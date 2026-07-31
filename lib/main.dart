import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/device.dart';
import 'core/prefs.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();

  final facts = await DeviceFacts.load();
  // Cheap TV boxes pay a real frame cost for backdrop blur.
  Perf.lite = facts.isLowEnd;

  SystemChrome.setSystemUIOverlayStyle(Sea.systemChrome);
  if (!facts.isTelevision) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  runApp(LanCastApp(facts: facts));
}
