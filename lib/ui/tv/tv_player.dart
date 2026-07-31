import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/receiver_controller.dart';
import '../../state/scope.dart';
import '../../subs/subtitle_view.dart';
import '../common/glass.dart';

/// Full-screen playback with a glass OSD that appears on any remote press and
/// fades away again. The phone stays the main remote; this is the fallback for
/// when it is across the room.
class TvPlayer extends StatefulWidget {
  const TvPlayer({super.key});

  @override
  State<TvPlayer> createState() => _TvPlayerState();
}

class _TvPlayerState extends State<TvPlayer> {
  bool _osd = true;
  Timer? _hideTimer;
  final _focus = FocusNode(debugLabel: 'tv-player');

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showOsd() {
    if (!_osd) setState(() => _osd = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && ReceiverScope.read(context).isPlaying) setState(() => _osd = false);
    });
  }

  KeyEventResult _onKey(ReceiverController receiver, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    _showOsd();

    if (key == LogicalKeyboardKey.arrowRight) {
      receiver.nudge(10000);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      receiver.nudge(-10000);
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      receiver.togglePlay();
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      receiver.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      receiver.nudgeSubDelay(100);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      receiver.nudgeSubDelay(-100);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final receiver = ReceiverScope.of(context);
    final engine = receiver.engine;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) => _onKey(receiver, event),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showOsd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (engine != null)
                engine.surface(receiver.fit)
              else
                const ColoredBox(color: Colors.black),

              // Subtitles repaint on their own notifier so the video surface
              // is never rebuilt for a cue change.
              ValueListenableBuilder<String?>(
                valueListenable: receiver.currentCue,
                builder: (context, cue, _) => SubtitleOverlay(
                  text: cue,
                  style: receiver.style,
                  scale: MediaQuery.sizeOf(context).height / 1080,
                ),
              ),

              if (receiver.loading || receiver.engine?.state.buffering == true)
                const Center(
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Sea.azure),
                  ),
                ),

              if (receiver.error != null)
                Center(
                  child: GlassPanel(
                    strong: true,
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Sea.danger, size: 38),
                        const SizedBox(height: 12),
                        Text(
                          receiver.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Sea.text, fontSize: 17, height: 1.8),
                        ),
                      ],
                    ),
                  ),
                ),

              AnimatedOpacity(
                opacity: _osd ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                child: IgnorePointer(
                  ignoring: !_osd,
                  child: _Osd(receiver: receiver),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Osd extends StatelessWidget {
  const _Osd({required this.receiver});

  final ReceiverController receiver;

  @override
  Widget build(BuildContext context) {
    final duration = receiver.duration;
    final position = receiver.position;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Column(
      children: [
        // Top: title + connection.
        Padding(
          padding: const EdgeInsets.all(24),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    Fmt.title(receiver.media?.title ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Sea.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                StatusPill(
                  label: receiver.link.isConnected ? 'کنترل از گوشی' : 'ارتباط قطع شد',
                  color: receiver.link.isConnected ? Sea.ok : Sea.danger,
                  icon: Icons.settings_remote_rounded,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        // Bottom: transport.
        Padding(
          padding: const EdgeInsets.all(24),
          child: GlassPanel(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
            child: Column(
              children: [
                if (receiver.isLive)
                  const Row(
                    children: [
                      _LiveDot(),
                      SizedBox(width: 10),
                      Text(
                        'پخش زنده',
                        style: TextStyle(
                          color: Sea.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Spacer(),
                    ],
                  )
                else
                Row(
                  children: [
                    Text(
                      Fmt.duration(position),
                      style: const TextStyle(
                        color: Sea.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: const Color(0x33FFFFFF),
                          valueColor: const AlwaysStoppedAnimation(Sea.azure),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      Fmt.duration(duration),
                      style: const TextStyle(color: Sea.textFaint, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlassIconButton(
                      icon: Icons.replay_10_rounded,
                      size: 52,
                      onPressed: receiver.isLive ? null : () => receiver.nudge(-10000),
                    ),
                    const SizedBox(width: 18),
                    GlassIconButton(
                      icon: receiver.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      primary: true,
                      size: 68,
                      autofocus: true,
                      onPressed: receiver.togglePlay,
                    ),
                    const SizedBox(width: 18),
                    GlassIconButton(
                      icon: Icons.forward_10_rounded,
                      size: 52,
                      onPressed: receiver.isLive ? null : () => receiver.nudge(10000),
                    ),
                    const SizedBox(width: 34),
                    if (receiver.supportsSubtitles)
                      _Readout(
                        icon: Icons.subtitles_rounded,
                        label: receiver.subId == null
                            ? 'زیرنویس خاموش'
                            : '${Fmt.offset(receiver.subDelayMs)} ثانیه',
                      ),
                    if (receiver.engine?.state.quality.isNotEmpty ?? false) ...[
                      const SizedBox(width: 12),
                      _Readout(
                        icon: Icons.hd_rounded,
                        label: '${Fmt.digits(receiver.engine!.state.quality)} • خودکار',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'کلیدها: چپ/راست جلو و عقب • OK پخش و مکث • بالا/پایین تنظیم زیرنویس',
                  style: TextStyle(color: Sea.textFaint, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Sea.glassFill,
        borderRadius: BorderRadius.circular(Sea.radiusSm),
        border: Border.all(color: Sea.glassStrokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: Sea.aqua),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Sea.text, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Pulsing dot that marks a live feed.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: .35, end: 1).animate(_pulse),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Sea.danger,
          boxShadow: [BoxShadow(color: Sea.danger, blurRadius: 12)],
        ),
      ),
    );
  }
}
