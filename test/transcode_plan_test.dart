import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cast/media/transcode_plan.dart';

void main() {
  TranscodePlan plan(
    MediaProbe probe, {
    Duration start = Duration.zero,
    bool hardware = true,
  }) =>
      planForBrowser(
        probe,
        input: '/sdcard/film.mkv',
        output: '/pipe/out',
        start: start,
        hardwareEncoder: hardware,
      );

  String argAfter(List<String> args, String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : '';
  }

  group('deciding whether any work is needed', () {
    test('an MP4 of H.264 and AAC is handed over untouched', () {
      const probe = MediaProbe(
        container: 'mov,mp4,m4a,3gp,3g2,mj2',
        videoCodec: 'h264',
        audioCodec: 'aac',
      );
      expect(BrowserCompat.canPlay(probe), isTrue);
      final p = plan(probe);
      expect(p.mode, TranscodeMode.direct);
      expect(p.args, isEmpty);
      expect(p.needsWork, isFalse);
    });

    test('an MKV of H.264 and AAC only needs rewrapping', () {
      // The commonest case by far: the codecs are fine, the container is not.
      const probe = MediaProbe(container: 'matroska,webm', videoCodec: 'h264', audioCodec: 'aac');
      final p = plan(probe);
      expect(p.mode, TranscodeMode.remux);
      expect(p.isHeavy, isFalse);
      // Nothing is decoded.
      expect(argAfter(p.args, '-c:v'), 'copy');
      expect(argAfter(p.args, '-c:a'), 'copy');
    });

    test('an MKV with AC-3 audio re-encodes the audio only', () {
      const probe = MediaProbe(container: 'matroska,webm', videoCodec: 'h264', audioCodec: 'ac3');
      final p = plan(probe);
      expect(p.mode, TranscodeMode.audioOnly);
      expect(p.isHeavy, isFalse);
      expect(argAfter(p.args, '-c:v'), 'copy');
      expect(argAfter(p.args, '-c:a'), 'aac');
    });

    test('H.265 forces a full transcode', () {
      // Safari plays HEVC, Chromium usually does not; guessing wrong is a
      // black screen, so it always gets converted.
      const probe = MediaProbe(container: 'matroska,webm', videoCodec: 'hevc', audioCodec: 'aac');
      final p = plan(probe);
      expect(p.mode, TranscodeMode.full);
      expect(p.isHeavy, isTrue);
    });

    test('an old DivX AVI forces a full transcode', () {
      const probe = MediaProbe(container: 'avi', videoCodec: 'mpeg4', audioCodec: 'mp3');
      expect(plan(probe).mode, TranscodeMode.full);
    });

    test('a file with no audio track is still fine', () {
      const probe = MediaProbe(container: 'matroska,webm', videoCodec: 'h264', audioCodec: '');
      expect(plan(probe).mode, TranscodeMode.remux);
    });
  });

  group('the command itself', () {
    const mkv = MediaProbe(container: 'matroska,webm', videoCodec: 'hevc', audioCodec: 'dts');

    test('uses the phone encoder chip when it can', () {
      expect(argAfter(plan(mkv).args, '-c:v'), 'h264_mediacodec');
    });

    test('falls back to software encoding', () {
      final p = plan(mkv, hardware: false);
      expect(argAfter(p.args, '-c:v'), 'libx264');
      expect(p.args, contains('-preset'));
    });

    test('always writes a fragmented MP4, so it can play while being written', () {
      final p = plan(mkv);
      expect(argAfter(p.args, '-movflags'), contains('frag_keyframe'));
      expect(argAfter(p.args, '-movflags'), contains('empty_moov'));
      expect(argAfter(p.args, '-f'), 'mp4');
      expect(p.args.last, '/pipe/out');
    });

    test('drops everything that cannot go into an MP4', () {
      // Embedded subtitles and font attachments abort the mux otherwise.
      final p = plan(mkv);
      expect(p.args, contains('-sn'));
      expect(p.args, contains('-dn'));
      expect(argAfter(p.args, '-map'), '0:v:0');
      // The audio mapping is optional so a silent file still works.
      expect(p.args, contains('0:a:0?'));
    });

    test('seeks before the input, so restarting at an offset is quick', () {
      final p = plan(mkv, start: const Duration(minutes: 12, seconds: 30));
      final ss = p.args.indexOf('-ss');
      final i = p.args.indexOf('-i');
      expect(ss, isNonNegative);
      expect(ss, lessThan(i), reason: '-ss must come before -i to seek by keyframe');
      expect(p.args[ss + 1], '750.000');
    });

    test('omits the seek entirely when starting from the beginning', () {
      expect(plan(mkv).args, isNot(contains('-ss')));
    });

    test('never builds a shell string', () {
      // Every argument is separate, so a file name with spaces or quotes
      // cannot turn into extra arguments.
      final p = plan(mkv);
      expect(p.args.where((a) => a.contains(' ')), isEmpty);
    });
  });

  group('codec tables', () {
    test('only codecs browsers actually decode are accepted', () {
      expect(BrowserCompat.videoOk('hevc'), isFalse);
      expect(BrowserCompat.videoOk('h264'), isTrue);
      expect(BrowserCompat.videoOk('vp9'), isTrue);
      expect(BrowserCompat.audioOk('ac3'), isFalse);
      expect(BrowserCompat.audioOk('dts'), isFalse);
      expect(BrowserCompat.audioOk('aac'), isTrue);
    });

    test('matroska is judged by its codecs, not its name', () {
      // FFmpeg reports "matroska,webm" for a .mkv and a .webm alike, so the
      // container name proves nothing. Only the codec set decides.
      const asWebm = MediaProbe(
        container: 'matroska,webm', videoCodec: 'vp9', audioCodec: 'opus');
      const asMkv = MediaProbe(
        container: 'matroska,webm', videoCodec: 'h264', audioCodec: 'aac');

      expect(BrowserCompat.canPlay(asWebm), isTrue,
          reason: 'VP9 + Opus in Matroska is a WebM and plays');
      expect(BrowserCompat.canPlay(asMkv), isFalse,
          reason: 'H.264 + AAC in Matroska does not play, whatever it is called');
    });

    test('H.264 in Matroska is caught and cheaply rewrapped', () {
      const probe = MediaProbe(
        container: 'matroska,webm', videoCodec: 'h264', audioCodec: 'aac');
      final p = planForBrowser(probe, input: 'a.mkv', output: 'out');
      expect(p.mode, TranscodeMode.remux);
    });
  });
}
