import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cast/model/protocol.dart';
import 'package:lan_cast/net/host_server.dart';

/// Exercises the real server over a real socket: byte ranges, subtitle
/// conversion and the control hub. This is the path a film actually takes.
void main() {
  late Directory temp;
  late HostServer server;
  late String base;
  late CastMedia media;

  /// 64 KiB of recognisable bytes standing in for a film.
  final videoBytes = Uint8List.fromList(
    List<int>.generate(64 * 1024, (i) => i % 256),
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lancast_test');

    final videoFile = File('${temp.path}/movie.mp4')..writeAsBytesSync(videoBytes);

    // A Windows-1256 Persian subtitle: the awkward real-world case.
    final subFile = File('${temp.path}/movie.srt')
      ..writeAsBytesSync(Uint8List.fromList([
        ...utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n'),
        0xD3, 0xE1, 0xC7, 0xE3, // "سلام" in CP1256
        0x0A, 0x0A,
      ]));

    media = CastMedia(
      id: 'm1',
      title: 'movie',
      path: videoFile.path,
      size: videoBytes.length,
      mime: 'video/mp4',
      subtitles: [SubtitleTrack(id: 's1', label: 'Persian', path: subFile.path)],
    );

    server = HostServer(deviceName: 'Test Phone')..publish(media);
    await server.start();
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    server.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Future<HttpClientResponse> get(String path, {String? range, String method = 'GET'}) async {
    final client = HttpClient();
    final req = await client.openUrl(method, Uri.parse('$base$path'));
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    return req.close();
  }

  Future<List<int>> body(HttpClientResponse res) async {
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    return out;
  }

  group('media streaming', () {
    test('serves the whole file when no range is asked for', () async {
      final res = await get(media.url);
      expect(res.statusCode, 200);
      expect(res.headers.value('accept-ranges'), 'bytes');
      expect(res.contentLength, videoBytes.length);
      expect(await body(res), videoBytes);
    });

    test('serves a byte range as 206 with the right slice', () async {
      final res = await get(media.url, range: 'bytes=100-199');
      expect(res.statusCode, 206);
      expect(
        res.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-199/${videoBytes.length}',
      );
      final bytes = await body(res);
      expect(bytes, hasLength(100));
      expect(bytes, videoBytes.sublist(100, 200));
    });

    test('an open-ended range runs to the end of the file', () async {
      final res = await get(media.url, range: 'bytes=65000-');
      expect(res.statusCode, 206);
      final bytes = await body(res);
      expect(bytes, hasLength(videoBytes.length - 65000));
      expect(bytes.first, videoBytes[65000]);
    });

    test('a suffix range returns the tail', () async {
      final res = await get(media.url, range: 'bytes=-500');
      expect(res.statusCode, 206);
      expect(await body(res), videoBytes.sublist(videoBytes.length - 500));
    });

    test('a range past the end is rejected, not truncated', () async {
      final res = await get(media.url, range: 'bytes=999999-');
      expect(res.statusCode, 416);
      expect(res.headers.value(HttpHeaders.contentRangeHeader),
          'bytes */${videoBytes.length}');
    });

    test('HEAD reports the size without sending the body', () async {
      final res = await get(media.url, method: 'HEAD');
      expect(res.statusCode, 200);
      expect(res.headers.contentLength, videoBytes.length);
      expect(await body(res), isEmpty);
    });

    test('an unknown id is a 404', () async {
      expect((await get('/media/nope')).statusCode, 404);
    });
  });

  group('subtitles', () {
    test('converts any encoding and format to WebVTT', () async {
      final res = await get('/sub/s1.vtt');
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'text/vtt');

      final text = utf8.decode(await body(res));
      expect(text, startsWith('WEBVTT'));
      expect(text, contains('00:00:01.000 --> 00:00:02.000'));
      // The CP1256 bytes came back out as proper Persian.
      expect(text, contains('سلام'));
    });
  });

  group('fonts', () {
    test('are served only for the two names the page asks for', () async {
      server.assetLoader = (key) async =>
          key.endsWith('.ttf') ? utf8.encode('FAKE-TTF-$key') : null;

      final ok = await get('/font/regular.ttf');
      expect(ok.statusCode, 200);
      expect(ok.headers.contentType.toString(), startsWith('font/ttf'));
      expect(utf8.decode(await body(ok)), contains('Vazirmatn-Regular.ttf'));

      // The asset path is fixed per name, so a traversal attempt finds nothing.
      expect((await get('/font/../../etc/passwd')).statusCode, 404);
      expect((await get('/font/anything-else.ttf')).statusCode, 404);
    });

    test('degrade to a 404 when the host has no asset bundle', () async {
      server.assetLoader = null;
      expect((await get('/font/regular.ttf')).statusCode, 404);
    });
  });

  group('converted streams', () {
    test('/stream falls back to the original when nothing needs converting', () async {
      // A null return means "the browser can play this as-is".
      server.transcoder = (path, start) async => null;
      final res = await get('/stream/m1');
      expect(res.statusCode, 200);
      expect(res.headers.value('accept-ranges'), 'bytes');
      expect(await body(res), videoBytes);
    });

    test('/stream pipes converted bytes out as they are produced', () async {
      final produced = <int>[];
      var closed = false;
      server.transcoder = (path, start) async {
        expect(path, media.path, reason: 'the host path, not the URL');
        return HostedStream(
          bytes: Stream.fromIterable([
            [1, 2, 3],
            [4, 5, 6],
          ]).map((chunk) {
            produced.addAll(chunk);
            return chunk;
          }),
          close: () async => closed = true,
        );
      };

      final res = await get('/stream/m1');
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'video/mp4');
      // A converted stream has no length and cannot be range-requested.
      expect(res.headers.value('accept-ranges'), 'none');
      expect(await body(res), [1, 2, 3, 4, 5, 6]);
      expect(produced, [1, 2, 3, 4, 5, 6]);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isTrue, reason: 'the encoder must be stopped afterwards');
    });

    test('the ?t= offset reaches the encoder', () async {
      Duration? asked;
      server.transcoder = (path, start) async {
        asked = start;
        return HostedStream(bytes: const Stream.empty(), close: () async {});
      };
      await body(await get('/stream/m1?t=754.5'));
      expect(asked, const Duration(milliseconds: 754500));

      await body(await get('/stream/m1'));
      expect(asked, Duration.zero, reason: 'no offset means start at zero');
    });

    test('a converter that throws degrades to the original file', () async {
      server.transcoder = (path, start) async => throw StateError('no encoder');
      final res = await get('/stream/m1');
      expect(res.statusCode, 200);
      expect(await body(res), videoBytes);
    });

    test('the encoder is stopped when the viewer walks away mid-stream', () async {
      var closed = false;
      final forever = StreamController<List<int>>();
      server.transcoder = (path, start) async => HostedStream(
            bytes: forever.stream,
            close: () async {
              closed = true;
              if (!forever.isClosed) await forever.close();
            },
          );

      // A raw socket so the connection can be cut mid-response, which is what
      // a TV does when it seeks or the viewer navigates away.
      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.write('GET /stream/m1 HTTP/1.1\r\nHost: test\r\n\r\n');
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      forever.add([9, 9, 9]);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      socket.destroy();

      // Keep producing: the first write to the dead socket is what surfaces
      // the disconnect.
      for (var i = 0; i < 5 && !closed; i++) {
        forever.add(List<int>.filled(1024, 7));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }

      expect(closed, isTrue, reason: 'a dropped viewer must not keep the phone encoding');
    });

    test('/stream on an unknown id is a 404', () async {
      server.transcoder = (path, start) async => null;
      expect((await get('/stream/nope')).statusCode, 404);
    });
  });

  group('browser player', () {
    test('the root page is self-contained', () async {
      final res = await get('/');
      expect(res.statusCode, 200);
      final html = utf8.decode(await body(res));
      expect(html, contains('<video'));
      // Everything inline: no external script or stylesheet to fetch.
      expect(html, isNot(contains('<script src=')));
      expect(html, isNot(contains('<link rel="stylesheet"')));
      // The host name is interpolated into the page.
      expect(html, contains('Test Phone'));
    });

    test('/info lists what is published', () async {
      final res = await get('/info');
      final info = jsonDecode(utf8.decode(await body(res))) as Map<String, Object?>;
      expect(info['app'], 'lancast');
      expect(info['name'], 'Test Phone');
      expect((info['media'] as List).single, containsPair('url', '/media/m1'));
    });
  });

  group('control hub', () {
    Future<WebSocket> attach(String kind) => WebSocket.connect(
          '${base.replaceFirst('http', 'ws')}/ws?kind=$kind&name=Screen',
        );

    test('greets a receiver and reports it as a peer', () async {
      final socket = await attach('tv');
      final first = jsonDecode(await socket.first as String) as Map<String, Object?>;
      expect(first['t'], 'hello');
      expect(first['host'], 'Test Phone');
      expect(server.peers, hasLength(1));
      expect(server.peers.single.kind, 'tv');
      await socket.close();
    });

    test('a command reaches the receiver', () async {
      final socket = await attach('tv');
      final messages = <Map<String, Object?>>[];
      socket.listen((Object? d) =>
          messages.add((jsonDecode(d! as String) as Map).cast<String, Object?>()));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.send(CastCommand.seek(42000));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(messages.map((m) => m['t']), containsAll(['hello', 'seek']));
      expect(messages.last['pos'], 42000);
      await socket.close();
    });

    test('receiver state comes back to the host', () async {
      final socket = await attach('tv');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final received = server.stateStream.first;
      socket.add(jsonEncode(
        const PlayerSnapshot(
          title: 'movie',
          positionMs: 5000,
          durationMs: 60000,
          playing: true,
          ready: true,
          receiver: 'Screen',
        ).toJson(),
      ));

      final snap = await received.timeout(const Duration(seconds: 2));
      expect(snap.positionMs, 5000);
      expect(snap.playing, isTrue);
      expect(snap.receiver, 'Screen');
      await socket.close();
    });

    test('sendTo catches up one receiver without touching the other', () async {
      final a = await attach('tv');
      final b = await attach('web');
      final toA = <String>[];
      final toB = <String>[];
      a.listen((Object? d) => toA.add(jsonDecode(d! as String)['t'] as String));
      b.listen((Object? d) => toB.add(jsonDecode(d! as String)['t'] as String));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Drain the greetings before asserting.
      toA.clear();
      toB.clear();

      final peerB = server.peers.firstWhere((p) => p.kind == 'web');
      server.sendTo(peerB, CastCommand.load(media));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(toB, ['load']);
      expect(toA, isEmpty, reason: 'the other receiver must not be disturbed');
      await a.close();
      await b.close();
    });

    test('a receiver that leaves is dropped from the peer list', () async {
      final socket = await attach('tv');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.peers, hasLength(1));

      await socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(server.peers, isEmpty);
    });
  });
}
