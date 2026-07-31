// Runs the real HostServer against a real file so the browser player can be
// driven exactly the way the phone drives it.
import 'dart:convert';
import 'dart:io';

import 'package:lan_cast/media/url_source.dart';
import 'package:lan_cast/model/protocol.dart';
import 'package:lan_cast/net/host_server.dart';

Future<void> main(List<String> args) async {
  final videoPath = args[0];
  final subPath = args[1];

  final server = HostServer(deviceName: 'Pixel آزمایشی')
    // In the app this reads the asset bundle; from the command line the same
    // files are simply sitting on disk.
    ..assetLoader = (key) async {
      final f = File(key);
      return f.existsSync() ? f.readAsBytesSync() : null;
    };
  await server.start();

  final media = CastMedia(
    id: 'm1',
    title: 'Big Buck Test',
    path: videoPath,
    size: await File(videoPath).length(),
    mime: 'video/webm',
    subtitles: [
      SubtitleTrack(id: 's1', label: 'فارسی', path: subPath),
    ],
  );
  server.publish(media);

  server.joinStream.listen((peer) {
    stderr.writeln('JOIN ${peer.kind} ${peer.name}');
  });
  server.stateStream.listen((s) {
    stdout.writeln(jsonEncode({'state': s.positionMs, 'playing': s.playing}));
  });

  stdout.writeln('READY ${server.port}');

  // Commands arrive on stdin, one JSON object per line — this stands in for
  // the phone's remote UI.
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final msg = jsonDecode(line) as Map<String, Object?>;
    switch (msg['do']) {
      case 'load':
        server.send(CastCommand.load(media, startMs: (msg['at'] as num?)?.toInt() ?? 0, subId: 's1'));
        server.send(CastCommand.subStyle(const SubtitleStyleSpec(sizePx: 40, bottomPct: 8)));
      case 'link':
        // Mirrors SenderController.castLink for a pasted URL.
        final source = UrlSource.parse(msg['url']! as String);
        if (source == null) {
          stdout.writeln(jsonEncode({'linkError': msg['url']}));
          break;
        }
        final remote = CastMedia(
          id: 'r1',
          title: source.title,
          path: source.url,
          size: 0,
          kind: source.kind,
          youtubeId: source.youtubeId,
        );
        server.publish(remote);
        stdout.writeln(jsonEncode({'linkKind': source.kind.name}));
        server.send(CastCommand.load(remote));
      case 'pause':
        server.send(CastCommand.pause);
      case 'play':
        server.send(CastCommand.play);
      case 'seek':
        server.send(CastCommand.seek((msg['ms'] as num).toInt()));
      case 'subDelay':
        server.send(CastCommand.subDelay((msg['ms'] as num).toInt()));
      case 'style':
        server.send(CastCommand.subStyle(SubtitleStyleSpec(
          sizePx: (msg['size'] as num?)?.toDouble() ?? 40,
          color: (msg['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
          backdrop: (msg['backdrop'] as num?)?.toDouble() ?? .35,
          bottomPct: (msg['bottom'] as num?)?.toDouble() ?? 8,
        )));
      case 'quit':
        server.dispose();
        exit(0);
    }
  }
}
