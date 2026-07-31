import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/log.dart';
import '../model/protocol.dart';

enum LinkStatus { idle, connecting, connected, retrying, failed }

/// The TV side of the control channel: keeps a WebSocket to the phone alive,
/// surfaces incoming commands and pushes player state back.
class ReceiverLink {
  ReceiverLink({required this.deviceName});

  final String deviceName;

  WebSocket? _socket;
  String? _baseUrl;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;

  final _commands = StreamController<CastCommand>.broadcast();
  final _status = StreamController<LinkStatus>.broadcast();

  Stream<CastCommand> get commands => _commands.stream;
  Stream<LinkStatus> get statusStream => _status.stream;

  LinkStatus status = LinkStatus.idle;

  /// `http://ip:port` of the phone we are attached to, once connected.
  String? get baseUrl => _baseUrl;
  bool get isConnected => status == LinkStatus.connected;

  /// Resolves a relative URL from the protocol against the connected host.
  String? resolve(String path) {
    final base = _baseUrl;
    if (base == null) return null;
    if (path.startsWith('http')) return path;
    return '$base$path';
  }

  void _setStatus(LinkStatus s) {
    status = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Connects to a host given as `http://ip:port`, `ip:port` or just `ip`.
  Future<void> connect(String host) async {
    _retryTimer?.cancel();
    _attempt = 0;
    _baseUrl = normalizeHost(host);
    await _open();
  }

  static String normalizeHost(String raw) {
    var h = raw.trim();
    if (h.startsWith('ws://')) h = 'http://${h.substring(5)}';
    if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'http://$h';
    final uri = Uri.parse(h);
    final port = uri.hasPort ? uri.port : kHttpPort;
    return '${uri.scheme}://${uri.host}:$port';
  }

  Future<void> _open() async {
    final base = _baseUrl;
    if (base == null || _disposed) return;
    _setStatus(_attempt == 0 ? LinkStatus.connecting : LinkStatus.retrying);

    final wsUrl = '${base.replaceFirst('http', 'ws')}/ws'
        '?kind=tv&name=${Uri.encodeComponent(deviceName)}';
    try {
      final socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 6));
      if (_disposed) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _attempt = 0;
      _setStatus(LinkStatus.connected);

      socket.listen(
        (Object? data) {
          if (data is! String) return;
          try {
            final msg = (jsonDecode(data) as Map).cast<String, Object?>();
            if (msg['t'] == 'hello') return;
            _commands.add(CastCommand.fromJson(msg));
          } catch (e) {
            logDebug('bad command: $e');
          }
        },
        onDone: _scheduleRetry,
        onError: (Object _) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (e) {
      logDebug('connect to $wsUrl failed: $e');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _socket = null;
    if (_disposed || _baseUrl == null) return;
    _attempt++;
    if (_attempt > 40) {
      _setStatus(LinkStatus.failed);
      return;
    }
    _setStatus(LinkStatus.retrying);
    // Back off quickly at first (the phone may just be switching screens),
    // then settle to a 5s heartbeat so a phone coming back is picked up fast.
    final delayMs = (300 * _attempt).clamp(300, 5000);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), _open);
  }

  void report(PlayerSnapshot snapshot) {
    final s = _socket;
    if (s == null || s.readyState != WebSocket.open) return;
    try {
      s.add(jsonEncode(snapshot.toJson()));
    } catch (_) {
      _scheduleRetry();
    }
  }

  Future<void> disconnect() async {
    _retryTimer?.cancel();
    _baseUrl = null;
    final s = _socket;
    _socket = null;
    await s?.close().catchError((_) => null);
    _setStatus(LinkStatus.idle);
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    unawaited(_socket?.close().catchError((_) => null));
    _commands.close();
    _status.close();
  }
}
