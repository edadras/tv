import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/device.dart';
import '../core/log.dart';
import '../core/prefs.dart';
import '../model/protocol.dart';
import '../net/receiver_link.dart';
import '../playback/exo_engine.dart';
import '../playback/mpv_engine.dart';
import '../playback/playback_engine.dart';
import '../playback/youtube_engine.dart';
import '../subs/subtitle_doc.dart';

/// TV-side brain: picks a playback engine for whatever the phone sent, renders
/// subtitles with the sync offset applied, obeys the phone and reports back.
class ReceiverController extends ChangeNotifier {
  ReceiverController(this.facts) {
    link = ReceiverLink(deviceName: facts.name);
    _commandSub = link.commands.listen(_onCommand);
    _statusSub = link.statusStream.listen((_) => notifyListeners());
  }

  final DeviceFacts facts;
  late final ReceiverLink link;

  StreamSubscription<CastCommand>? _commandSub;
  StreamSubscription<LinkStatus>? _statusSub;

  PlaybackEngine? _engine;
  Timer? _ticker;
  SubtitleDoc? _doc;
  CastMedia? _media;

  /// Only the subtitle overlay listens to this, so a cue change never
  /// rebuilds the video surface.
  final currentCue = ValueNotifier<String?>(null);

  String? _subId;
  int _subDelayMs = 0;
  double _volume = 1;
  SubtitleStyleSpec _style = const SubtitleStyleSpec();
  VideoFit _fit = VideoFit.contain;
  String? _error;
  bool _loading = false;

  PlaybackEngine? get engine => _engine;
  CastMedia? get media => _media;
  String? get error => _error ?? _engine?.state.error;
  bool get loading => _loading;
  SubtitleStyleSpec get style => _style;
  VideoFit get fit => _fit;
  int get subDelayMs => _subDelayMs;
  String? get subId => _subId;
  List<SubtitleTrack> get subtitles => _media?.subtitles ?? const [];
  LinkStatus get status => link.status;

  EngineState get _es => _engine?.state ?? const EngineState();
  bool get isPlaying => _es.playing;
  bool get hasVideo => _es.ready;
  bool get isLive => _es.live;
  Duration get position => _es.position;
  Duration get duration => _es.duration;

  /// Subtitles cannot be layered onto YouTube's own player, so the overlay is
  /// suppressed there rather than floating over the wrong picture.
  bool get supportsSubtitles => _media?.kind != MediaKind.youtube;

  Future<void> connect(String host) async {
    await Prefs.instance.setLastHost(host);
    await link.connect(host);
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _teardown();
    await link.disconnect();
    notifyListeners();
  }

  // --- commands -----------------------------------------------------------

  Future<void> _onCommand(CastCommand c) async {
    switch (c.type) {
      case 'load':
        final raw = (c.data['media'] as Map?)?.cast<String, Object?>();
        if (raw == null) return;
        await _load(
          CastMedia.fromJson(raw),
          startMs: (c.data['start'] as num?)?.toInt() ?? 0,
          subId: c.data['sub'] as String?,
        );
      case 'play':
        await _engine?.play();
        _keepAwake(true);
      case 'pause':
        await _engine?.pause();
        _keepAwake(false);
      case 'toggle':
        await togglePlay();
      case 'stop':
        await _teardown();
      case 'seek':
        await _seek(Duration(milliseconds: (c.data['pos'] as num?)?.toInt() ?? 0));
      case 'nudge':
        await _seek(position + Duration(milliseconds: (c.data['delta'] as num?)?.toInt() ?? 0));
      case 'sub':
        await selectSubtitle(c.data['id'] as String?);
      case 'subDelay':
        setSubDelay((c.data['ms'] as num?)?.toInt() ?? 0);
      case 'subStyle':
        _style = SubtitleStyleSpec.fromJson(c.data);
        notifyListeners();
      case 'addSub':
        final raw = (c.data['sub'] as Map?)?.cast<String, Object?>();
        final m = _media;
        if (raw != null && m != null) {
          _media = m.copyWith(subtitles: [...m.subtitles, SubtitleTrack.fromJson(raw)]);
          notifyListeners();
        }
      case 'rate':
        await _engine?.setRate((c.data['v'] as num?)?.toDouble() ?? 1);
        notifyListeners();
      case 'volume':
        _volume = ((c.data['v'] as num?)?.toDouble() ?? 1).clamp(0, 1);
        await _engine?.setVolume(_volume);
        notifyListeners();
      case 'fit':
        _fit = VideoFit.values.firstWhere(
          (f) => f.name == c.data['v'],
          orElse: () => VideoFit.contain,
        );
        notifyListeners();
    }
  }

  // --- playback -----------------------------------------------------------

  /// Chooses the backend for a source.
  ///
  /// Adaptive manifests go to ExoPlayer because its bitrate ladder is the
  /// thing that keeps a stream alive on a slow line; everything else goes to
  /// FFmpeg, which plays containers Android's own stack will not.
  PlaybackEngine _engineFor(MediaKind kind) => switch (kind) {
        MediaKind.youtube => YoutubeEngine(),
        MediaKind.adaptive => ExoEngine(),
        MediaKind.direct || MediaKind.file => MpvEngine(),
      };

  Future<void> _load(CastMedia media, {int startMs = 0, String? subId}) async {
    // A phone-hosted file arrives as a relative path; a remote link is
    // already absolute and must not be resolved against the phone.
    final url = media.isRemote ? media.path : link.resolve(media.path);
    if (url == null || url.isEmpty) return;

    await _teardown(keepMedia: true);
    _media = media;
    _error = null;
    _loading = true;
    notifyListeners();

    final engine = _engineFor(media.kind)..addListener(_onEngineChanged);
    _engine = engine;
    _startTicker();

    try {
      await engine.open(url, start: Duration(milliseconds: startMs));
      await engine.setVolume(_volume);
      _keepAwake(true);
    } catch (e) {
      logDebug('load failed: $e');
      _error = 'پخش این مورد ممکن نشد';
    }
    _loading = false;
    notifyListeners();

    if (subId != null && supportsSubtitles) await selectSubtitle(subId);
  }

  void _onEngineChanged() {
    _refreshCue();
    notifyListeners();
  }

  Future<void> _seek(Duration to) async {
    // Seeking a live feed with no timeline just restarts buffering.
    if (isLive) return;
    await _engine?.seek(to);
    _doc?.resetCursor();
    _refreshCue();
  }

  Future<void> togglePlay() async {
    final e = _engine;
    if (e == null) return;
    e.state.playing ? await e.pause() : await e.play();
    _keepAwake(!e.state.playing);
    notifyListeners();
  }

  Future<void> nudge(int ms) => _seek(position + Duration(milliseconds: ms));

  Future<void> _teardown({bool keepMedia = false}) async {
    _ticker?.cancel();
    _ticker = null;
    final e = _engine;
    _engine = null;
    if (e != null) {
      e.removeListener(_onEngineChanged);
      await e.release();
      e.dispose();
    }
    _doc = null;
    currentCue.value = null;
    if (!keepMedia) {
      _media = null;
      _subId = null;
      _error = null;
    }
    _keepAwake(false);
    link.report(snapshot());
    notifyListeners();
  }

  void _keepAwake(bool on) => unawaited(DeviceFacts.keepAwake(on));

  // --- subtitles ----------------------------------------------------------

  Future<void> selectSubtitle(String? id) async {
    _subId = id;
    _doc = null;
    currentCue.value = null;
    notifyListeners();
    if (id == null) return;

    final track = subtitles.where((s) => s.id == id).firstOrNull;
    final url = track == null ? null : link.resolve(track.path);
    if (url == null) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      client.close();
      _doc = SubtitleDoc.parseBytes(Uint8List.fromList(bytes));
      _refreshCue();
    } catch (e) {
      logDebug('subtitle fetch failed: $e');
      _error = 'زیرنویس بارگذاری نشد';
    }
    notifyListeners();
  }

  /// Positive delay = the subtitle shows later than the audio.
  void setSubDelay(int ms) {
    _subDelayMs = ms.clamp(-60000, 60000);
    _doc?.resetCursor();
    _refreshCue();
    notifyListeners();
  }

  void nudgeSubDelay(int deltaMs) => setSubDelay(_subDelayMs + deltaMs);

  void _refreshCue() {
    final doc = _doc;
    if (doc == null || doc.isEmpty || !supportsSubtitles) {
      if (currentCue.value != null) currentCue.value = null;
      return;
    }
    final cue = doc.cueAt(position.inMilliseconds - _subDelayMs);
    if (currentCue.value != cue?.text) currentCue.value = cue?.text;
  }

  // --- reporting ----------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    // The engines push their own updates, but a subtitle still has to be
    // looked up between them, and the phone wants a heartbeat either way.
    var beat = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _refreshCue();
      if (++beat % 3 == 0) {
        link.report(snapshot());
        notifyListeners();
      }
    });
  }

  PlayerSnapshot snapshot() {
    final s = _es;
    return PlayerSnapshot(
      title: _media?.title ?? '',
      positionMs: s.position.inMilliseconds,
      durationMs: s.duration.inMilliseconds,
      bufferedMs: s.buffered.inMilliseconds,
      playing: s.playing,
      buffering: s.buffering,
      ready: s.ready,
      error: error,
      subId: _subId,
      subDelayMs: _subDelayMs,
      rate: 1,
      volume: _volume,
      fit: _fit,
      style: _style,
      subs: supportsSubtitles ? subtitles : const [],
      receiver: facts.name,
      live: s.live,
      kind: _media?.kind ?? MediaKind.file,
      quality: s.quality,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _commandSub?.cancel();
    _statusSub?.cancel();
    final e = _engine;
    if (e != null) {
      e.removeListener(_onEngineChanged);
      unawaited(e.release());
      e.dispose();
    }
    currentCue.dispose();
    link.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
