import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../media/library.dart';
import '../../model/protocol.dart';
import '../../state/scope.dart';
import '../common/glass.dart';

/// Track selection, fine sync and appearance — all live, all applied on the
/// TV the moment you touch them.
Future<void> showSubtitleSheet(BuildContext context) {
  final controller = SenderScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .55),
    builder: (_) => SenderScope(
      controller: controller,
      child: const _SubtitleSheet(),
    ),
  );
}

class _SubtitleSheet extends StatelessWidget {
  const _SubtitleSheet();

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final snap = sender.snapshot;
    final style = sender.style;
    final tracks = sender.subtitles;

    return DraggableScrollableSheet(
      initialChildSize: .82,
      minChildSize: .5,
      maxChildSize: .95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlassPanel(
          strong: true,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Sea.glassStroke,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),

              const SectionLabel('انتخاب زیرنویس'),
              _TrackTile(
                label: 'خاموش',
                selected: snap.subId == null,
                icon: Icons.subtitles_off_rounded,
                onTap: () => sender.selectSubtitle(null),
              ),
              for (final t in tracks)
                _TrackTile(
                  label: Fmt.title(t.label),
                  selected: snap.subId == t.id,
                  icon: Icons.closed_caption_rounded,
                  onTap: () => sender.selectSubtitle(t.id),
                ),
              const SizedBox(height: 10),
              GlassButton(
                label: 'افزودن فایل زیرنویس',
                icon: Icons.add_rounded,
                filled: false,
                compact: true,
                onPressed: () => _pickSubtitle(context),
              ),

              const SizedBox(height: 22),
              const SectionLabel('همگام‌سازی دقیق'),
              _SyncPad(delayMs: snap.subDelayMs),

              const SizedBox(height: 22),
              const SectionLabel('ظاهر زیرنویس'),
              _Preview(style: style),
              const SizedBox(height: 14),
              _StyleSlider(
                label: 'اندازه‌ی متن',
                value: style.sizePx,
                min: 18,
                max: 68,
                display: Fmt.digits(style.sizePx.round().toString()),
                onChanged: (v) => sender.setStyle(style.copyWith(sizePx: v)),
              ),
              _StyleSlider(
                label: 'فاصله از پایین',
                value: style.bottomPct,
                min: 0,
                max: 25,
                display: '${Fmt.digits(style.bottomPct.round().toString())}٪',
                onChanged: (v) => sender.setStyle(style.copyWith(bottomPct: v)),
              ),
              _StyleSlider(
                label: 'تیرگی پس‌زمینه',
                value: style.backdrop,
                min: 0,
                max: 1,
                display: '${Fmt.digits((style.backdrop * 100).round().toString())}٪',
                onChanged: (v) => sender.setStyle(style.copyWith(backdrop: v)),
              ),
              const SizedBox(height: 8),
              const SectionLabel('رنگ متن'),
              _ColorRow(
                selected: style.color,
                onPick: (c) => sender.setStyle(style.copyWith(color: c)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Toggle(
                      label: 'حاشیه‌ی تیره',
                      value: style.outline,
                      onChanged: (v) => sender.setStyle(style.copyWith(outline: v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Toggle(
                      label: 'متن ضخیم',
                      value: style.bold,
                      onChanged: (v) => sender.setStyle(style.copyWith(bold: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GlassButton(
                label: 'بستن',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSubtitle(BuildContext context) async {
    final sender = SenderScope.read(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!isSubtitleFile(path)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فقط SRT، VTT یا ASS پشتیبانی می‌شود')),
        );
      }
      return;
    }
    await sender.addSubtitle(path);
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Sea.radiusSm),
            color: selected ? Sea.azure.withValues(alpha: .2) : Sea.glassFill,
            border: Border.all(color: selected ? Sea.azure : Sea.glassStrokeSoft),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? Sea.azure : Sea.textFaint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Sea.text : Sea.textDim,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: Sea.azure),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coarse and fine sync in one block: tap for ±0.1s, hold the big buttons for
/// ±0.5s, and reset when you have gone too far.
class _SyncPad extends StatelessWidget {
  const _SyncPad({required this.delayMs});

  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Sea.radius),
        color: Sea.glassFill,
        border: Border.all(color: Sea.glassStrokeSoft),
      ),
      child: Column(
        children: [
          Text(
            delayMs == 0 ? 'بدون اختلاف' : '${Fmt.offset(delayMs)} ثانیه',
            style: TextStyle(
              color: delayMs == 0 ? Sea.textDim : Sea.aqua,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            delayMs > 0
                ? 'زیرنویس دیرتر از صدا نشان داده می‌شود'
                : (delayMs < 0
                    ? 'زیرنویس زودتر از صدا نشان داده می‌شود'
                    : 'زیرنویس با صدا هماهنگ است'),
            style: const TextStyle(color: Sea.textFaint, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Step(label: '−۱ ث', onTap: () => sender.nudgeSubDelay(-1000)),
              _Step(label: '−۰٫۱', onTap: () => sender.nudgeSubDelay(-100)),
              GlassIconButton(
                icon: Icons.restart_alt_rounded,
                size: 42,
                tooltip: 'صفر کردن',
                onPressed: () => sender.setSubDelay(0),
              ),
              _Step(label: '+۰٫۱', onTap: () => sender.nudgeSubDelay(100)),
              _Step(label: '+۱ ث', onTap: () => sender.nudgeSubDelay(1000)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Sea.glassFillStrong,
          border: Border.all(color: Sea.glassStrokeSoft),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Sea.text, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.style});

  final SubtitleStyleSpec style;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.only(bottom: 96 * (style.bottomPct / 100)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Sea.radiusSm),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1B3D), Color(0xFF05070F)],
        ),
        border: Border.all(color: Sea.glassStrokeSoft),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: style.backdrop),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          'نمونه‌ی زیرنویس روی تلویزیون',
          style: TextStyle(
            // The spec is sized for a 1080p screen; scale it into the preview.
            fontSize: style.sizePx * .38,
            color: Color(style.color),
            fontWeight: style.bold ? FontWeight.w700 : FontWeight.w500,
            shadows: style.outline
                ? const [Shadow(blurRadius: 5, color: Colors.black)]
                : null,
          ),
        ),
      ),
    );
  }
}

class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Sea.textDim, fontSize: 12.5)),
            const Spacer(),
            Text(
              display,
              style: const TextStyle(
                color: Sea.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  static const _colors = [
    0xFFFFFFFF, // white
    0xFFFFE58A, // warm cream, easiest on the eyes at night
    0xFF6EE7F9, // aqua
    0xFF9BE49B, // green
    0xFFFFB3C7, // pink
    0xFFFFFF66, // classic yellow
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in _colors)
          Expanded(
            child: GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                height: 38,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Color(c),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected == c ? Sea.azure : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: selected == c
                    ? const Icon(Icons.check_rounded, size: 17, color: Sea.abyss)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Sea.radiusSm),
          color: value ? Sea.azure.withValues(alpha: .18) : Sea.glassFill,
          border: Border.all(color: value ? Sea.azure : Sea.glassStrokeSoft),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: value ? Sea.azure : Sea.textFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: value ? Sea.text : Sea.textDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
