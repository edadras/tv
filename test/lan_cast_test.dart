import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cast/core/format.dart';
import 'package:lan_cast/core/text_codec.dart';
import 'package:lan_cast/model/protocol.dart';
import 'package:lan_cast/net/lan.dart';
import 'package:lan_cast/net/receiver_link.dart';
import 'package:lan_cast/subs/subtitle_doc.dart';

void main() {
  group('subtitle parsing', () {
    test('reads a plain SRT file', () {
      final doc = SubtitleDoc.parse('''
1
00:00:01,000 --> 00:00:03,500
Hello there

2
00:01:02,250 --> 00:01:04,000
Second line
spanning two rows
''');

      expect(doc.cues, hasLength(2));
      expect(doc.cues.first.startMs, 1000);
      expect(doc.cues.first.endMs, 3500);
      expect(doc.cues.first.text, 'Hello there');
      expect(doc.cues[1].startMs, 62250);
      expect(doc.cues[1].text, 'Second line\nspanning two rows');
    });

    test('strips markup and decodes entities', () {
      final doc = SubtitleDoc.parse('''
1
00:00:01,000 --> 00:00:02,000
<i>Tom &amp; Jerry</i>
''');
      expect(doc.cues.single.text, 'Tom & Jerry');
    });

    test('reads WebVTT with dot separators and skips NOTE blocks', () {
      final doc = SubtitleDoc.parse('''WEBVTT

NOTE this should be ignored

1
00:00:04.000 --> 00:00:06.000
From a VTT file
''');
      expect(doc.cues, hasLength(1));
      expect(doc.cues.single.startMs, 4000);
      expect(doc.cues.single.text, 'From a VTT file');
    });

    test('reads ASS dialogue with the declared field order', () {
      final doc = SubtitleDoc.parse('''[Script Info]
Title: test

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:05.00,0:00:07.50,Default,,0,0,0,,{\\an8}Styled, with a comma
''');
      expect(doc.cues, hasLength(1));
      expect(doc.cues.single.startMs, 5000);
      expect(doc.cues.single.endMs, 7500);
      // The override block goes, the comma inside the text stays.
      expect(doc.cues.single.text, 'Styled, with a comma');
    });

    test('drops cues that end before they start', () {
      final doc = SubtitleDoc.parse('''
1
00:00:09,000 --> 00:00:08,000
backwards
''');
      expect(doc.cues, isEmpty);
    });
  });

  group('cue lookup', () {
    SubtitleDoc build() => SubtitleDoc.parse('''
1
00:00:01,000 --> 00:00:02,000
one

2
00:00:03,000 --> 00:00:04,000
two

3
00:00:10,000 --> 00:00:12,000
three
''');

    test('finds the cue covering a moment, and nothing in the gaps', () {
      final doc = build();
      expect(doc.cueAt(1500)?.text, 'one');
      expect(doc.cueAt(2500), isNull);
      expect(doc.cueAt(3000)?.text, 'two');
      expect(doc.cueAt(3999)?.text, 'two');
      expect(doc.cueAt(4000), isNull);
    });

    test('survives a backwards seek', () {
      final doc = build();
      expect(doc.cueAt(11000)?.text, 'three');
      expect(doc.cueAt(1200)?.text, 'one');
      expect(doc.cueAt(0), isNull);
    });

    test('a sync offset just shifts the lookup', () {
      final doc = build();
      // +500 ms delay: the cue that used to show at 1000 now shows at 1500.
      const delay = 500;
      expect(doc.cueAt(1200 - delay), isNull);
      expect(doc.cueAt(1600 - delay)?.text, 'one');
    });
  });

  group('WebVTT export', () {
    test('round-trips through the browser format', () {
      final doc = SubtitleDoc.parse('''
1
01:02:03,400 --> 01:02:05,000
round trip
''');
      final vtt = doc.toVtt();
      expect(vtt, startsWith('WEBVTT'));
      expect(vtt, contains('01:02:03.400 --> 01:02:05.000'));

      final reparsed = SubtitleDoc.parse(vtt);
      expect(reparsed.cues.single.startMs, doc.cues.single.startMs);
      expect(reparsed.cues.single.text, 'round trip');
    });
  });

  group('text decoding', () {
    test('keeps UTF-8 as UTF-8', () {
      final bytes = Uint8List.fromList(utf8.encode('سلام دنیا'));
      expect(TextCodec.decode(bytes), 'سلام دنیا');
    });

    test('strips a UTF-8 BOM', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('hi')]);
      expect(TextCodec.decode(bytes), 'hi');
    });

    test('decodes a Windows-1256 Persian subtitle', () {
      // "سلام" in CP1256, which is not valid UTF-8.
      final bytes = Uint8List.fromList([0xD3, 0xE1, 0xC7, 0xE3]);
      expect(TextCodec.decode(bytes), 'سلام');
    });

    test('falls back to Windows-1252 for Western high bytes', () {
      // "café" in CP1252.
      final bytes = Uint8List.fromList([0x63, 0x61, 0x66, 0xE9]);
      expect(TextCodec.decode(bytes), 'café');
    });


    test('rewrites CP1256 Persian text to Persian yeh and kaf', () {
      // "گیک" — has gaf (Persian-only), plus Arabic yeh and kaf from CP1256.
      final bytes = Uint8List.fromList([0x90, 0xED, 0xDF]);
      expect(TextCodec.decode(bytes), 'گیک');
    });

    test('leaves Arabic text alone', () {
      // "كي" in CP1256 with no Persian-only letter anywhere: keep it Arabic.
      final bytes = Uint8List.fromList([0xDF, 0xED, 0xC7, 0xE1, 0xE3]);
      final text = TextCodec.decode(bytes);
      expect(text, contains('ك'));
      expect(text, contains('ي'));
    });

    test('normalises CRLF line endings', () {
      final bytes = Uint8List.fromList(utf8.encode('a\r\nb\rc'));
      expect(TextCodec.decode(bytes), 'a\nb\nc');
    });
  });

  group('protocol', () {
    test('a snapshot survives a JSON round trip', () {
      const original = PlayerSnapshot(
        title: 'فیلم',
        positionMs: 1234,
        durationMs: 7200000,
        playing: true,
        subId: 'abc',
        subDelayMs: -750,
        rate: 1.5,
        fit: VideoFit.cover,
        style: SubtitleStyleSpec(sizePx: 42, color: 0xFFFFE58A, bottomPct: 9),
        receiver: 'TV',
      );
      final copy = PlayerSnapshot.fromJson(
        (jsonDecode(jsonEncode(original.toJson())) as Map).cast<String, Object?>(),
      );

      expect(copy.title, 'فیلم');
      expect(copy.positionMs, 1234);
      expect(copy.playing, isTrue);
      expect(copy.subId, 'abc');
      expect(copy.subDelayMs, -750);
      expect(copy.rate, 1.5);
      expect(copy.fit, VideoFit.cover);
      expect(copy.style.sizePx, 42);
      expect(copy.style.color, 0xFFFFE58A);
      expect(copy.style.bottomPct, 9);
      expect(copy.progress, closeTo(1234 / 7200000, 1e-9));
    });

    test('commands carry their payload under a type tag', () {
      final cmd = CastCommand.seek(90000);
      expect(cmd.toJson(), {'t': 'seek', 'pos': 90000});

      final decoded = CastCommand.fromJson(
        (jsonDecode(jsonEncode(cmd.toJson())) as Map).cast<String, Object?>(),
      );
      expect(decoded.type, 'seek');
      expect(decoded.data['pos'], 90000);
    });

    test('media exposes relative URLs so the receiver resolves them itself', () {
      const media = CastMedia(id: 'x1', title: 'Film', path: '/sdcard/a.mkv', size: 10);
      expect(media.url, '/media/x1');
      expect(media.toJson()['url'], '/media/x1');
      // The host-side path must never go over the wire.
      expect(jsonEncode(media.toJson()), isNot(contains('sdcard')));
    });

    test('an unknown fit value degrades to contain', () {
      final snap = PlayerSnapshot.fromJson({'fit': 'nonsense'});
      expect(snap.fit, VideoFit.contain);
    });
  });

  group('host addressing', () {
    test('normalises whatever the user types', () {
      expect(ReceiverLink.normalizeHost('192.168.1.5'), 'http://192.168.1.5:8787');
      expect(ReceiverLink.normalizeHost('192.168.1.5:9000'), 'http://192.168.1.5:9000');
      expect(ReceiverLink.normalizeHost('http://10.0.0.2:8787'), 'http://10.0.0.2:8787');
      expect(ReceiverLink.normalizeHost(' ws://10.0.0.2:8787 '), 'http://10.0.0.2:8787');
    });

    test('derives the /24 broadcast address', () {
      expect(Lan.broadcastFor('192.168.1.5'), '192.168.1.255');
      expect(Lan.broadcastFor('nonsense'), isNull);
    });
  });

  group('formatting', () {
    test('durations use Persian digits and drop empty hours', () {
      expect(Fmt.duration(const Duration(minutes: 4, seconds: 7)), '۰۴:۰۷');
      expect(Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 3)), '۱:۰۲:۰۳');
      expect(Fmt.duration(const Duration(seconds: -5)), '۰۰:۰۰');
    });

    test('subtitle offsets read as signed seconds', () {
      expect(Fmt.offset(0), '۰٫۰');
      expect(Fmt.offset(1500), '+۱٫۵');
      expect(Fmt.offset(-750), '−۰٫۸');
    });

    test('file names lose scene-release punctuation', () {
      expect(Fmt.title('The.Movie.2019.1080p'), 'The Movie 2019 1080p');
    });
  });
}
