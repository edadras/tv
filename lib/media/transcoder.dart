import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';

import '../core/log.dart';
import '../net/host_server.dart';
import 'transcode_plan.dart';

/// Runs FFmpeg on the phone so a browser that cannot open a file gets one it
/// can. Everything decidable lives in [transcode_plan]; this is only the part
/// that needs the device.
///
/// Output goes to a FIFO rather than a file, so bytes reach the TV as they are
/// produced instead of after the whole film is converted.
class Transcoder {
  final _probes = <String, MediaProbe>{};
  _Session? _current;

  /// Whether the last hardware attempt failed, in which case we stop asking
  /// for it. Some devices advertise the encoder and then refuse the format.
  bool _hardwareWorks = true;

  /// Reads the codecs out of [path], caching the answer per file.
  Future<MediaProbe> probe(String path) async {
    final cached = _probes[path];
    if (cached != null) return cached;
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final result = info == null ? MediaProbe.unknown : _readProbe(info);
      _probes[path] = result;
      return result;
    } catch (e) {
      logDebug('probe failed for $path: $e');
      return MediaProbe.unknown;
    }
  }

  static MediaProbe _readProbe(MediaInformation info) {
    var video = '';
    var audio = '';
    var width = 0;
    var height = 0;
    for (final s in info.getStreams()) {
      switch (s.getType()) {
        case 'video':
          if (video.isNotEmpty) continue;
          video = s.getCodec() ?? '';
          width = s.getWidth() ?? 0;
          height = s.getHeight() ?? 0;
        case 'audio':
          audio = audio.isEmpty ? (s.getCodec() ?? '') : audio;
      }
    }
    final seconds = double.tryParse(info.getDuration() ?? '') ?? 0;
    return MediaProbe(
      container: info.getFormat() ?? '',
      videoCodec: video,
      audioCodec: audio,
      durationMs: (seconds * 1000).round(),
      width: width,
      height: height,
    );
  }

  /// True when the browser would fail on this file as-is.
  Future<TranscodePlan> planFor(String path, {Duration start = Duration.zero}) async {
    final p = await probe(path);
    // An unreadable probe must not silently trigger a pointless transcode;
    // hand the original over and let the browser try.
    if (p.isEmpty) {
      return const TranscodePlan(mode: TranscodeMode.direct, args: []);
    }
    return planForBrowser(
      p,
      input: path,
      output: '',
      start: start,
      hardwareEncoder: _hardwareWorks,
    );
  }

  /// Starts converting [path] and returns the bytes as they are produced.
  /// Returns null when the file needs no work, so the caller serves the
  /// original (which keeps range requests and seeking intact).
  Future<HostedStream?> open(String path, Duration start) async {
    final probeResult = await probe(path);
    if (probeResult.isEmpty || BrowserCompat.canPlay(probeResult)) return null;

    // Only one conversion at a time: a second would fight the first for the
    // encoder and the battery.
    await stop();

    String? pipe;
    try {
      pipe = await FFmpegKitConfig.registerNewFFmpegPipe();
      if (pipe == null) {
        logDebug('could not create an FFmpeg pipe');
        return null;
      }

      final plan = planForBrowser(
        probeResult,
        input: path,
        output: pipe,
        start: start,
        hardwareEncoder: _hardwareWorks,
      );

      final session = await FFmpegKit.executeWithArgumentsAsync(
        plan.args,
        (session) async {
          final code = await session.getReturnCode();
          if (code == null || code.isValueSuccess()) return;
          final failed = await session.getFailStackTrace() ?? '';
          logDebug('ffmpeg finished badly (${code.getValue()}): $failed');
          // A device that advertises a hardware encoder but rejects the
          // stream should not keep failing the same way.
          if (plan.isHeavy && _hardwareWorks) {
            _hardwareWorks = false;
            logDebug('falling back to software encoding from now on');
          }
        },
      );

      final sessionId = session.getSessionId();
      final current = _Session(pipe: pipe, sessionId: sessionId);
      _current = current;

      return HostedStream(
        // Opening the FIFO blocks until FFmpeg opens the write end, which it
        // already has by now.
        bytes: File(pipe).openRead().handleError((Object e) {
          logDebug('transcode stream error: $e');
        }),
        close: () => _close(current),
      );
    } catch (e) {
      logDebug('transcode start failed: $e');
      if (pipe != null) await _safeClosePipe(pipe);
      return null;
    }
  }

  Future<void> stop() async {
    final current = _current;
    if (current != null) await _close(current);
  }

  Future<void> _close(_Session session) async {
    if (_current == session) _current = null;
    final id = session.sessionId;
    try {
      if (id != null) {
        await FFmpegKit.cancel(id);
      } else {
        await FFmpegKit.cancel();
      }
    } catch (e) {
      logDebug('cancel failed: $e');
    }
    await _safeClosePipe(session.pipe);
  }

  Future<void> _safeClosePipe(String pipe) async {
    try {
      FFmpegKitConfig.closeFFmpegPipe(pipe);
    } catch (e) {
      logDebug('closing pipe failed: $e');
    }
  }

  void dispose() => unawaited(stop());
}

class _Session {
  _Session({required this.pipe, required this.sessionId});

  final String pipe;
  final int? sessionId;
}
