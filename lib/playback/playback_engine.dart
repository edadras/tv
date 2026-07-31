import 'package:flutter/widgets.dart';

import '../model/protocol.dart';

/// Everything the receiver needs to know about what an engine is doing.
@immutable
class EngineState {
  const EngineState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.ready = false,
    this.error,
    this.quality = '',
    this.aspectRatio = 16 / 9,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool playing;
  final bool buffering;
  final bool ready;
  final String? error;

  /// What the engine picked, when it can tell us — e.g. "۷۲۰p".
  final String quality;
  final double aspectRatio;

  /// A stream with no fixed end. Every engine reports a zero duration for one,
  /// so there is a single rule instead of one per backend.
  bool get live => ready && duration <= Duration.zero;

  EngineState copyWith({
    Duration? position,
    Duration? duration,
    Duration? buffered,
    bool? playing,
    bool? buffering,
    bool? ready,
    String? error,
    bool clearError = false,
    String? quality,
    double? aspectRatio,
  }) =>
      EngineState(
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        ready: ready ?? this.ready,
        error: clearError ? null : (error ?? this.error),
        quality: quality ?? this.quality,
        aspectRatio: aspectRatio ?? this.aspectRatio,
      );
}

/// One way of getting pixels on screen.
///
/// Three of these exist because no single backend does everything well:
/// ExoPlayer has the best adaptive-bitrate logic for HLS/DASH, libmpv/FFmpeg
/// plays containers nothing else will touch, and YouTube can only legitimately
/// be played through its own embedded player. The receiver picks per source
/// and the rest of the app never knows the difference.
abstract class PlaybackEngine extends ChangeNotifier {
  EngineState get state;

  /// Human name, for diagnostics in the UI.
  String get label;

  /// Whether the engine can be scrubbed. YouTube can; a live RTSP feed cannot.
  bool get seekable => true;

  Future<void> open(String url, {Duration start = Duration.zero});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);

  /// The video surface. [fit] is applied by the engine because each backend
  /// exposes its natural size differently.
  Widget surface(VideoFit fit);

  /// Releases native resources. Separate from [dispose] because it is async.
  Future<void> release();
}
