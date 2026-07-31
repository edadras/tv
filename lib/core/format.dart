/// Formatting helpers for the Persian UI.
class Fmt {
  const Fmt._();

  static const _fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  /// Latin digits -> Persian digits, everything else untouched.
  static String digits(String s) {
    final b = StringBuffer();
    for (final unit in s.codeUnits) {
      b.write(unit >= 0x30 && unit <= 0x39 ? _fa[unit - 0x30] : String.fromCharCode(unit));
    }
    return b.toString();
  }

  /// `1:23:45` / `04:07`, always with Persian digits.
  static String duration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    String p(int v) => v.toString().padLeft(2, '0');
    final s = d.inHours > 0
        ? '${d.inHours}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}'
        : '${p(d.inMinutes)}:${p(d.inSeconds % 60)}';
    return digits(s);
  }

  /// Signed seconds with one decimal, e.g. `+۱٫۵ ثانیه`.
  static String offset(int ms) {
    final sign = ms > 0 ? '+' : (ms < 0 ? '−' : '');
    final abs = (ms.abs() / 1000).toStringAsFixed(1).replaceAll('.', '٫');
    return '$sign${digits(abs)}';
  }

  static String bytes(int n) {
    const units = ['بایت', 'کیلوبایت', 'مگابایت', 'گیگابایت'];
    var value = n.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    final text = i == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '${digits(text.replaceAll('.', '٫'))} ${units[i]}';
  }

  /// Trims release-scene noise out of a file name for the title line.
  static String title(String raw) {
    var s = raw.replaceAll(RegExp(r'[._]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty ? raw : s;
  }
}
