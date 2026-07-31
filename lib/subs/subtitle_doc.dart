import 'dart:typed_data';

import '../core/text_codec.dart';

/// A single timed line group.
class Cue {
  const Cue(this.startMs, this.endMs, this.text);

  final int startMs;
  final int endMs;

  /// Plain text, `\n` separated. Markup is already stripped.
  final String text;
}

/// A parsed subtitle file plus the cursor used to look cues up while playing.
///
/// Lookup is O(1) amortised during normal playback (the cursor walks forward)
/// and O(log n) after a seek, which keeps it free even on a slow TV box.
class SubtitleDoc {
  SubtitleDoc(this.cues);

  final List<Cue> cues;

  int _cursor = 0;

  bool get isEmpty => cues.isEmpty;

  /// The cue visible at [ms], or null. [ms] must already have the sync
  /// offset applied by the caller.
  Cue? cueAt(int ms) {
    if (cues.isEmpty) return null;

    // Fast path: we are at or just after the cached cue.
    if (_cursor < cues.length) {
      final c = cues[_cursor];
      if (ms >= c.startMs && ms < c.endMs) return c;
      if (ms >= c.endMs && _cursor + 1 < cues.length) {
        final n = cues[_cursor + 1];
        if (ms < n.startMs) return null;
        if (ms < n.endMs) {
          _cursor++;
          return n;
        }
      }
    }

    // Slow path (seek): binary search for the last cue starting at or before ms.
    var lo = 0, hi = cues.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].startMs <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) {
      _cursor = 0;
      return null;
    }
    _cursor = found;
    final c = cues[found];
    return ms < c.endMs ? c : null;
  }

  void resetCursor() => _cursor = 0;

  /// Parses SRT, WebVTT or ASS/SSA from raw file bytes.
  static SubtitleDoc parseBytes(Uint8List bytes) => parse(TextCodec.decode(bytes));

  static SubtitleDoc parse(String text) {
    final head = text.trimLeft();
    if (head.startsWith('WEBVTT')) return SubtitleDoc(_parseVtt(text));
    if (head.startsWith('[Script Info]') || head.contains('[Events]')) {
      return SubtitleDoc(_parseAss(text));
    }
    return SubtitleDoc(_parseSrt(text));
  }

  /// Re-emits the document as WebVTT so the browser player can consume it.
  String toVtt() {
    final b = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < cues.length; i++) {
      final c = cues[i];
      b
        ..write(i + 1)
        ..write('\n')
        ..write(_vttStamp(c.startMs))
        ..write(' --> ')
        ..write(_vttStamp(c.endMs))
        ..write('\n')
        ..write(c.text)
        ..write('\n\n');
    }
    return b.toString();
  }

  static String _vttStamp(int ms) {
    final d = Duration(milliseconds: ms < 0 ? 0 : ms);
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}'
        '.${p(d.inMilliseconds % 1000, 3)}';
  }

  // --- parsers -------------------------------------------------------------

  static final _srtArrow = RegExp(
    r'(\d{1,3}):(\d{1,2}):(\d{1,2})[,.](\d{1,3})\s*-->\s*'
    r'(\d{1,3}):(\d{1,2}):(\d{1,2})[,.](\d{1,3})',
  );

  static List<Cue> _parseSrt(String text) {
    final cues = <Cue>[];
    final lines = text.split('\n');
    var i = 0;
    while (i < lines.length) {
      final m = _srtArrow.firstMatch(lines[i]);
      if (m == null) {
        i++;
        continue;
      }
      final start = _stamp(m, 1);
      final end = _stamp(m, 5);
      i++;
      final body = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        // A bare index line directly before the next timing belongs to it.
        if (i + 1 < lines.length &&
            _isIndex(lines[i]) &&
            _srtArrow.hasMatch(lines[i + 1])) {
          break;
        }
        body.add(lines[i]);
        i++;
      }
      final txt = _stripTags(body.join('\n').trim());
      if (txt.isNotEmpty && end > start) cues.add(Cue(start, end, txt));
    }
    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static List<Cue> _parseVtt(String text) {
    // WebVTT timings are the same shape as SRT with a dot separator, so the
    // SRT scanner handles both; we only need to drop NOTE/STYLE blocks.
    final cleaned = text
        .split('\n\n')
        .where((b) {
          final t = b.trimLeft();
          return !t.startsWith('NOTE') && !t.startsWith('STYLE') && !t.startsWith('REGION');
        })
        .join('\n\n');
    return _parseSrt(cleaned);
  }

  static final _assLine = RegExp(r'^Dialogue:\s*(.*)$', multiLine: true);
  static final _assStamp = RegExp(r'(\d+):(\d{1,2}):(\d{1,2})[.,](\d{1,2})');

  static List<Cue> _parseAss(String text) {
    // Find the field order declared by the Format: line inside [Events].
    var startIdx = 1, endIdx = 2, textIdx = 9;
    final fmt = RegExp(r'^Format:\s*(.*)$', multiLine: true)
        .allMatches(text)
        .map((m) => m.group(1)!)
        .where((f) => f.contains('Start') && f.contains('Text'))
        .firstOrNull;
    if (fmt != null) {
      final fields = [for (final f in fmt.split(',')) f.trim().toLowerCase()];
      startIdx = fields.indexOf('start');
      endIdx = fields.indexOf('end');
      textIdx = fields.indexOf('text');
    }
    final cues = <Cue>[];
    for (final m in _assLine.allMatches(text)) {
      // Text is always last and may itself contain commas.
      final parts = m.group(1)!.split(',');
      if (parts.length <= textIdx || startIdx < 0 || endIdx < 0) continue;
      final start = _assTime(parts[startIdx]);
      final end = _assTime(parts[endIdx]);
      if (start == null || end == null || end <= start) continue;
      final raw = parts.sublist(textIdx).join(',');
      final txt = _stripTags(
        raw.replaceAll(RegExp(r'\{[^}]*\}'), '').replaceAll(RegExp(r'\\[Nnh]'), '\n').trim(),
      );
      if (txt.isNotEmpty) cues.add(Cue(start, end, txt));
    }
    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static int? _assTime(String s) {
    final m = _assStamp.firstMatch(s.trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 3600000 +
        int.parse(m.group(2)!) * 60000 +
        int.parse(m.group(3)!) * 1000 +
        int.parse(m.group(4)!.padRight(3, '0'));
  }

  static int _stamp(RegExpMatch m, int g) =>
      int.parse(m.group(g)!) * 3600000 +
      int.parse(m.group(g + 1)!) * 60000 +
      int.parse(m.group(g + 2)!) * 1000 +
      int.parse(m.group(g + 3)!.padRight(3, '0'));

  static bool _isIndex(String line) => RegExp(r'^\d+$').hasMatch(line.trim());

  static final _tag = RegExp(r'</?[a-zA-Z][^>]*>');

  static String _stripTags(String s) => s
      .replaceAll(_tag, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
