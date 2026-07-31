import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/log.dart';
import '../model/protocol.dart';
import '../subs/subtitle_doc.dart';
import 'web_assets.dart';

/// A receiver currently attached to the hub.
class ReceiverPeer {
  ReceiverPeer(this.socket, this.name, this.kind);

  final WebSocket socket;
  final String name;

  /// `tv` for the native app, `web` for the browser player.
  final String kind;
  PlayerSnapshot? last;
}

/// The phone side: a tiny HTTP server that streams the chosen file to the TV
/// and a WebSocket hub that carries the remote-control protocol.
///
/// Deliberately built on `dart:io` alone — no server framework, no extra
/// packages, so startup is instant and the byte path is as short as possible.
class HostServer {
  HostServer({required this.deviceName});

  final String deviceName;

  HttpServer? _server;
  final _media = <String, CastMedia>{};
  final _subs = <String, SubtitleTrack>{};
  final _subCache = <String, List<int>>{};
  final _peers = <ReceiverPeer>[];

  /// Path to this app's own APK, published at `/app.apk` so the TV browser can
  /// download and sideload it. Null when unknown.
  String? apkPath;

  /// Reads a bundled asset. Set by the app layer so `/font/*.ttf` can hand the
  /// Persian font to a smart TV browser that has none of its own. Left null
  /// (in tests, or on a host without assets) the page falls back to whatever
  /// fonts the TV already has.
  Future<List<int>?> Function(String assetKey)? assetLoader;

  final _peersController = StreamController<List<ReceiverPeer>>.broadcast();
  final _stateController = StreamController<PlayerSnapshot>.broadcast();
  final _joinController = StreamController<ReceiverPeer>.broadcast();

  /// The peer whose state we surface. With a TV app and a browser tab both
  /// attached their snapshots would otherwise interleave and make the remote
  /// jitter, so one of them owns the readout.
  ReceiverPeer? _primary;

  Stream<List<ReceiverPeer>> get peersStream => _peersController.stream;
  Stream<PlayerSnapshot> get stateStream => _stateController.stream;

  /// Fires once per receiver, when it attaches.
  Stream<ReceiverPeer> get joinStream => _joinController.stream;

  List<ReceiverPeer> get peers => List.unmodifiable(_peers);
  bool get running => _server != null;
  int get port => _server?.port ?? kHttpPort;

  /// Binds the server, falling back to nearby ports if the default is taken.
  Future<void> start() async {
    if (_server != null) return;
    for (var p = kHttpPort; p < kHttpPort + 12; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p, shared: true);
        break;
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) {
      throw const SocketException('No free port for the cast server');
    }
    server.autoCompress = false;
    server.idleTimeout = const Duration(minutes: 30);
    unawaited(server.forEach(_handle).catchError((Object e) {
      logDebug('host server stopped: $e');
    }));
  }

  Future<void> stop() async {
    for (final p in List.of(_peers)) {
      await p.socket.close().catchError((_) => null);
    }
    _peers.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void dispose() {
    _peersController.close();
    _stateController.close();
    _joinController.close();
    unawaited(stop());
  }

  // --- session ------------------------------------------------------------

  /// Publishes [media] (and its subtitles) so receivers can fetch them.
  void publish(CastMedia media) {
    _media[media.id] = media;
    for (final s in media.subtitles) {
      _subs[s.id] = s;
    }
  }

  void publishSubtitle(SubtitleTrack track) => _subs[track.id] = track;

  /// Sends a command to every attached receiver.
  void send(CastCommand command) {
    final payload = jsonEncode(command.toJson());
    for (final peer in List.of(_peers)) {
      _write(peer, payload);
    }
  }

  /// Sends a command to one receiver — used to catch a late joiner up without
  /// disturbing anything already playing.
  void sendTo(ReceiverPeer peer, CastCommand command) =>
      _write(peer, jsonEncode(command.toJson()));

  void _write(ReceiverPeer peer, String payload) {
    try {
      peer.socket.add(payload);
    } catch (_) {
      _drop(peer);
    }
  }

  // --- HTTP ---------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Cache-Control', 'no-store');

    final path = req.uri.path;
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.ok;
        await res.close();
        return;
      }
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        await _upgrade(req);
        return;
      }
      if (path == '/' || path == '/index.html') {
        return _text(res, WebAssets.playerPage(deviceName), 'text/html; charset=utf-8');
      }
      if (path == '/info') {
        return _text(
          res,
          jsonEncode({
            'app': 'lancast',
            'v': kProtocolVersion,
            'name': deviceName,
            'media': _media.values.map((m) => m.toJson()).toList(),
            'apk': apkPath != null,
          }),
          'application/json; charset=utf-8',
        );
      }
      if (path == '/app.apk') return _serveApk(req);
      if (path.startsWith('/font/')) return _serveFont(req, path.substring(6));
      if (path.startsWith('/media/')) return _serveMedia(req, path.substring(7));
      if (path.startsWith('/sub/')) return _serveSub(req, path.substring(5));

      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (e) {
      logDebug('request $path failed: $e');
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {
        // Client already gone.
      }
    }
  }

  Future<void> _text(HttpResponse res, String body, String type) async {
    final bytes = utf8.encode(body);
    res.headers
      ..contentType = ContentType.parse(type)
      ..contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  Future<void> _serveSub(HttpRequest req, String name) async {
    final id = name.endsWith('.vtt') ? name.substring(0, name.length - 4) : name;
    final track = _subs[id];
    final res = req.response;
    if (track == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    var bytes = _subCache[id];
    if (bytes == null) {
      // Convert once, on demand: any encoding and format in, WebVTT out.
      final doc = SubtitleDoc.parseBytes(await File(track.path).readAsBytes());
      bytes = utf8.encode(doc.toVtt());
      _subCache[id] = bytes;
    }
    res.headers
      ..contentType = ContentType.parse('text/vtt; charset=utf-8')
      ..contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  /// Only the two weights the browser page asks for, by fixed name — the
  /// asset path is never taken from the request.
  static const _fonts = {
    'regular.ttf': 'assets/fonts/Vazirmatn-Regular.ttf',
    'bold.ttf': 'assets/fonts/Vazirmatn-Bold.ttf',
  };

  Future<void> _serveFont(HttpRequest req, String name) async {
    final res = req.response;
    final asset = _fonts[name];
    final loader = assetLoader;
    if (asset == null || loader == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final bytes = await loader(asset);
    if (bytes == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers
      ..contentType = ContentType('font', 'ttf')
      ..set('Cache-Control', 'public, max-age=604800')
      ..contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  Future<void> _serveApk(HttpRequest req) async {
    final res = req.response;
    final path = apkPath;
    if (path == null || !File(path).existsSync()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers
      ..contentType = ContentType('application', 'vnd.android.package-archive')
      ..set('Content-Disposition', 'attachment; filename="LanCast.apk"');
    await _sendFile(req, File(path));
  }

  Future<void> _serveMedia(HttpRequest req, String id) async {
    final media = _media[id];
    final res = req.response;
    if (media == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final file = File(media.path);
    if (!file.existsSync()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.parse(media.mime);
    await _sendFile(req, file);
  }

  /// Streams [file] honouring `Range`, which is what lets the TV seek
  /// instantly instead of re-downloading from the start.
  Future<void> _sendFile(HttpRequest req, File file) async {
    final res = req.response;
    final length = await file.length();
    res.headers.set('Accept-Ranges', 'bytes');

    var start = 0;
    var end = length - 1;
    final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
    final match = rangeHeader == null
        ? null
        : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);

    if (match != null) {
      final rawStart = match.group(1) ?? '';
      final rawEnd = match.group(2) ?? '';
      if (rawStart.isEmpty && rawEnd.isNotEmpty) {
        // Suffix range: the last N bytes.
        final n = int.parse(rawEnd);
        start = n >= length ? 0 : length - n;
      } else if (rawStart.isNotEmpty) {
        start = int.parse(rawStart);
        if (rawEnd.isNotEmpty) end = int.parse(rawEnd);
      }
      if (end >= length) end = length - 1;
      if (start > end || start >= length) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await res.close();
        return;
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }

    res.headers.contentLength = end - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    try {
      await res.addStream(file.openRead(start, end + 1));
      await res.close();
    } catch (_) {
      // Seeking or stopping cancels the transfer mid-flight; that is normal.
      try {
        await res.close();
      } catch (_) {
        // Already torn down.
      }
    }
  }

  // --- WebSocket hub ------------------------------------------------------

  Future<void> _upgrade(HttpRequest req) async {
    final socket = await WebSocketTransformer.upgrade(req);
    final query = req.uri.queryParameters;
    final peer = ReceiverPeer(
      socket,
      query['name'] ?? 'Receiver',
      query['kind'] ?? 'web',
    );
    _peers.add(peer);
    _primary ??= peer;
    _peersController.add(peers);
    _joinController.add(peer);

    socket.add(jsonEncode({'t': 'hello', 'v': kProtocolVersion, 'host': deviceName}));

    socket.listen(
      (Object? data) {
        if (data is! String) return;
        Map<String, Object?> msg;
        try {
          msg = (jsonDecode(data) as Map).cast<String, Object?>();
        } catch (_) {
          return;
        }
        if (msg['t'] == 'state') {
          final snap = PlayerSnapshot.fromJson(msg);
          peer.last = snap;
          // A receiver that actually has a film loaded outranks an idle one.
          if (_primary == null ||
              _primary == peer ||
              !(_primary!.last?.ready ?? false)) {
            if (snap.ready || _primary == peer) _primary = peer;
          }
          if (_primary == peer) _stateController.add(snap);
        }
      },
      onDone: () => _drop(peer),
      onError: (_) => _drop(peer),
      cancelOnError: true,
    );
  }

  void _drop(ReceiverPeer peer) {
    if (_peers.remove(peer)) {
      unawaited(peer.socket.close().catchError((_) => null));
      if (_primary == peer) _primary = _peers.isEmpty ? null : _peers.first;
      if (!_peersController.isClosed) _peersController.add(peers);
    }
  }
}
