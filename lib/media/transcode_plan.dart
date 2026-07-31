/// Decides how a file has to be reshaped before a browser can play it, and
/// builds the FFmpeg command that does it.
///
/// This is deliberately pure Dart with no plugin behind it, so the decision —
/// the part that is easy to get wrong — is unit tested, and only the thin
/// "run FFmpeg" layer needs a device.
library;

/// What FFmpeg told us about a file.
class MediaProbe {
  const MediaProbe({
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
  });

  /// Format name as FFmpeg reports it, e.g. `matroska,webm` or `mov,mp4,…`.
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int durationMs;
  final int width;
  final int height;

  static const unknown = MediaProbe(container: '', videoCodec: '', audioCodec: '');

  bool get isEmpty => container.isEmpty && videoCodec.isEmpty;
}

/// How much work the phone has to do to make a file playable in a browser.
enum TranscodeMode {
  /// Nothing to do: the browser can play the original bytes.
  direct,

  /// Same streams, different wrapper. No decoding, so it costs almost nothing
  /// and always keeps up.
  remux,

  /// Video is fine, only the audio needs re-encoding (AC-3 and DTS in MKV are
  /// the usual reason). Still cheap.
  audioOnly,

  /// The video itself has to be re-encoded. This is the expensive one.
  full,
}

class TranscodePlan {
  const TranscodePlan({
    required this.mode,
    required this.args,
    this.reason = '',
  });

  final TranscodeMode mode;

  /// FFmpeg arguments, already split — never a shell string.
  final List<String> args;

  /// Short human explanation, shown on the phone.
  final String reason;

  bool get needsWork => mode != TranscodeMode.direct;

  /// True when the phone will be decoding and re-encoding video, which is
  /// what costs battery and may not keep up on a slow device.
  bool get isHeavy => mode == TranscodeMode.full;
}

/// What browsers will play without help.
class BrowserCompat {
  const BrowserCompat._();

  /// MP4-family containers, which accept the broad codec set.
  static const _mp4Containers = {'mp4', 'm4v', 'mov', 'mj2', '3gp', '3g2'};

  /// H.265 is deliberately excluded: Safari plays it, Chromium generally does
  /// not, and guessing wrong means a black screen on the TV.
  static const _videoCodecs = {'h264', 'avc1', 'vp8', 'vp9', 'av1', 'av01'};

  static const _audioCodecs = {'aac', 'mp3', 'mp4a', 'opus', 'vorbis'};

  /// Matroska and WebM share one demuxer, so FFmpeg reports `matroska,webm`
  /// for both an .mkv and a .webm. The container name therefore cannot tell
  /// them apart — only the codecs inside can. A Matroska carrying VP9 and
  /// Opus *is* a WebM and plays; the same container carrying H.264 and AAC
  /// does not, whatever the file is called.
  static const _webmVideo = {'vp8', 'vp9', 'av1', 'av01'};
  static const _webmAudio = {'opus', 'vorbis'};

  static bool videoOk(String codec) => _videoCodecs.contains(_norm(codec));

  static bool audioOk(String codec) =>
      codec.isEmpty || _audioCodecs.contains(_norm(codec));

  /// A file the browser can be handed as-is.
  static bool canPlay(MediaProbe probe) {
    final names = probe.container.toLowerCase().split(',').map((s) => s.trim()).toSet();
    final video = _norm(probe.videoCodec);
    final audio = _norm(probe.audioCodec);

    if (names.contains('matroska') || names.contains('webm')) {
      return _webmVideo.contains(video) &&
          (audio.isEmpty || _webmAudio.contains(audio));
    }
    if (names.any(_mp4Containers.contains)) {
      return videoOk(video) && audioOk(audio);
    }
    return false;
  }

  static String _norm(String codec) => codec.toLowerCase().trim();
}

/// Builds the plan for handing [probe] to a browser.
///
/// [output] is where FFmpeg writes — a pipe, so the bytes stream out as they
/// are produced instead of waiting for a whole file.
TranscodePlan planForBrowser(
  MediaProbe probe, {
  required String input,
  required String output,
  Duration start = Duration.zero,
  bool hardwareEncoder = true,
}) {
  if (BrowserCompat.canPlay(probe)) {
    return const TranscodePlan(
      mode: TranscodeMode.direct,
      args: [],
      reason: 'مرورگر خودش این فایل را پخش می‌کند',
    );
  }

  final videoOk = BrowserCompat.videoOk(probe.videoCodec);
  final audioOk = BrowserCompat.audioOk(probe.audioCodec);

  final mode = !videoOk
      ? TranscodeMode.full
      : (audioOk ? TranscodeMode.remux : TranscodeMode.audioOnly);

  final args = <String>[
    '-hide_banner',
    '-loglevel', 'error',
    // Seeking before -i lets FFmpeg jump by keyframe instead of decoding up
    // to the point, which is what makes restarting at an offset feel instant.
    if (start > Duration.zero) ...['-ss', _seconds(start)],
    '-i', input,

    // First video and first audio track only. Anything else (chapters, fonts,
    // embedded subtitles) has no place in a fragmented MP4 and would abort
    // the mux.
    '-map', '0:v:0',
    '-map', '0:a:0?',
    '-sn',
    '-dn',

    ...switch (mode) {
      TranscodeMode.remux => const ['-c:v', 'copy', '-c:a', 'copy'],
      TranscodeMode.audioOnly => const ['-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ac', '2'],
      TranscodeMode.full => [
          ...(hardwareEncoder
              // The phone's own encoder chip: the difference between keeping
              // up with playback and not.
              ? const ['-c:v', 'h264_mediacodec', '-b:v', '5M']
              : const ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23']),
          '-pix_fmt', 'yuv420p',
          '-c:a', 'aac', '-b:a', '192k', '-ac', '2',
        ],
      TranscodeMode.direct => const [],
    },

    // A fragmented MP4 can be played while it is still being written; a normal
    // one cannot, because its index is only finished at the end.
    '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
    '-f', 'mp4',
    '-y',
    output,
  ];

  return TranscodePlan(
    mode: mode,
    args: args,
    reason: switch (mode) {
      TranscodeMode.remux => 'فقط قالب فایل عوض می‌شود — بدون فشار روی گوشی',
      TranscodeMode.audioOnly => 'فقط صدا تبدیل می‌شود — فشار کمی روی گوشی',
      TranscodeMode.full => 'تصویر روی گوشی تبدیل می‌شود — گوشی گرم می‌شود',
      TranscodeMode.direct => '',
    },
  );
}

String _seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);
