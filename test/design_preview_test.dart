@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_cast/core/theme.dart';
import 'package:lan_cast/model/protocol.dart';
import 'package:lan_cast/subs/subtitle_view.dart';
import 'package:lan_cast/ui/common/glass.dart';

/// Renders the app's own widgets to PNG so the navy-glass styling can be
/// reviewed without a device. Run with:
///
///   flutter test test/design_preview_test.dart --update-goldens
///
/// The images land in test/preview/.
void main() {
  Widget frame(Widget child, {Size size = const Size(420, 900)}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Sea.theme(),
        locale: const Locale('fa'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fa'), Locale('en')],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: Sea.abyss,
            body: GlassBackdrop(child: SafeArea(child: child)),
          ),
        ),
      );

  Future<void> shoot(WidgetTester tester, Widget child, String name, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(child, size: size));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/$name.png'),
    );
  }

  testWidgets('phone — remote panel', (tester) async {
    await shoot(tester, const _RemotePreview(), 'phone_remote', const Size(420, 900));
  });

  testWidgets('phone — subtitle settings', (tester) async {
    await shoot(tester, const _SubtitlePreview(), 'phone_subtitles', const Size(420, 900));
  });

  testWidgets('tv — pairing screen', (tester) async {
    await shoot(tester, const _TvPairPreview(), 'tv_pairing', const Size(1280, 720));
  });

  testWidgets('tv — player OSD', (tester) async {
    await shoot(tester, const _TvOsdPreview(), 'tv_osd', const Size(1280, 720));
  });

  tearDownAll(() {
    final dir = Directory('test/preview');
    if (dir.existsSync()) {
      // ignore: avoid_print
      print('preview images: ${dir.listSync().map((e) => e.path).join(', ')}');
    }
  });
}

// --- stand-ins that mirror the real screens without needing a live server ---

class _RemotePreview extends StatelessWidget {
  const _RemotePreview();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Row(
          children: [
            ShaderMask(
              shaderCallback: (r) => Sea.accentGradient.createShader(r),
              child: const Text(
                'LanCast',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            const Flexible(
              child: StatusPill(
                label: 'متصل به Android TV',
                color: Sea.ok,
                icon: Icons.cast_connected_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GlassPanel(
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
                child: const Icon(Icons.movie_creation_rounded, color: Sea.abyss),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dune Part Two 2024 1080p',
                      style: TextStyle(
                        color: Sea.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'روی Android TV',
                      style: TextStyle(color: Sea.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Slider(value: .38, onChanged: (_) {}),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Text(
                      '۵۴:۱۲',
                      style: TextStyle(
                        color: Sea.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Spacer(),
                    Text('۲:۲۶:۰۰', style: TextStyle(color: Sea.textFaint, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GlassIconButton(icon: Icons.stop_rounded, size: 44, onPressed: () {}),
              GlassIconButton(icon: Icons.replay_30_rounded, size: 50, onPressed: () {}),
              GlassIconButton(icon: Icons.replay_10_rounded, size: 50, onPressed: () {}),
              GlassIconButton(
                icon: Icons.pause_rounded,
                primary: true,
                size: 68,
                onPressed: () {},
              ),
              GlassIconButton(icon: Icons.forward_10_rounded, size: 50, onPressed: () {}),
              GlassIconButton(icon: Icons.forward_30_rounded, size: 50, onPressed: () {}),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.subtitles_rounded, size: 18, color: Sea.aqua),
                  SizedBox(width: 8),
                  Text(
                    'زیرنویس',
                    style: TextStyle(
                      color: Sea.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Spacer(),
                  Text('تنظیمات', style: TextStyle(color: Sea.azure, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Dune.Part.Two.Farsi',
                style: TextStyle(color: Sea.text, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Sea.glassFill,
                  borderRadius: BorderRadius.circular(Sea.radiusSm),
                ),
                child: Row(
                  children: [
                    GlassIconButton(icon: Icons.remove_rounded, size: 40, onPressed: () {}),
                    const Expanded(
                      child: Column(
                        children: [
                          Text('همگام‌سازی',
                              style: TextStyle(color: Sea.textFaint, fontSize: 11)),
                          SizedBox(height: 2),
                          Text(
                            '+۱٫۵ ثانیه',
                            style: TextStyle(
                              color: Sea.aqua,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GlassIconButton(icon: Icons.add_rounded, size: 40, onPressed: () {}),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview();

  @override
  Widget build(BuildContext context) {
    const style = SubtitleStyleSpec(sizePx: 40, color: 0xFFFFE58A, backdrop: .5, bottomPct: 10);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionLabel('انتخاب زیرنویس'),
        for (final entry in const {'خاموش': false, 'Farsi.srt': true, 'English.srt': false}.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Sea.radiusSm),
                color: entry.value ? Sea.azure.withValues(alpha: .2) : Sea.glassFill,
                border: Border.all(color: entry.value ? Sea.azure : Sea.glassStrokeSoft),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.closed_caption_rounded,
                    size: 18,
                    color: entry.value ? Sea.azure : Sea.textFaint,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        color: entry.value ? Sea.text : Sea.textDim,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (entry.value)
                    const Icon(Icons.check_circle_rounded, size: 18, color: Sea.azure),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        const SectionLabel('همگام‌سازی دقیق'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Sea.radius),
            color: Sea.glassFill,
            border: Border.all(color: Sea.glassStrokeSoft),
          ),
          child: const Column(
            children: [
              Text(
                '+۱٫۵ ثانیه',
                style: TextStyle(color: Sea.aqua, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'زیرنویس دیرتر از صدا نشان داده می‌شود',
                style: TextStyle(color: Sea.textFaint, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('ظاهر زیرنویس'),
        Container(
          height: 120,
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Sea.radiusSm),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0E1B3D), Color(0xFF05070F)],
            ),
            border: Border.all(color: Sea.glassStrokeSoft),
          ),
          child: const SubtitleOverlay(
            text: 'نمونه‌ی زیرنویس روی تلویزیون',
            style: style,
            scale: .4,
          ),
        ),
      ],
    );
  }
}

class _TvPairPreview extends StatelessWidget {
  const _TvPairPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: GlassPanel(
          strong: true,
          glow: Sea.azure,
          padding: const EdgeInsets.all(38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (r) => Sea.accentGradient.createShader(r),
                    child: const Text(
                      'LanCast',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const StatusPill(label: 'آماده', color: Sea.textDim, icon: Icons.wifi_rounded),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'اپ را روی گوشی باز کنید؛ هر دو باید به یک وای‌فای وصل باشند.',
                style: TextStyle(color: Sea.textDim, fontSize: 19, height: 1.9),
              ),
              const SizedBox(height: 28),
              const SectionLabel('گوشی‌های پیداشده'),
              GlassPanel(
                radius: Sea.radiusSm,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: const Row(
                  children: [
                    Icon(Icons.smartphone_rounded, color: Sea.azure),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Samsung Galaxy S23',
                            style: TextStyle(
                              color: Sea.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '192.168.1.42:8787',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(color: Sea.textFaint, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.link_rounded, color: Sea.ok),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'آی‌پی این تلویزیون: 192.168.1.77',
                      style: TextStyle(color: Sea.textFaint, fontSize: 13),
                    ),
                  ),
                  GlassButton(
                    label: 'این دستگاه، فرستنده باشد',
                    icon: Icons.smartphone_rounded,
                    filled: false,
                    compact: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvOsdPreview extends StatelessWidget {
  const _TvOsdPreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Dune Part Two 2024 1080p',
                    style: TextStyle(
                      color: Sea.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                StatusPill(
                  label: 'کنترل از گوشی',
                  color: Sea.ok,
                  icon: Icons.settings_remote_rounded,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        const SubtitleOverlay(
          text: 'زیرنویس فارسی روی تلویزیون نمایش داده می‌شود',
          style: SubtitleStyleSpec(sizePx: 34),
          scale: .66,
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: GlassPanel(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      '۵۴:۱۲',
                      style: TextStyle(
                        color: Sea.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: const LinearProgressIndicator(
                          value: .38,
                          minHeight: 6,
                          backgroundColor: Color(0x33FFFFFF),
                          valueColor: AlwaysStoppedAnimation(Sea.azure),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      '۲:۲۶:۰۰',
                      style: TextStyle(color: Sea.textFaint, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlassIconButton(icon: Icons.replay_10_rounded, size: 52, onPressed: () {}),
                    const SizedBox(width: 18),
                    GlassIconButton(
                      icon: Icons.pause_rounded,
                      primary: true,
                      size: 68,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 18),
                    GlassIconButton(icon: Icons.forward_10_rounded, size: 52, onPressed: () {}),
                    const SizedBox(width: 34),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Sea.glassFill,
                        borderRadius: BorderRadius.circular(Sea.radiusSm),
                        border: Border.all(color: Sea.glassStrokeSoft),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.subtitles_rounded, size: 17, color: Sea.aqua),
                          SizedBox(width: 8),
                          Text(
                            '+۱٫۵ ثانیه',
                            style: TextStyle(
                              color: Sea.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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
