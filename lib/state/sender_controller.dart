import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/device.dart';
import '../core/log.dart';
import '../core/prefs.dart';
import '../media/library.dart';
import '../media/url_source.dart';
import '../model/protocol.dart';
import '../net/discovery.dart';
import '../net/host_server.dart';
import '../net/lan.dart';

/// Phone-side brain: hosts the files, tracks the receivers and holds the
/// remote-control state the UI renders.
class SenderController extends ChangeNotifier {
  SenderController(this.facts) {
    _server = HostServer(deviceName: facts.name)
      ..apkPath = facts.apkPath
      ..assetLoader = _loadAsset;
    _style = Prefs.instance.subtitleStyle;
  }

  final DeviceFacts facts;
  late final HostServer _server;
  Discovery? _discovery;

  StreamSubscription<void>? _peersSub;
  StreamSubscription<void>? _stateSub;
  StreamSubscription<void>? _joinSub;
  Timer? _resumeSaver;

  String? _address;
  CastMedia? _media;
  PlayerSnapshot _snapshot = const PlayerSnapshot();
  SubtitleStyleSpec _style = const SubtitleStyleSpec();
  String? _error;
  bool _starting = false;

  /// Set while the user drags the scrubber so incoming state does not fight it.
  double? _scrubTarget;

  // --- read-only view for the UI -----------------------------------------

  String? get address => _address;
  String get shareUrl => _address == null ? '' : 'http://$_address:${_server.port}';
  CastMedia? get media => _media;
  PlayerSnapshot get snapshot => _snapshot;
  SubtitleStyleSpec get style => _style;
  String? get error => _error;
  bool get isHosting => _server.running;
  bool get starting => _starting;
  List<ReceiverPeer> get receivers => _server.peers;
  bool get hasReceiver => _server.peers.isNotEmpty;
  List<SubtitleTrack> get subtitles => _media?.subtitles ?? const [];

  /// Position to draw: the drag target while scrubbing, else the real one.
  double get displayProgress => _scrubTarget ?? _snapshot.progress;

  Duration get displayPosition => _scrubTarget == null
      ? _snapshot.position
      : Duration(milliseconds: (_snapshot.durationMs * _scrubTarget!).round());

  /// Lets the browser player pull the bundled Persian font off the phone.
  static Future<List<int>?> _loadAsset(String key) async {
    try {
      return (await rootBundle.load(key)).buffer.asUint8List();
    } catch (e) {
      logDebug('asset \$key unavailable: \$e');
      return null;
    }
  }

  // --- lifecycle ----------------------------------------------------------

  Future<void> start() async {
    if (_server.running || _starting) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      await _server.start();
      _address = await Lan.primaryAddress();
      if (_address == null) {
        _error = 'به یک شبکه‌ی وای‌فای وصل شوید';
      }

      _peersSub = _server.peersStream.listen((_) => notifyListeners());

      // Catch a late joiner up on its own, so a receiver leaving never
      // restarts the film on the ones that stayed.
      _joinSub = _server.joinStream.listen((peer) {
        final m = _media;
        if (m == null) return;
        _server.sendTo(
          peer,
          CastCommand.load(m, startMs: _snapshot.positionMs, subId: _snapshot.subId),
        );
        _server.sendTo(peer, CastCommand.subStyle(_style));
        if (_snapshot.subDelayMs != 0) {
          _server.sendTo(peer, CastCommand.subDelay(_snapshot.subDelayMs));
        }
      });

      _stateSub = _server.stateStream.listen((snap) {
        _snapshot = snap;
        notifyListeners();
      });

      _discovery ??= await Discovery.bind();
      final addr = _address;
      if (addr != null) {
        _discovery?.announce(name: facts.name, url: shareUrl);
      }

      _resumeSaver = Timer.periodic(const Duration(seconds: 5), (_) => _saveResume());
    } on SocketException catch (e) {
      _error = 'سرور اجرا نشد: ${e.message}';
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stopHosting() async {
    _discovery?.stopAnnouncing();
    await _server.stop();
    notifyListeners();
  }

  void _saveResume() {
    final m = _media;
    if (m == null || _snapshot.durationMs <= 0 || _snapshot.live) return;
    // Don't "resume" the last few seconds of a film.
    final atEnd = _snapshot.positionMs > _snapshot.durationMs - 15000;
    unawaited(Prefs.instance.setResumeFor(m.path, atEnd ? 0 : _snapshot.positionMs));
  }

  @override
  void dispose() {
    _resumeSaver?.cancel();
    _peersSub?.cancel();
    _stateSub?.cancel();
    _joinSub?.cancel();
    _discovery?.dispose();
    _server.dispose();
    super.dispose();
  }

  // --- casting ------------------------------------------------------------

  /// Publishes [path] and tells every receiver to play it.
  /// Subtitles sitting next to the file are attached automatically.
  Future<void> castFile(String path, {bool resume = true}) async {
    final file = File(path);
    if (!await file.exists()) {
      _error = 'فایل پیدا نشد';
      notifyListeners();
      return;
    }
    if (!_server.running) await start();

    final id = _idFor(path);
    final subs = <SubtitleTrack>[];
    for (final s in await Library.siblingSubtitles(path)) {
      subs.add(SubtitleTrack(
        id: _idFor(s),
        label: p.basenameWithoutExtension(s),
        path: s,
      ));
    }

    final media = CastMedia(
      id: id,
      title: p.basenameWithoutExtension(path),
      path: path,
      size: await file.length(),
      kind: MediaKind.file,
      mime: mimeForPath(path),
      subtitles: subs,
    );
    _media = media;
    _server.publish(media);

    final startMs = resume ? Prefs.instance.resumeFor(path) : 0;
    final delay = Prefs.instance.subDelayFor(path);

    _snapshot = PlayerSnapshot(
      title: media.title,
      positionMs: startMs,
      subs: subs,
      subDelayMs: delay,
      style: _style,
    );

    _server.send(CastCommand.load(
      media,
      startMs: startMs,
      subId: subs.isNotEmpty ? subs.first.id : null,
    ));
    _server.send(CastCommand.subStyle(_style));
    if (delay != 0) _server.send(CastCommand.subDelay(delay));
    notifyListeners();
  }

  /// Casts a pasted link — a direct video URL, a live stream manifest or a
  /// YouTube video. Nothing is downloaded or proxied through the phone: the
  /// TV fetches it itself, so quality is limited by the TV's connection
  /// rather than by a round trip through here.
  Future<void> castLink(UrlSource source) async {
    if (!_server.running) await start();

    final media = CastMedia(
      id: _idFor(source.url),
      title: source.title,
      path: source.url,
      size: 0,
      kind: source.kind,
      youtubeId: source.youtubeId,
    );
    _media = media;
    _server.publish(media);
    unawaited(Prefs.instance.rememberLink(source.url));

    // A timestamped link wins; then our own resume point; a live stream
    // always starts at the edge.
    final startMs = switch (source.kind) {
      MediaKind.adaptive => 0,
      _ when source.startAt > Duration.zero => source.startAt.inMilliseconds,
      _ => Prefs.instance.resumeFor(source.url),
    };

    _snapshot = PlayerSnapshot(
      title: media.title,
      positionMs: startMs,
      style: _style,
      kind: source.kind,
    );

    _server.send(CastCommand.load(media, startMs: startMs));
    _server.send(CastCommand.subStyle(_style));
    notifyListeners();
  }

  /// Adds a subtitle file the user picked by hand.
  Future<void> addSubtitle(String path) async {
    final m = _media;
    if (m == null) return;
    final track = SubtitleTrack(
      id: _idFor(path),
      label: p.basenameWithoutExtension(path),
      path: path,
    );
    if (m.subtitles.any((s) => s.id == track.id)) {
      selectSubtitle(track.id);
      return;
    }
    final updated = m.copyWith(subtitles: [...m.subtitles, track]);
    _media = updated;
    _server.publish(updated);
    _server.send(CastCommand.addSub(track));
    selectSubtitle(track.id);
    notifyListeners();
  }

  // --- transport ----------------------------------------------------------

  void play() {
    _server.send(CastCommand.play);
    _optimistic(playing: true);
  }

  void pause() {
    _server.send(CastCommand.pause);
    _optimistic(playing: false);
  }

  void togglePlay() => _snapshot.playing ? pause() : play();

  void stop() {
    _saveResume();
    _server.send(CastCommand.stop);
    _snapshot = const PlayerSnapshot();
    notifyListeners();
  }

  void nudge(int ms) {
    _server.send(CastCommand.nudge(ms));
    final target = (_snapshot.positionMs + ms).clamp(0, _snapshot.durationMs);
    _snapshot = _copy(positionMs: target);
    notifyListeners();
  }

  /// Called continuously while the scrubber is dragged.
  void scrubTo(double fraction) {
    _scrubTarget = fraction.clamp(0, 1);
    notifyListeners();
  }

  /// Called when the finger lifts.
  void commitScrub() {
    final t = _scrubTarget;
    _scrubTarget = null;
    if (t == null || _snapshot.durationMs <= 0) {
      notifyListeners();
      return;
    }
    final ms = (_snapshot.durationMs * t).round();
    _server.send(CastCommand.seek(ms));
    _snapshot = _copy(positionMs: ms);
    notifyListeners();
  }

  void seekTo(Duration position) {
    _server.send(CastCommand.seek(position.inMilliseconds));
    _snapshot = _copy(positionMs: position.inMilliseconds);
    notifyListeners();
  }

  void setRate(double rate) {
    _server.send(CastCommand.rate(rate));
    _snapshot = _copy(rate: rate);
    notifyListeners();
  }

  void setVolume(double v) {
    _server.send(CastCommand.volume(v));
    _snapshot = _copy(volume: v);
    notifyListeners();
  }

  void setFit(VideoFit fit) {
    _server.send(CastCommand.fit(fit));
    _snapshot = _copy(fit: fit);
    notifyListeners();
  }

  // --- subtitles ----------------------------------------------------------

  void selectSubtitle(String? id) {
    _server.send(CastCommand.selectSub(id));
    _snapshot = _copy(subId: id, clearSub: id == null);
    notifyListeners();
  }

  /// Positive = subtitles appear later, negative = earlier.
  void setSubDelay(int ms) {
    final clamped = ms.clamp(-60000, 60000);
    _server.send(CastCommand.subDelay(clamped));
    _snapshot = _copy(subDelayMs: clamped);
    final m = _media;
    if (m != null) unawaited(Prefs.instance.setSubDelayFor(m.path, clamped));
    notifyListeners();
  }

  void nudgeSubDelay(int deltaMs) => setSubDelay(_snapshot.subDelayMs + deltaMs);

  void setStyle(SubtitleStyleSpec style) {
    _style = style;
    _server.send(CastCommand.subStyle(style));
    _snapshot = _copy(style: style);
    unawaited(Prefs.instance.setSubtitleStyle(style));
    notifyListeners();
  }

  // --- helpers ------------------------------------------------------------

  void _optimistic({required bool playing}) {
    _snapshot = _copy(playing: playing);
    notifyListeners();
  }

  /// The UI must feel instant, so we mirror the command locally and let the
  /// receiver's next state push (250 ms) correct us if it disagrees.
  PlayerSnapshot _copy({
    int? positionMs,
    bool? playing,
    String? subId,
    bool clearSub = false,
    int? subDelayMs,
    double? rate,
    double? volume,
    VideoFit? fit,
    SubtitleStyleSpec? style,
  }) {
    final s = _snapshot;
    return PlayerSnapshot(
      title: s.title,
      positionMs: positionMs ?? s.positionMs,
      durationMs: s.durationMs,
      bufferedMs: s.bufferedMs,
      playing: playing ?? s.playing,
      buffering: s.buffering,
      ready: s.ready,
      error: s.error,
      subId: clearSub ? null : (subId ?? s.subId),
      subDelayMs: subDelayMs ?? s.subDelayMs,
      rate: rate ?? s.rate,
      volume: volume ?? s.volume,
      fit: fit ?? s.fit,
      style: style ?? s.style,
      subs: s.subs.isEmpty ? subtitles : s.subs,
      receiver: s.receiver,
      live: s.live,
      kind: s.kind,
      quality: s.quality,
    );
  }

  static String _idFor(String path) {
    // Stable, short and safe in a URL.
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
    }
    return hash.toRadixString(36);
  }
}
