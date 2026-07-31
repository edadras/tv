/// Wire protocol shared by the phone (controller), the TV app (receiver) and
/// the browser player. Everything is plain JSON over a single WebSocket.
///
/// Controller -> receiver : [CastCommand]
/// Receiver -> controller : [PlayerSnapshot] (as `{"t":"state", ...}`) plus
///                          `{"t":"hello"}` / `{"t":"bye"}` handshakes.
library;

/// Default LAN ports. Kept high and fixed so nothing needs configuring.
const int kHttpPort = 8787;
const int kBeaconPort = 45454;

/// Bumped whenever the JSON shape changes incompatibly.
const int kProtocolVersion = 1;

/// What the receiver is being asked to play, which decides both the URL
/// handling and the playback engine.
enum MediaKind {
  /// A file on the phone, streamed from its built-in server. The URL is
  /// relative and the receiver resolves it against the host.
  file,

  /// A plain remote video URL (MP4, MKV, …), played straight from source.
  direct,

  /// HLS / DASH / SmoothStreaming / RTSP. Carries several renditions, so the
  /// player picks the bitrate itself and steps down when the network slows.
  adaptive,

  /// Played through YouTube's official embedded player.
  youtube,
}

enum SubFormat { srt, vtt, ass, unknown }

SubFormat subFormatOf(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.srt')) return SubFormat.srt;
  if (p.endsWith('.vtt')) return SubFormat.vtt;
  if (p.endsWith('.ass') || p.endsWith('.ssa')) return SubFormat.ass;
  return SubFormat.unknown;
}

/// A subtitle file published by the host.
class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.label,
    required this.path,
    this.language,
  });

  /// Stable id inside the current session.
  final String id;

  /// Human label shown in the picker (usually the file name).
  final String label;

  /// Path on the *host* device. Never sent to the receiver.
  final String path;
  final String? language;

  /// URL (relative to the host root) that serves this track as WebVTT.
  String get vttUrl => '/sub/$id.vtt';

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'url': vttUrl, 'lang': language};

  static SubtitleTrack fromJson(Map<String, Object?> j) => SubtitleTrack(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? 'Subtitle',
        path: (j['url'] as String?) ?? '',
        language: j['lang'] as String?,
      );
}

/// The video being cast — a phone file, a remote link or a YouTube video.
class CastMedia {
  const CastMedia({
    required this.id,
    required this.title,
    required this.path,
    required this.size,
    this.kind = MediaKind.file,
    this.mime = 'video/mp4',
    this.subtitles = const [],
    this.youtubeId,
    this.durationMs = 0,
    this.viaTranscode = false,
  });

  final String id;
  final String title;

  /// For [MediaKind.file] this is the host-side path and is never transmitted;
  /// the receiver instead sees the relative [url]. For every remote kind it is
  /// the source URL itself, which does go over the wire.
  final String path;
  final int size;
  final MediaKind kind;
  final String mime;
  final List<SubtitleTrack> subtitles;
  final String? youtubeId;

  /// Known length, so a converted stream can still show a timeline even
  /// though the bytes themselves carry no duration.
  final int durationMs;

  /// Set only on the copy sent to a browser that cannot play the original.
  /// The phone converts as it sends, which means the result has no length and
  /// cannot be seeked — the player restarts it at an offset instead.
  final bool viaTranscode;

  bool get isRemote => kind != MediaKind.file;

  /// What the receiver is told to open. Relative for phone-hosted files so it
  /// resolves against whichever address the receiver reached us on; absolute
  /// for anything already out on the network.
  String get url => kind != MediaKind.file
      ? path
      : (viaTranscode ? '/stream/$id' : '/media/$id');

  CastMedia copyWith({
    List<SubtitleTrack>? subtitles,
    int? durationMs,
    bool? viaTranscode,
  }) =>
      CastMedia(
        id: id,
        title: title,
        path: path,
        size: size,
        kind: kind,
        mime: mime,
        subtitles: subtitles ?? this.subtitles,
        youtubeId: youtubeId,
        durationMs: durationMs ?? this.durationMs,
        viaTranscode: viaTranscode ?? this.viaTranscode,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'size': size,
        'kind': kind.name,
        'mime': mime,
        'yt': youtubeId,
        'dur': durationMs,
        'restart': viaTranscode,
        'subs': [for (final s in subtitles) s.toJson()],
      };

  static CastMedia fromJson(Map<String, Object?> j) => CastMedia(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        path: (j['url'] as String?) ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        kind: MediaKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => MediaKind.file,
        ),
        mime: (j['mime'] as String?) ?? 'video/mp4',
        youtubeId: j['yt'] as String?,
        durationMs: (j['dur'] as num?)?.toInt() ?? 0,
        viaTranscode: (j['restart'] as bool?) ?? false,
        subtitles: [
          for (final s in (j['subs'] as List? ?? const []))
            SubtitleTrack.fromJson((s as Map).cast<String, Object?>()),
        ],
      );
}

/// Look of the rendered subtitles. Applied identically on TV and in the
/// browser player so switching targets never changes how a film reads.
class SubtitleStyleSpec {
  const SubtitleStyleSpec({
    this.sizePx = 34,
    this.color = 0xFFFFFFFF,
    this.backdrop = .35,
    this.outline = true,
    this.bottomPct = 6,
    this.bold = true,
  });

  /// Font size in logical px, referenced to a 1080p-tall screen.
  final double sizePx;
  final int color;

  /// 0 = no plate behind the text, 1 = solid black plate.
  final double backdrop;
  final bool outline;

  /// Distance from the bottom of the video, as a % of video height.
  final double bottomPct;
  final bool bold;

  SubtitleStyleSpec copyWith({
    double? sizePx,
    int? color,
    double? backdrop,
    bool? outline,
    double? bottomPct,
    bool? bold,
  }) =>
      SubtitleStyleSpec(
        sizePx: sizePx ?? this.sizePx,
        color: color ?? this.color,
        backdrop: backdrop ?? this.backdrop,
        outline: outline ?? this.outline,
        bottomPct: bottomPct ?? this.bottomPct,
        bold: bold ?? this.bold,
      );

  Map<String, Object?> toJson() => {
        'size': sizePx,
        'color': color,
        'backdrop': backdrop,
        'outline': outline,
        'bottom': bottomPct,
        'bold': bold,
      };

  static SubtitleStyleSpec fromJson(Map<String, Object?> j) => SubtitleStyleSpec(
        sizePx: (j['size'] as num?)?.toDouble() ?? 34,
        color: (j['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
        backdrop: (j['backdrop'] as num?)?.toDouble() ?? .35,
        outline: (j['outline'] as bool?) ?? true,
        bottomPct: (j['bottom'] as num?)?.toDouble() ?? 6,
        bold: (j['bold'] as bool?) ?? true,
      );
}

/// How the video is scaled into the screen.
enum VideoFit { contain, cover, stretch }

/// One command from the controller to the receiver.
class CastCommand {
  const CastCommand(this.type, [this.data = const {}]);

  final String type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {'t': type, ...data};

  static CastCommand fromJson(Map<String, Object?> j) {
    final d = Map<String, Object?>.from(j)..remove('t');
    return CastCommand((j['t'] as String?) ?? '', d);
  }

  static CastCommand load(CastMedia media, {int startMs = 0, String? subId}) =>
      CastCommand('load', {'media': media.toJson(), 'start': startMs, 'sub': subId});

  static const play = CastCommand('play');
  static const pause = CastCommand('pause');
  static const stop = CastCommand('stop');
  static const toggle = CastCommand('toggle');
  static const ping = CastCommand('ping');

  static CastCommand seek(int ms) => CastCommand('seek', {'pos': ms});
  static CastCommand nudge(int ms) => CastCommand('nudge', {'delta': ms});
  static CastCommand selectSub(String? id) => CastCommand('sub', {'id': id});
  static CastCommand subDelay(int ms) => CastCommand('subDelay', {'ms': ms});
  static CastCommand subStyle(SubtitleStyleSpec s) => CastCommand('subStyle', s.toJson());
  static CastCommand addSub(SubtitleTrack t) => CastCommand('addSub', {'sub': t.toJson()});
  static CastCommand rate(double v) => CastCommand('rate', {'v': v});
  static CastCommand volume(double v) => CastCommand('volume', {'v': v});
  static CastCommand fit(VideoFit f) => CastCommand('fit', {'v': f.name});
}

/// Everything the controller needs to draw the remote, pushed by the receiver.
class PlayerSnapshot {
  const PlayerSnapshot({
    this.title = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.bufferedMs = 0,
    this.playing = false,
    this.buffering = false,
    this.ready = false,
    this.error,
    this.subId,
    this.subDelayMs = 0,
    this.rate = 1,
    this.volume = 1,
    this.fit = VideoFit.contain,
    this.style = const SubtitleStyleSpec(),
    this.subs = const [],
    this.receiver = '',
    this.live = false,
    this.kind = MediaKind.file,
    this.quality = '',
  });

  final String title;
  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final bool playing;
  final bool buffering;
  final bool ready;
  final String? error;
  final String? subId;
  final int subDelayMs;
  final double rate;
  final double volume;
  final VideoFit fit;
  final SubtitleStyleSpec style;
  final List<SubtitleTrack> subs;
  final String receiver;

  /// A stream with no fixed end. The remote hides the scrubber and shows a
  /// LIVE badge instead of pretending there is a timeline to drag.
  final bool live;

  final MediaKind kind;

  /// Human-readable note about what the engine picked, e.g. "۷۲۰p • خودکار".
  final String quality;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  Map<String, Object?> toJson() => {
        't': 'state',
        'title': title,
        'pos': positionMs,
        'dur': durationMs,
        'buf': bufferedMs,
        'playing': playing,
        'buffering': buffering,
        'ready': ready,
        'err': error,
        'sub': subId,
        'subDelay': subDelayMs,
        'rate': rate,
        'vol': volume,
        'fit': fit.name,
        'style': style.toJson(),
        'subs': [for (final s in subs) s.toJson()],
        'receiver': receiver,
        'live': live,
        'kind': kind.name,
        'quality': quality,
      };

  static PlayerSnapshot fromJson(Map<String, Object?> j) => PlayerSnapshot(
        title: (j['title'] as String?) ?? '',
        positionMs: (j['pos'] as num?)?.toInt() ?? 0,
        durationMs: (j['dur'] as num?)?.toInt() ?? 0,
        bufferedMs: (j['buf'] as num?)?.toInt() ?? 0,
        playing: (j['playing'] as bool?) ?? false,
        buffering: (j['buffering'] as bool?) ?? false,
        ready: (j['ready'] as bool?) ?? false,
        error: j['err'] as String?,
        subId: j['sub'] as String?,
        subDelayMs: (j['subDelay'] as num?)?.toInt() ?? 0,
        rate: (j['rate'] as num?)?.toDouble() ?? 1,
        volume: (j['vol'] as num?)?.toDouble() ?? 1,
        fit: VideoFit.values.firstWhere(
          (f) => f.name == j['fit'],
          orElse: () => VideoFit.contain,
        ),
        style: SubtitleStyleSpec.fromJson(
          ((j['style'] as Map?) ?? const {}).cast<String, Object?>(),
        ),
        subs: [
          for (final s in (j['subs'] as List? ?? const []))
            SubtitleTrack.fromJson((s as Map).cast<String, Object?>()),
        ],
        receiver: (j['receiver'] as String?) ?? '',
        live: (j['live'] as bool?) ?? false,
        kind: MediaKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => MediaKind.file,
        ),
        quality: (j['quality'] as String?) ?? '',
      );
}
