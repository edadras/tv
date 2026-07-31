import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../model/protocol.dart';

/// Draws one subtitle cue over the video, styled by [SubtitleStyleSpec].
///
/// Rendering the cues ourselves (instead of handing the file to the platform
/// player) is what makes the sync offset exact and instant: shifting the
/// lookup time is the entire implementation.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.text,
    required this.style,
    this.scale = 1,
  });

  final String? text;
  final SubtitleStyleSpec style;

  /// Multiplier applied on top of the 1080p reference size.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final value = text;
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    final size = style.sizePx * scale;
    final color = Color(style.color);
    final textStyle = TextStyle(
      fontSize: size,
      height: 1.28,
      color: color,
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w500,
      shadows: style.outline
          ? [
              Shadow(blurRadius: size * .18, color: Colors.black.withValues(alpha: .95)),
              const Shadow(offset: Offset(0, 1.5), blurRadius: 3, color: Colors.black),
            ]
          : null,
      fontFamily: Sea.fontFamily,
      fontFamilyFallback: const ['Noto Naskh Arabic', 'Roboto'],
    );

    return LayoutBuilder(
      builder: (context, c) {
        // The overlay is normally laid over the video and therefore bounded,
        // but it must not produce NaN padding if it is ever dropped into a
        // scrolling or otherwise unbounded parent.
        final height = c.maxHeight.isFinite ? c.maxHeight : size * 8;
        final width = c.maxWidth.isFinite ? c.maxWidth : size * 20;
        return Padding(
          padding: EdgeInsets.only(
            bottom: height * (style.bottomPct / 100),
            left: width * .05,
            right: width * .05,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: style.backdrop.clamp(0, 1)),
                borderRadius: BorderRadius.circular(size * .22),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size * .5, vertical: size * .22),
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: textStyle,
                  // Persian/Arabic and Latin cues both read correctly when the
                  // direction follows the text itself.
                  textDirection: _directionOf(value),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static TextDirection _directionOf(String s) {
    for (final r in s.runes) {
      // Arabic, Persian, Hebrew blocks.
      if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF)) {
        return TextDirection.rtl;
      }
      if ((r >= 0x0041 && r <= 0x005A) || (r >= 0x0061 && r <= 0x007A)) {
        return TextDirection.ltr;
      }
    }
    return TextDirection.ltr;
  }
}
