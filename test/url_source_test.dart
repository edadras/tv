import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cast/media/url_source.dart';
import 'package:lan_cast/model/protocol.dart';

void main() {
  UrlSource? parse(String s) => UrlSource.parse(s);

  group('YouTube links', () {
    const ids = {
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s': 'dQw4w9WgXcQ',
      'https://m.youtube.com/watch?v=dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://youtu.be/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://youtu.be/dQw4w9WgXcQ?t=30': 'dQw4w9WgXcQ',
      'https://www.youtube.com/embed/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://www.youtube.com/shorts/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://www.youtube.com/live/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
    };

    test('every common YouTube URL shape yields the video id', () {
      ids.forEach((url, id) {
        final source = parse(url);
        expect(source, isNotNull, reason: url);
        expect(source!.kind, MediaKind.youtube, reason: url);
        expect(source.youtubeId, id, reason: url);
      });
    });

    test('a timestamped link starts where it says', () {
      expect(parse('https://youtu.be/dQw4w9WgXcQ?t=90')?.startAt,
          const Duration(seconds: 90));
      expect(parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s')?.startAt,
          const Duration(minutes: 1, seconds: 30));
      expect(parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s')?.startAt,
          const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(parse('https://youtu.be/dQw4w9WgXcQ')?.startAt, Duration.zero);
      expect(parse('https://youtu.be/dQw4w9WgXcQ?t=junk')?.startAt, Duration.zero);
    });

    test('a YouTube URL without a video is not treated as YouTube', () {
      // A channel page has nothing to play.
      final source = parse('https://www.youtube.com/@someone');
      expect(source?.kind, isNot(MediaKind.youtube));
    });
  });

  group('adaptive streams', () {
    test('manifests and real-time protocols are marked adaptive', () {
      for (final url in const [
        'https://cdn.example.com/live/stream.m3u8',
        'http://example.com/channel/index.M3U8',
        'https://example.com/vod/manifest.mpd',
        'https://example.com/smooth/movie.ism',
        'rtsp://192.168.1.9:554/stream1',
        'rtmp://example.com/live/key',
      ]) {
        expect(parse(url)?.kind, MediaKind.adaptive, reason: url);
      }
    });

    test('a manifest hidden in the query string is still adaptive', () {
      expect(
        parse('https://iptv.example.com/play?id=7&type=m3u8')?.kind,
        MediaKind.adaptive,
      );
    });
  });

  group('direct video links', () {
    test('ordinary files play directly', () {
      for (final url in const [
        'https://example.com/movies/film.mp4',
        'https://example.com/film.mkv',
        'http://192.168.1.50:8096/video.avi',
      ]) {
        expect(parse(url)?.kind, MediaKind.direct, reason: url);
      }
    });

    test('the title comes from the file name, without the extension', () {
      expect(parse('https://example.com/movies/The%20Film.mp4')?.title, 'The Film');
      expect(parse('https://example.com/')?.title, 'example.com');
    });
  });

  group('lenient input', () {
    test('a missing scheme is filled in', () {
      final source = parse('youtube.com/watch?v=dQw4w9WgXcQ');
      expect(source?.kind, MediaKind.youtube);
      expect(source?.url, startsWith('https://'));
    });

    test('surrounding whitespace is ignored', () {
      expect(parse('  https://example.com/a.mp4  ')?.url, 'https://example.com/a.mp4');
    });

    test('things that are not links are rejected', () {
      for (final text in const [
        '',
        '   ',
        'just some text',
        'file:///sdcard/movie.mp4',
        'javascript:alert(1)',
      ]) {
        expect(parse(text), isNull, reason: '"$text"');
      }
    });
  });
}
