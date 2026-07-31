import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Navy-glass design tokens shared by the phone UI, the TV UI and the
/// browser player (the CSS in `lib/net/web_assets.dart` mirrors these values).
class Sea {
  const Sea._();

  // Base "سرمه‌ای" (navy) ramp.
  static const abyss = Color(0xFF040814);
  static const navy = Color(0xFF071026);
  static const navyHigh = Color(0xFF0C1A3C);
  static const navySoft = Color(0xFF12224A);

  // Accents.
  static const azure = Color(0xFF4EA8FF);
  static const aqua = Color(0xFF6EE7F9);
  static const violet = Color(0xFF8B7BFF);
  static const danger = Color(0xFFFF6B7A);
  static const ok = Color(0xFF52E5A3);

  // Text.
  static const text = Color(0xFFEAF1FF);
  static const textDim = Color(0xFF9FB2D8);
  static const textFaint = Color(0xFF6B7FA8);

  // Glass surfaces.
  static const glassFill = Color(0x14FFFFFF);
  static const glassFillStrong = Color(0x1FFFFFFF);
  static const glassStroke = Color(0x26FFFFFF);
  static const glassStrokeSoft = Color(0x14FFFFFF);

  static const radius = 22.0;
  static const radiusSm = 14.0;

  /// Full-screen background used behind every page.
  static const backdrop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A1330), Color(0xFF060C1F), Color(0xFF040810)],
  );

  static const accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [azure, aqua],
  );

  /// Bundled with the app so Persian looks right on every device, including
  /// TV boxes that ship without an Arabic-script font.
  static const fontFamily = 'Vazirmatn';

  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: azure,
      secondary: aqua,
      surface: navy,
      error: danger,
      onPrimary: abyss,
      onSecondary: abyss,
      onSurface: text,
    );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: abyss,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamily: fontFamily,
        fontFamilyFallback: const ['Noto Naskh Arabic', 'Roboto', 'Arial'],
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: azure,
        inactiveTrackColor: const Color(0x33FFFFFF),
        thumbColor: Colors.white,
        overlayColor: const Color(0x334EA8FF),
        trackHeight: 5,
      ),
      dividerColor: glassStrokeSoft,
      iconTheme: const IconThemeData(color: text),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: navyHigh,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static const systemChrome = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF040814),
    systemNavigationBarIconBrightness: Brightness.light,
  );
}

/// Blur is cheap on phones and expensive on low-end TV boxes, so every glass
/// surface asks this switch how much it is allowed to spend.
class Perf {
  static bool lite = false;

  static double blur(double wanted) => lite ? 0 : wanted;
}
