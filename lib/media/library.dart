import 'dart:io';

import 'package:path/path.dart' as p;

/// File types we offer to cast.
const kVideoExtensions = {
  '.mp4', '.mkv', '.avi', '.mov', '.m4v', '.webm', '.ts', '.m2ts',
  '.flv', '.wmv', '.mpg', '.mpeg', '.3gp', '.ogv', '.divx', '.rmvb',
};

const kSubtitleExtensions = {'.srt', '.vtt', '.ass', '.ssa', '.sub'};

const _mimeByExt = {
  '.mp4': 'video/mp4',
  '.m4v': 'video/mp4',
  '.mov': 'video/quicktime',
  '.mkv': 'video/x-matroska',
  '.webm': 'video/webm',
  '.avi': 'video/x-msvideo',
  '.ts': 'video/mp2t',
  '.m2ts': 'video/mp2t',
  '.3gp': 'video/3gpp',
  '.flv': 'video/x-flv',
  '.wmv': 'video/x-ms-wmv',
  '.mpg': 'video/mpeg',
  '.mpeg': 'video/mpeg',
};

String mimeForPath(String path) =>
    _mimeByExt[p.extension(path).toLowerCase()] ?? 'video/mp4';

bool isVideoFile(String path) =>
    kVideoExtensions.contains(p.extension(path).toLowerCase());

bool isSubtitleFile(String path) =>
    kSubtitleExtensions.contains(p.extension(path).toLowerCase());

/// One row in the browser: a folder, a video or a subtitle.
class LibraryEntry {
  LibraryEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  bool get isVideo => !isDirectory && isVideoFile(path);
  bool get isSubtitle => !isDirectory && isSubtitleFile(path);
}

/// A plain filesystem browser. Using real paths (rather than copied-out
/// content URIs) is what keeps casting a 4 GB film instant — we stream the
/// original bytes and never duplicate them.
class Library {
  const Library._();

  static const roots = ['/storage/emulated/0', '/sdcard', '/storage'];

  /// Folders worth offering as one-tap shortcuts, when they exist.
  static Future<List<LibraryEntry>> shortcuts() async {
    const candidates = [
      'Download', 'Downloads', 'Movies', 'Video', 'Videos', 'DCIM/Camera',
      'Telegram/Telegram Video', 'Documents', 'bluetooth', 'Music',
    ];
    final out = <LibraryEntry>[];
    final base = await defaultRoot();
    if (base == null) return out;
    for (final c in candidates) {
      final dir = Directory(p.join(base, c));
      if (await dir.exists()) {
        out.add(LibraryEntry(path: dir.path, name: c, isDirectory: true));
      }
    }
    return out;
  }

  static Future<String?> defaultRoot() async {
    for (final r in roots) {
      if (await Directory(r).exists()) return r;
    }
    return null;
  }

  /// Lists [path], folders first then files, both alphabetically.
  /// Hidden entries and unreadable folders are skipped rather than thrown.
  static Future<List<LibraryEntry>> list(String path, {bool videosOnly = true}) async {
    final dir = Directory(path);
    final entries = <LibraryEntry>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        try {
          final stat = await e.stat();
          if (stat.type == FileSystemEntityType.directory) {
            entries.add(LibraryEntry(
              path: e.path,
              name: name,
              isDirectory: true,
              modified: stat.modified,
            ));
          } else {
            final keep = videosOnly
                ? isVideoFile(e.path) || isSubtitleFile(e.path)
                : true;
            if (!keep) continue;
            entries.add(LibraryEntry(
              path: e.path,
              name: name,
              isDirectory: false,
              size: stat.size,
              modified: stat.modified,
            ));
          }
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return entries;
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// Subtitle files that belong to [videoPath]: same folder, and either the
  /// same base name or inside a `Subs`/`Subtitles` sub-folder next to it.
  /// This is what makes "pick a film, subtitles are already there" work.
  static Future<List<String>> siblingSubtitles(String videoPath) async {
    final dir = Directory(p.dirname(videoPath));
    final stem = p.basenameWithoutExtension(videoPath).toLowerCase();
    final found = <String>[];

    Future<void> scan(Directory d, {required bool requireStem}) async {
      try {
        await for (final e in d.list(followLinks: false)) {
          if (e is! File || !isSubtitleFile(e.path)) continue;
          final name = p.basenameWithoutExtension(e.path).toLowerCase();
          if (!requireStem || name.startsWith(stem) || stem.startsWith(name)) {
            found.add(e.path);
          }
        }
      } on FileSystemException {
        // Unreadable folder: just means no auto-attached subtitles.
      }
    }

    await scan(dir, requireStem: true);
    for (final sub in const ['Subs', 'subs', 'Subtitles', 'subtitles']) {
      final nested = Directory(p.join(dir.path, sub));
      if (await nested.exists()) await scan(nested, requireStem: false);
      final byName = Directory(p.join(dir.path, p.basenameWithoutExtension(videoPath)));
      if (await byName.exists()) await scan(byName, requireStem: false);
    }
    final unique = found.toSet().toList()..sort();
    return unique;
  }

  /// Best-effort recursive hunt for videos, bounded so it stays snappy.
  static Future<List<LibraryEntry>> recentVideos({int limit = 60}) async {
    final base = await defaultRoot();
    if (base == null) return [];
    final found = <LibraryEntry>[];
    final queue = <String>[base];
    var visited = 0;

    while (queue.isNotEmpty && found.length < limit && visited < 400) {
      final current = queue.removeAt(0);
      visited++;
      try {
        await for (final e in Directory(current).list(followLinks: false)) {
          final name = p.basename(e.path);
          if (name.startsWith('.') || name == 'Android') continue;
          final stat = await e.stat();
          if (stat.type == FileSystemEntityType.directory) {
            queue.add(e.path);
          } else if (isVideoFile(e.path) && stat.size > 1024 * 1024) {
            found.add(LibraryEntry(
              path: e.path,
              name: name,
              isDirectory: false,
              size: stat.size,
              modified: stat.modified,
            ));
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    found.sort((a, b) =>
        (b.modified ?? DateTime(1970)).compareTo(a.modified ?? DateTime(1970)));
    return found.take(limit).toList();
  }
}
