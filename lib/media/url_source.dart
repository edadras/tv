import '../model/protocol.dart';

/// Works out what a pasted link actually is, which decides how the TV plays it.
///
/// The classification is deliberately done once on the phone and sent in the
/// protocol, so the receiver never has to guess and the user can see what is
/// going to happen before pressing play.
class UrlSource {
  const UrlSource({
    required this.url,
    required this.kind,
    required this.title,
    this.youtubeId,
    this.startAt = Duration.zero,
  });

  final String url;
  final MediaKind kind;
  final String title;

  /// Set only for [MediaKind.youtube].
  final String? youtubeId;

  /// Offset asked for by the link itself, e.g. `?t=1m30s`. Someone who shares
  /// a timestamped link means that timestamp.
  final Duration startAt;

  bool get isLiveCapable => kind == MediaKind.adaptive;

  /// Streaming manifests and real-time protocols. These carry several
  /// renditions, so the player picks the bitrate itself and drops quality
  /// when the network gets slower — no logic of ours involved.
  static const _adaptiveExtensions = ['.m3u8', '.m3u', '.mpd', '.ism', '.isml'];
  static const _adaptiveSchemes = ['rtsp', 'rtsps', 'rtmp', 'rtmps', 'udp', 'rtp'];

  static final _youtubeHosts = {
    'youtube.com', 'www.youtube.com', 'm.youtube.com',
    'music.youtube.com', 'youtu.be', 'www.youtu.be',
    'youtube-nocookie.com', 'www.youtube-nocookie.com',
  };

  /// Returns null when [raw] is not something we can play.
  static UrlSource? parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // People paste "youtube.com/watch?v=..." without a scheme all the time.
    if (!text.contains('://')) {
      if (text.startsWith('//')) {
        text = 'https:$text';
      } else if (RegExp(r'^[\w.-]+\.[a-zA-Z]{2,}(/|$|\?)').hasMatch(text)) {
        text = 'https://$text';
      } else {
        return null;
      }
    }

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty && !_adaptiveSchemes.contains(uri.scheme)) {
      return null;
    }

    final youtubeId = _youtubeIdOf(uri);
    if (youtubeId != null) {
      return UrlSource(
        url: uri.toString(),
        kind: MediaKind.youtube,
        title: 'YouTube',
        youtubeId: youtubeId,
        startAt: _startOffset(uri),
      );
    }

    final scheme = uri.scheme.toLowerCase();
    final path = uri.path.toLowerCase();
    final adaptive = _adaptiveSchemes.contains(scheme) ||
        _adaptiveExtensions.any(path.endsWith) ||
        // Query-string manifests, e.g. ".../play?type=m3u8".
        _adaptiveExtensions.any((e) => uri.query.toLowerCase().contains(e.substring(1)));

    if (scheme != 'http' && scheme != 'https' && !_adaptiveSchemes.contains(scheme)) {
      return null;
    }

    return UrlSource(
      url: uri.toString(),
      kind: adaptive ? MediaKind.adaptive : MediaKind.direct,
      title: _titleFor(uri),
    );
  }

  static String? _youtubeIdOf(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!_youtubeHosts.contains(host)) return null;

    // youtu.be/<id>
    if (host.endsWith('youtu.be')) {
      final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      return _validId(id);
    }
    // youtube.com/watch?v=<id>
    final v = uri.queryParameters['v'];
    if (v != null) return _validId(v);

    // /embed/<id>, /shorts/<id>, /live/<id>, /v/<id>
    final segments = uri.pathSegments;
    for (final prefix in const ['embed', 'shorts', 'live', 'v']) {
      final i = segments.indexOf(prefix);
      if (i >= 0 && i + 1 < segments.length) return _validId(segments[i + 1]);
    }
    return null;
  }

  /// Reads `t` / `start`, which YouTube writes as either plain seconds or
  /// the `1h2m3s` shorthand.
  static Duration _startOffset(Uri uri) {
    final raw = uri.queryParameters['t'] ?? uri.queryParameters['start'];
    if (raw == null || raw.isEmpty) return Duration.zero;

    final plain = int.tryParse(raw);
    if (plain != null) return Duration(seconds: plain.clamp(0, 86400));

    final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(raw);
    if (m == null || m.group(0)!.isEmpty) return Duration.zero;
    return Duration(
      hours: int.tryParse(m.group(1) ?? '') ?? 0,
      minutes: int.tryParse(m.group(2) ?? '') ?? 0,
      seconds: int.tryParse(m.group(3) ?? '') ?? 0,
    );
  }

  static String? _validId(String? id) {
    if (id == null) return null;
    return RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id) ? id : null;
  }

  /// A readable name from the last path segment, falling back to the host.
  static String _titleFor(Uri uri) {
    final last = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    if (last == null || last.isEmpty) return uri.host;
    final decoded = Uri.decodeComponent(last);
    final dot = decoded.lastIndexOf('.');
    final stem = dot > 0 ? decoded.substring(0, dot) : decoded;
    return stem.isEmpty ? uri.host : stem;
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
