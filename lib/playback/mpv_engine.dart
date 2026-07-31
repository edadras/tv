import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/log.dart';
import '../model/protocol.dart';
import 'playback_engine.dart';

/// libmpv + FFmpeg, used for local files and plain remote URLs.
///
/// This is the engine that makes "plays anything" true: FFmpeg's demuxers and
/// decoders cover the containers Android's own stack refuses — RMVB, VOB,
/// older WMV/VC-1, OGM — as well as everything it does handle.
class MpvEngine extends PlaybackEngine {
  MpvEngine() {
    _player = Player(
      configuration: const PlayerConfiguration(
        // A generous demuxer cache is what keeps a film over Wi-Fi smooth when
        // the link hiccups; this engine has no bitrate ladder to fall back on.
        bufferSize: 32 * 1024 * 1024,
        title: 'LanCast',
      ),
    );
    _controller = VideoController(_player);
    _wire();
  }

  late final Player _player;
  late final VideoController _controller;
  final _subscriptions = <StreamSubscription<void>>[];

  EngineState _state = const EngineState();
  bool _released = false;

  @override
  EngineState get state => _state;

  @override
  String get label => 'FFmpeg';

  void _wire() {
    void update(EngineState next) {
      if (_released) return;
      _state = next;
      notifyListeners();
    }

    _subscriptions.addAll([
      _player.stream.position.listen((p) => update(_state.copyWith(position: p))),
      _player.stream.duration.listen((d) => update(_state.copyWith(duration: d))),
      _player.stream.playing.listen((p) => update(_state.copyWith(playing: p))),
      _player.stream.buffering.listen((b) => update(_state.copyWith(buffering: b))),
      _player.stream.buffer.listen((b) => update(_state.copyWith(buffered: b))),
      _player.stream.width.listen((_) => _updateSize()),
      _player.stream.height.listen((_) => _updateSize()),
      _player.stream.error.listen((e) {
        logDebug('mpv error: $e');
        update(_state.copyWith(error: 'این فایل پخش نشد: $e'));
      }),
    ]);
  }

  void _updateSize() {
    if (_released) return;
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    if (w <= 0 || h <= 0) return;
    _state = _state.copyWith(
      ready: true,
      aspectRatio: w / h,
      quality: '${h}p',
    );
    notifyListeners();
  }

  @override
  Future<void> open(String url, {Duration start = Duration.zero}) async {
    _state = const EngineState();
    notifyListeners();
    try {
      await _player.open(Media(url, start: start > Duration.zero ? start : null));
      await _player.play();
    } catch (e) {
      logDebug('mpv open failed: $e');
      _state = _state.copyWith(error: 'این فایل پخش نشد');
      notifyListeners();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) async {
    final max = _state.duration;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && to > max ? max : to);
    await _player.seek(clamped);
  }

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume.clamp(0, 1)) * 100);

  @override
  Widget surface(VideoFit fit) => Video(
        controller: _controller,
        controls: NoVideoControls,
        fill: Colors.black,
        fit: switch (fit) {
          VideoFit.contain => BoxFit.contain,
          VideoFit.cover => BoxFit.cover,
          VideoFit.stretch => BoxFit.fill,
        },
      );

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _player.dispose();
  }
}
