import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../model/protocol.dart';
import '../../state/scope.dart';
import '../common/glass.dart';
import 'subtitle_sheet.dart';

/// The remote: everything you need while a film is playing on the TV.
class RemoteTab extends StatelessWidget {
  const RemoteTab({super.key});

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final snap = sender.snapshot;
    final hasMedia = sender.media != null;

    if (!hasMedia) return const _NothingPlaying();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        _NowPlaying(
          title: snap.title,
          receiver: snap.receiver,
          buffering: snap.buffering,
          kind: snap.kind,
          live: snap.live,
          quality: snap.quality,
        ),
        const SizedBox(height: 14),
        if (snap.live) const _LiveBar() else const _Scrubber(),
        const SizedBox(height: 14),
        const _Transport(),
        const SizedBox(height: 16),
        // Our subtitle engine cannot draw over YouTube's own player.
        if (snap.kind != MediaKind.youtube) ...[
          const _SubtitleCard(),
          const SizedBox(height: 12),
        ],
        const _ExtrasCard(),
        if (snap.error != null) ...[
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Sea.danger, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    snap.error!,
                    style: const TextStyle(color: Sea.textDim, fontSize: 12.5, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.title,
    required this.receiver,
    required this.buffering,
    required this.kind,
    required this.live,
    required this.quality,
  });

  final String title;
  final String receiver;
  final bool buffering;
  final MediaKind kind;
  final bool live;
  final String quality;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      strong: true,
      glow: Sea.azure,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: Sea.accentGradient,
            ),
            child: Icon(
              buffering ? Icons.hourglass_top_rounded : Icons.movie_creation_rounded,
              color: Sea.abyss,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.title(title),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Sea.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  receiver.isEmpty ? 'در انتظار پخش‌کننده…' : 'روی $receiver',
                  style: const TextStyle(color: Sea.textDim, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (live)
                      const StatusPill(
                        label: 'زنده',
                        color: Sea.danger,
                        icon: Icons.sensors_rounded,
                      ),
                    if (kind == MediaKind.youtube)
                      const StatusPill(
                        label: 'یوتیوب',
                        color: Sea.danger,
                        icon: Icons.smart_display_rounded,
                      ),
                    if (quality.isNotEmpty)
                      StatusPill(
                        label: '${Fmt.digits(quality)} • خودکار',
                        color: Sea.aqua,
                        icon: Icons.hd_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final snap = sender.snapshot;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: sender.displayProgress.clamp(0, 1),
              onChanged: snap.durationMs > 0 ? sender.scrubTo : null,
              onChangeEnd: (_) => sender.commitScrub(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Text(
                  Fmt.duration(sender.displayPosition),
                  style: const TextStyle(
                    color: Sea.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  Fmt.duration(snap.duration),
                  style: const TextStyle(color: Sea.textFaint, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final playing = sender.snapshot.playing;
    final live = sender.snapshot.live;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GlassIconButton(
            icon: Icons.stop_rounded,
            tooltip: 'توقف',
            size: 44,
            onPressed: sender.stop,
          ),
          GlassIconButton(
            icon: Icons.replay_30_rounded,
            tooltip: '۳۰ ثانیه عقب',
            size: 50,
            onPressed: live ? null : () => sender.nudge(-30000),
          ),
          GlassIconButton(
            icon: Icons.replay_10_rounded,
            tooltip: '۱۰ ثانیه عقب',
            size: 50,
            onPressed: live ? null : () => sender.nudge(-10000),
          ),
          GlassIconButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            primary: true,
            size: 68,
            onPressed: sender.togglePlay,
          ),
          GlassIconButton(
            icon: Icons.forward_10_rounded,
            tooltip: '۱۰ ثانیه جلو',
            size: 50,
            onPressed: live ? null : () => sender.nudge(10000),
          ),
          GlassIconButton(
            icon: Icons.forward_30_rounded,
            tooltip: '۳۰ ثانیه جلو',
            size: 50,
            onPressed: live ? null : () => sender.nudge(30000),
          ),
        ],
      ),
    );
  }
}

class _SubtitleCard extends StatelessWidget {
  const _SubtitleCard();

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final snap = sender.snapshot;
    final tracks = sender.subtitles;
    final active = tracks.where((t) => t.id == snap.subId).firstOrNull;

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.subtitles_rounded, size: 18, color: Sea.aqua),
              const SizedBox(width: 8),
              const Text(
                'زیرنویس',
                style: TextStyle(color: Sea.text, fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => showSubtitleSheet(context),
                child: const Row(
                  children: [
                    Text('تنظیمات', style: TextStyle(color: Sea.azure, fontSize: 12.5)),
                    Icon(Icons.chevron_left_rounded, color: Sea.azure, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            active?.label ?? 'خاموش',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active == null ? Sea.textFaint : Sea.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),

          // Sync: the control people actually reach for mid-film.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Sea.glassFill,
              borderRadius: BorderRadius.circular(Sea.radiusSm),
            ),
            child: Row(
              children: [
                GlassIconButton(
                  icon: Icons.remove_rounded,
                  size: 40,
                  onPressed: () => sender.nudgeSubDelay(-500),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'همگام‌سازی',
                        style: TextStyle(color: Sea.textFaint, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snap.subDelayMs == 0
                            ? 'دقیقاً هماهنگ'
                            : '${Fmt.offset(snap.subDelayMs)} ثانیه',
                        style: TextStyle(
                          color: snap.subDelayMs == 0 ? Sea.textDim : Sea.aqua,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                GlassIconButton(
                  icon: Icons.add_rounded,
                  size: 40,
                  onPressed: () => sender.nudgeSubDelay(500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'اگر زیرنویس زودتر از حرف‌ها می‌آید، عدد را زیاد کنید.',
            style: TextStyle(color: Sea.textFaint, fontSize: 11, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _ExtrasCard extends StatelessWidget {
  const _ExtrasCard();

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final snap = sender.snapshot;
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('سرعت پخش'),
          Row(
            children: [
              for (final s in speeds)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _Chip(
                      label: '${Fmt.digits(s == s.roundToDouble() ? '${s.toInt()}' : '$s')}×',
                      selected: (snap.rate - s).abs() < .01,
                      onTap: () => sender.setRate(s),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('اندازه‌ی تصویر'),
          Row(
            children: [
              for (final entry in const {
                VideoFit.contain: 'اصلی',
                VideoFit.cover: 'پرکردن',
                VideoFit.stretch: 'کشیده',
              }.entries)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _Chip(
                      label: entry.value,
                      selected: snap.fit == entry.key,
                      onTap: () => sender.setFit(entry.key),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('صدا'),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, color: Sea.textFaint, size: 18),
              Expanded(
                child: Slider(
                  value: snap.volume.clamp(0, 1),
                  onChanged: sender.setVolume,
                ),
              ),
              const Icon(Icons.volume_up_rounded, color: Sea.textFaint, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? Sea.azure.withValues(alpha: .22) : Sea.glassFill,
          border: Border.all(
            color: selected ? Sea.azure : Sea.glassStrokeSoft,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Sea.text : Sea.textDim,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Sea.azure.withValues(alpha: .12),
                border: Border.all(color: Sea.azure.withValues(alpha: .3)),
              ),
              child: const Icon(Icons.settings_remote_rounded, size: 36, color: Sea.azure),
            ),
            const SizedBox(height: 18),
            const Text(
              'هنوز فیلمی پخش نمی‌شود',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Sea.text),
            ),
            const SizedBox(height: 8),
            const Text(
              'از بخش «فیلم‌ها» یک ویدیو انتخاب کنید تا روی تلویزیون پخش شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Sea.textDim, fontSize: 13, height: 1.9),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}


/// Stands in for the scrubber on a live feed, where there is nothing to drag.
class _LiveBar extends StatelessWidget {
  const _LiveBar();

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Sea.danger,
              boxShadow: [BoxShadow(color: Sea.danger, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'پخش زنده — از لحظه‌ی حال',
              style: TextStyle(color: Sea.text, fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            Fmt.duration(sender.snapshot.position),
            style: const TextStyle(color: Sea.textFaint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
