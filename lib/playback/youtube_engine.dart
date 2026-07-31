import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/log.dart';
import '../model/protocol.dart';
import 'playback_engine.dart';

/// YouTube, through YouTube's own embedded player.
///
/// We deliberately do not pull the underlying stream out of a YouTube page:
/// that breaks their terms and breaks in practice every few weeks. The
/// official IFrame API instead gives us real play/pause/seek control, and
/// YouTube handles the bitrate ladder itself — which is the adaptive-quality
/// behaviour we want anyway.
class YoutubeEngine extends PlaybackEngine {
  YoutubeEngine() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('LanCast', onMessageReceived: _onMessage);

    // Without this the embed refuses to start until someone touches the TV.
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  late final WebViewController _controller;
  Timer? _poll;
  EngineState _state = const EngineState();
  bool _apiReady = false;

  @override
  EngineState get state => _state;

  @override
  String get label => 'YouTube';

  @override
  Future<void> open(String url, {Duration start = Duration.zero}) async {
    final id = _idOf(url);
    if (id == null) {
      _state = _state.copyWith(error: 'شناسه‌ی ویدیوی یوتیوب پیدا نشد');
      notifyListeners();
      return;
    }
    _apiReady = false;
    _state = const EngineState();
    notifyListeners();

    // The page must be served from a youtube.com origin for the IFrame API to
    // accept it, which is what baseUrl is doing here.
    await _controller.loadHtmlString(
      _page(id, start.inSeconds),
      baseUrl: 'https://www.youtube.com',
    );

    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollState());
  }

  void _onMessage(JavaScriptMessage message) {
    Map<String, Object?> data;
    try {
      data = (jsonDecode(message.message) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    if (data['t'] == 'ready') {
      _apiReady = true;
      return;
    }
    if (data['t'] != 'state') return;

    final durationSec = (data['dur'] as num?)?.toDouble() ?? 0;
    _state = _state.copyWith(
      position: _seconds((data['pos'] as num?)?.toDouble() ?? 0),
      // A YouTube livestream reports duration 0, same as our other engines.
      duration: _seconds(durationSec),
      buffered: _seconds(((data['loaded'] as num?)?.toDouble() ?? 0) * durationSec),
      playing: data['playing'] == true,
      buffering: data['buffering'] == true,
      ready: true,
      quality: (data['q'] as String?) ?? '',
      clearError: true,
    );
    notifyListeners();
  }

  static Duration _seconds(double v) =>
      Duration(milliseconds: (v * 1000).round().clamp(0, 1 << 40));

  Future<void> _pollState() async {
    if (!_apiReady) return;
    try {
      await _controller.runJavaScript('window.lcReport && window.lcReport();');
    } catch (e) {
      logDebug('youtube poll failed: $e');
    }
  }

  Future<void> _call(String js) async {
    if (!_apiReady) return;
    try {
      await _controller.runJavaScript(js);
    } catch (e) {
      logDebug('youtube call failed: $e');
    }
  }

  @override
  Future<void> play() => _call('window.lcPlayer && window.lcPlayer.playVideo();');

  @override
  Future<void> pause() => _call('window.lcPlayer && window.lcPlayer.pauseVideo();');

  @override
  Future<void> seek(Duration to) => _call(
        'window.lcPlayer && window.lcPlayer.seekTo(${to.inMilliseconds / 1000}, true);',
      );

  @override
  Future<void> setRate(double rate) =>
      _call('window.lcPlayer && window.lcPlayer.setPlaybackRate($rate);');

  @override
  Future<void> setVolume(double volume) => _call(
        'window.lcPlayer && window.lcPlayer.setVolume(${(volume.clamp(0, 1) * 100).round()});',
      );

  @override
  Widget surface(VideoFit fit) => ColoredBox(
        color: Colors.black,
        // The embed letterboxes itself; stretching it would only distort the
        // player chrome along with the picture.
        child: WebViewWidget(controller: _controller),
      );

  @override
  Future<void> release() async {
    _poll?.cancel();
    _poll = null;
    _apiReady = false;
    try {
      await _controller.loadHtmlString('<html><body style="background:#000"></body></html>');
    } catch (_) {
      // The view may already be gone.
    }
  }

  static String? _idOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.endsWith('youtu.be')) {
      return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    }
    final v = uri.queryParameters['v'];
    if (v != null) return v;
    for (final prefix in const ['embed', 'shorts', 'live', 'v']) {
      final i = uri.pathSegments.indexOf(prefix);
      if (i >= 0 && i + 1 < uri.pathSegments.length) return uri.pathSegments[i + 1];
    }
    return null;
  }

  static String _page(String videoId, int startSeconds) => '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
  #player{width:100%;height:100%}
</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
  function post(o){ try { LanCast.postMessage(JSON.stringify(o)); } catch(e){} }

  window.lcPlayer = null;
  var buffering = false;

  function onYouTubeIframeAPIReady() {
    window.lcPlayer = new YT.Player('player', {
      videoId: '$videoId',
      playerVars: {
        autoplay: 1, playsinline: 1, rel: 0, modestbranding: 1,
        start: $startSeconds, controls: 0, iv_load_policy: 3
      },
      events: {
        onReady: function(e){ e.target.playVideo(); post({t:'ready'}); window.lcReport(); },
        onStateChange: function(e){
          buffering = (e.data === YT.PlayerState.BUFFERING);
          window.lcReport();
        },
        onError: function(e){ post({t:'state', err: 'code ' + e.data}); }
      }
    });
  }

  window.lcReport = function(){
    var p = window.lcPlayer;
    if (!p || !p.getPlayerState) return;
    post({
      t: 'state',
      pos: p.getCurrentTime ? p.getCurrentTime() : 0,
      dur: p.getDuration ? p.getDuration() : 0,
      loaded: p.getVideoLoadedFraction ? p.getVideoLoadedFraction() : 0,
      playing: p.getPlayerState() === YT.PlayerState.PLAYING,
      buffering: buffering,
      q: p.getPlaybackQuality ? p.getPlaybackQuality() : ''
    });
  };
</script>
</body>
</html>
''';
}
