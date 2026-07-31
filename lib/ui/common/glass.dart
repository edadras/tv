import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Frosted navy panel. The workhorse of the whole UI.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Sea.radius,
    this.blur = 20,
    this.strong = false,
    this.border = true,
    this.glow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final bool strong;
  final bool border;
  final Color? glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: strong
              ? const [Color(0x2BFFFFFF), Color(0x12FFFFFF)]
              : const [Color(0x1AFFFFFF), Color(0x0AFFFFFF)],
        ),
        border: border
            ? Border.all(
                color: strong ? Sea.glassStroke : Sea.glassStrokeSoft,
                width: 1,
              )
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    surface = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: Perf.blur(blur),
          sigmaY: Perf.blur(blur),
        ),
        child: surface,
      ),
    );

    if (glow != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(color: glow!.withValues(alpha: .28), blurRadius: 34, spreadRadius: -6),
          ],
        ),
        child: surface,
      );
    }

    if (onTap != null) {
      surface = Material(
        color: Colors.transparent,
        borderRadius: shape,
        child: InkWell(borderRadius: shape, onTap: onTap, child: surface),
      );
    }
    return surface;
  }
}

/// Page background: navy gradient plus two soft light blooms.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Sea.backdrop),
      child: Stack(
        children: [
          const Positioned(top: -140, right: -90, child: _Bloom(color: Sea.azure, size: 340)),
          const Positioned(bottom: -160, left: -110, child: _Bloom(color: Sea.violet, size: 380)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Bloom extends StatelessWidget {
  const _Bloom({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: .22), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// Primary action button with the azure→aqua gradient fill.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = true,
    this.compact = false,
    this.autofocus = false,
    this.tone,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool compact;
  final bool autofocus;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = tone ?? Sea.azure;
    final radius = BorderRadius.circular(Sea.radiusSm);
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          autofocus: autofocus,
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: filled
                  ? LinearGradient(colors: [accent, accent == Sea.azure ? Sea.aqua : accent])
                  : null,
              color: filled ? null : Sea.glassFill,
              border: Border.all(
                color: filled ? Colors.transparent : Sea.glassStroke,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
                vertical: compact ? 9 : 13,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: compact ? 17 : 19, color: filled ? Sea.abyss : Sea.text),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: filled ? Sea.abyss : Sea.text,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 13 : 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button used across the transport bars.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 48,
    this.iconSize,
    this.primary = false,
    this.tooltip,
    this.autofocus = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double? iconSize;
  final bool primary;
  final String? tooltip;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    Widget button = Opacity(
      opacity: onPressed == null ? .4 : 1,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          autofocus: autofocus,
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: primary ? Sea.accentGradient : null,
              color: primary ? null : Sea.glassFill,
              border: Border.all(color: primary ? Colors.transparent : Sea.glassStroke),
              boxShadow: primary
                  ? const [BoxShadow(color: Color(0x554EA8FF), blurRadius: 22, spreadRadius: -4)]
                  : null,
            ),
            child: Icon(
              icon,
              size: iconSize ?? size * .46,
              color: primary ? Sea.abyss : Sea.text,
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// Small status pill (connected / disconnected / mode).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading used inside settings sheets.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Sea.textDim,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
