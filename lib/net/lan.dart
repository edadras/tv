import 'dart:io';

/// Helpers for finding this device on the local network.
class Lan {
  const Lan._();

  /// All usable IPv4 addresses, Wi-Fi/Ethernet first and hotspot-style
  /// interfaces last, so the address we show the user is the one their TV
  /// can actually reach.
  static Future<List<String>> addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );
    final scored = <MapEntry<int, String>>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue;
        scored.add(MapEntry(_score(iface.name, ip), ip));
      }
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    return [for (final e in scored) e.value];
  }

  static Future<String?> primaryAddress() async => (await addresses()).firstOrNull;

  static int _score(String iface, String ip) {
    var s = 0;
    final n = iface.toLowerCase();
    if (n.startsWith('wlan') || n.startsWith('wl') || n.startsWith('en')) s += 40;
    if (n.startsWith('eth') || n.startsWith('rndis')) s += 30;
    if (n.startsWith('ap') || n.startsWith('swlan')) s += 10; // hotspot
    if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('tun')) s -= 40; // cellular/vpn
    if (ip.startsWith('192.168.')) s += 20;
    if (ip.startsWith('10.')) s += 12;
    if (ip.startsWith('172.')) s += 8;
    return s;
  }

  /// Directed broadcast address for a /24, e.g. 192.168.1.5 -> 192.168.1.255.
  /// Routers that drop 255.255.255.255 usually still pass this one.
  static String? broadcastFor(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
