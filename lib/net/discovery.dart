import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/log.dart';
import '../model/protocol.dart';
import 'lan.dart';

/// A host (phone) seen on the network.
class DiscoveredHost {
  DiscoveredHost({required this.name, required this.url, required this.seenAt});

  final String name;
  final String url;
  DateTime seenAt;

  @override
  bool operator ==(Object other) => other is DiscoveredHost && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Zero-config discovery over UDP broadcast.
///
/// The phone announces itself twice a second while it is hosting; the TV both
/// listens for those announcements and can send a query to pull an immediate
/// reply. Two directions means the pair finds each other in well under a
/// second no matter which one started first.
class Discovery {
  Discovery._(this._socket);

  static const _magic = 'lancast';

  final RawDatagramSocket _socket;
  Timer? _announceTimer;
  String? _announceName;
  String? _announceUrl;

  final _hosts = <String, DiscoveredHost>{};
  final _controller = StreamController<List<DiscoveredHost>>.broadcast();

  /// Hosts seen recently, refreshed as announcements arrive.
  Stream<List<DiscoveredHost>> get hosts => _controller.stream;

  List<DiscoveredHost> get current => _hosts.values.toList();

  static Future<Discovery?> bind() async {
    // SO_REUSEPORT lets the phone and TV halves coexist on one device and
    // survives a restart with the socket still in TIME_WAIT, but not every
    // Android kernel allows it — so we fall back rather than lose discovery.
    for (final reusePort in [true, false]) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          kBeaconPort,
          reuseAddress: true,
          reusePort: reusePort,
        );
        socket.broadcastEnabled = true;
        return Discovery._(socket).._listen();
      } on SocketException catch (e) {
        logDebug('discovery bind (reusePort: $reusePort) failed: $e');
      } on OSError catch (e) {
        logDebug('discovery bind (reusePort: $reusePort) failed: $e');
      }
    }
    // Another app owns the port, or the platform forbids it. Discovery is only
    // a convenience — entering the address by hand still works.
    return null;
  }

  void _listen() {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _socket.receive();
      if (dg == null) return;
      Map<String, Object?> msg;
      try {
        msg = (jsonDecode(utf8.decode(dg.data)) as Map).cast<String, Object?>();
      } catch (_) {
        return;
      }
      if (msg['app'] != _magic) return;

      switch (msg['role']) {
        case 'host':
          final url = msg['url'] as String?;
          if (url == null) return;
          final host = DiscoveredHost(
            name: (msg['name'] as String?) ?? 'Phone',
            url: url,
            seenAt: DateTime.now(),
          );
          _hosts[url] = host;
          _prune();
          _controller.add(current);
        case 'seek':
          // A receiver is looking for us; answer straight away.
          if (_announceUrl != null) _send(dg.address);
      }
    });
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 8));
    _hosts.removeWhere((_, h) => h.seenAt.isBefore(cutoff));
  }

  /// Starts announcing this device as a host at [url].
  void announce({required String name, required String url}) {
    _announceName = name;
    _announceUrl = url;
    _announceTimer?.cancel();
    _broadcast();
    _announceTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _broadcast());
  }

  void stopAnnouncing() {
    _announceTimer?.cancel();
    _announceTimer = null;
    _announceUrl = null;
  }

  /// Asks any host on the network to announce itself immediately.
  Future<void> seek() async {
    final payload = utf8.encode(jsonEncode({'app': _magic, 'v': kProtocolVersion, 'role': 'seek'}));
    for (final target in await _broadcastTargets()) {
      try {
        _socket.send(payload, InternetAddress(target), kBeaconPort);
      } on SocketException {
        // Interface went away mid-scan; the other targets still stand.
      }
    }
  }

  Future<void> _broadcast() async {
    for (final target in await _broadcastTargets()) {
      _send(InternetAddress(target));
    }
  }

  void _send(InternetAddress to) {
    final url = _announceUrl;
    if (url == null) return;
    final payload = utf8.encode(jsonEncode({
      'app': _magic,
      'v': kProtocolVersion,
      'role': 'host',
      'name': _announceName ?? 'Phone',
      'url': url,
    }));
    try {
      _socket.send(payload, to, kBeaconPort);
    } on SocketException {
      // Non-fatal: the next tick tries again.
    }
  }

  Future<List<String>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    for (final ip in await Lan.addresses()) {
      final b = Lan.broadcastFor(ip);
      if (b != null) targets.add(b);
    }
    return targets.toList();
  }

  void dispose() {
    _announceTimer?.cancel();
    _controller.close();
    _socket.close();
  }
}
