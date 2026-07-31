import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../core/device.dart';
import '../core/prefs.dart';
import '../model/protocol.dart';
import '../net/receiver_link.dart';
import '../subs/subtitle_doc.dart';

/// TV-side brain: owns the video player, renders subtitles with the sync
/// offset applied, obeys the phone and reports state back to it.
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

  VideoPlayerController? _player;
  Timer? _ticker;
  SubtitleDoc? _doc;
  CastMedia? _media;

  /// Only the subtitle overlay listens to this, so a cue change never
  /// rebuilds the video surface.
  final currentCue = ValueNotifier<String?>(null);

  String? _subId;
  int _subDelayMs = 0;
  SubtitleStyleSpec _style = const SubtitleStyleSpec();
  VideoFit _fit = VideoFit.contain;
  String? _error;
  bool _loading = false;

  VideoPlayerController? get player => _player;
  CastMedia? get media => _media;
  String? get error => _error;
  bool get loading => _loading;
  SubtitleStyleSpec get style => _style;
  VideoFit get fit => _fit;
  int get subDelayMs => _subDelayMs;
  String? get subId => _subId;
  List<SubtitleTrack> get subtitles => _media?.subtitles ?? const [];
  LinkStatus get status => link.status;

  bool get isPlaying => _player?.value.isPlaying ?? false;
  bool get hasVideo => _player?.value.isInitialized ?? false;
  Duration get position => _player?.value.position ?? Duration.zero;
  Duration get duration => _player?.value.duration ?? Duration.zero;

  Future<void> connect(String host) async {
    await Prefs.instance.setLastHost(host);
    await link.connect(host);
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _teardownPlayer();
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
        await _player?.play();
        _keepAwake(true);
      case 'pause':
        await _player?.pause();
        _keepAwake(false);
      case 'toggle':
        await togglePlay();
      case 'stop':
        await _teardownPlayer();
      case 'seek':
        await _seek(Duration(milliseconds: (c.data['pos'] as num?)?.toInt() ?? 0));
      case 'nudge':
        final delta = (c.data['delta'] as num?)?.toInt() ?? 0;
        await _seek(position + Duration(milliseconds: delta));
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
        await _player?.setPlaybackSpeed((c.data['v'] as num?)?.toDouble() ?? 1);
        notifyListeners();
      case 'volume':
        await _player?.setVolume(((c.data['v'] as num?)?.toDouble() ?? 1).clamp(0, 1));
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

  Future<void> _load(CastMedia media, {int startMs = 0, String? subId}) async {
    final url = link.resolve(media.path);
    if (url == null) return;

    await _teardownPlayer(keepMedia: true);
    _media = media;
    _error = null;
    _loading = true;
    notifyListeners();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _player = controller;
    _startTicker();
    try {
      await controller.initialize();
      if (startMs > 0) await controller.seekTo(Duration(milliseconds: startMs));
      await controller.play();
      _keepAwake(true);
    } catch (e) {
      _error = 'این فایل پخش نشد: $e';
      debugPrint('load failed: $e');
    }
    _loading = false;
    notifyListeners();

    if (subId != null) await selectSubtitle(subId);
  }

  Future<void> _seek(Duration to) async {
    final c = _player;
    if (c == null || !c.value.isInitialized) return;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (to > c.value.duration ? c.value.duration : to);
    await c.seekTo(clamped);
    _doc?.resetCursor();
    _refreshCue();
  }

  Future<void> togglePlay() async {
    final c = _player;
    if (c == null) return;
    c.value.isPlaying ? await c.pause() : await c.play();
    _keepAwake(c.value.isPlaying);
    notifyListeners();
  }

  Future<void> nudge(int ms) => _seek(position + Duration(milliseconds: ms));

  Future<void> _teardownPlayer({bool keepMedia = false}) async {
    _ticker?.cancel();
    _ticker = null;
    final c = _player;
    _player = null;
    if (c != null) {
      await c.pause().catchError((_) {});
      await c.dispose();
    }
    _doc = null;
    currentCue.value = null;
    if (!keepMedia) {
      _media = null;
      _subId = null;
    }
    _keepAwake(false);
    link.report(snapshot());
    notifyListeners();
  }

  void _keepAwake(bool on) {
    unawaited(DeviceFacts.keepAwake(on));
  }

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
      debugPrint('subtitle fetch failed: $e');
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
    if (doc == null || doc.isEmpty) {
      currentCue.value = null;
      return;
    }
    final cue = doc.cueAt(position.inMilliseconds - _subDelayMs);
    if (currentCue.value != cue?.text) currentCue.value = cue?.text;
  }

  // --- reporting ----------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    // 20 Hz keeps the subtitles frame-accurate enough to feel instant while
    // costing nothing; the phone only needs a state push every 4th tick.
    var beat = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _refreshCue();
      if (++beat % 5 == 0) {
        link.report(snapshot());
        notifyListeners();
      }
    });
  }

  PlayerSnapshot snapshot() {
    final v = _player?.value;
    final buffered = v?.buffered.isNotEmpty ?? false
        ? v!.buffered.last.end.inMilliseconds
        : 0;
    return PlayerSnapshot(
      title: _media?.title ?? '',
      positionMs: v?.position.inMilliseconds ?? 0,
      durationMs: v?.duration.inMilliseconds ?? 0,
      bufferedMs: buffered,
      playing: v?.isPlaying ?? false,
      buffering: v?.isBuffering ?? false,
      ready: v?.isInitialized ?? false,
      error: _error,
      subId: _subId,
      subDelayMs: _subDelayMs,
      rate: v?.playbackSpeed ?? 1,
      volume: v?.volume ?? 1,
      fit: _fit,
      style: _style,
      subs: subtitles,
      receiver: facts.name,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _commandSub?.cancel();
    _statusSub?.cancel();
    _player?.dispose();
    currentCue.dispose();
    link.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
