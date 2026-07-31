import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/log.dart';
import '../model/protocol.dart';
import 'playback_engine.dart';

/// ExoPlayer, used for HLS / DASH / SmoothStreaming / RTSP.
///
/// The reason these go here rather than through FFmpeg is adaptive bitrate:
/// ExoPlayer's track selector watches throughput and switches rendition on its
/// own, which is exactly the "drop the quality when the line gets slow"
/// behaviour we want. We deliberately do not override it — the default
/// selector is better tuned than anything we would hand-roll.
class ExoEngine extends PlaybackEngine {
  VideoPlayerController? _controller;
  EngineState _state = const EngineState();

  @override
  EngineState get state => _state;

  @override
  String get label => 'ExoPlayer';

  @override
  Future<void> open(String url, {Duration start = Duration.zero}) async {
    await release();
    _state = const EngineState();
    notifyListeners();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _controller = controller;
    controller.addListener(_onValue);

    try {
      await controller.initialize();
      if (start > Duration.zero) await controller.seekTo(start);
      await controller.play();
    } catch (e) {
      logDebug('exo open failed: $e');
      _state = _state.copyWith(error: 'پخش این پخش زنده ممکن نشد', ready: false);
      notifyListeners();
    }
  }

  void _onValue() {
    final v = _controller?.value;
    if (v == null) return;
    _state = _state.copyWith(
      position: v.position,
      duration: v.duration,
      buffered: v.buffered.isEmpty ? Duration.zero : v.buffered.last.end,
      playing: v.isPlaying,
      buffering: v.isBuffering,
      ready: v.isInitialized,
      aspectRatio: v.aspectRatio,
      // The selector reports its choice through the natural video size.
      quality: v.size.height > 0 ? '${v.size.height.round()}p' : '',
      error: v.hasError ? (v.errorDescription ?? 'خطای پخش') : null,
      clearError: !v.hasError,
    );
    notifyListeners();
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seek(Duration to) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final max = c.value.duration;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && to > max ? max : to);
    await c.seekTo(clamped);
  }

  @override
  Future<void> setRate(double rate) async => _controller?.setPlaybackSpeed(rate);

  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume(volume.clamp(0, 1));

  @override
  Widget surface(VideoFit fit) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final player = VideoPlayer(c);
    return switch (fit) {
      VideoFit.contain =>
        Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: player)),
      VideoFit.cover => FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: player,
          ),
        ),
      VideoFit.stretch => player,
    };
  }

  @override
  Future<void> release() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    c.removeListener(_onValue);
    try {
      await c.pause();
    } catch (_) {
      // Already gone.
    }
    await c.dispose();
  }
}
