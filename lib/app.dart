import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/device.dart';
import 'core/prefs.dart';
import 'core/theme.dart';
import 'state/receiver_controller.dart';
import 'state/scope.dart';
import 'state/sender_controller.dart';
import 'ui/mobile/sender_home.dart';
import 'ui/tv/tv_home.dart';

class LanCastApp extends StatefulWidget {
  const LanCastApp({super.key, required this.facts});

  final DeviceFacts facts;

  @override
  State<LanCastApp> createState() => _LanCastAppState();
}

class _LanCastAppState extends State<LanCastApp> {
  late AppRole _role;
  SenderController? _sender;
  ReceiverController? _receiver;

  @override
  void initState() {
    super.initState();
    _role = Prefs.instance.roleOverride ??
        (widget.facts.isTelevision ? AppRole.receiver : AppRole.sender);
    _buildRole();
  }

  void _buildRole() {
    if (_role == AppRole.sender) {
      _sender = SenderController(widget.facts)..start();
    } else {
      _receiver = ReceiverController(widget.facts);
      final last = Prefs.instance.lastHost;
      if (last != null) _receiver!.connect(last);
    }
  }

  /// Lets a phone act as a screen, or a TV box act as the sender — handy when
  /// the automatic detection guesses wrong on an odd Android box.
  Future<void> _switchRole(AppRole role) async {
    if (role == _role) return;
    await Prefs.instance.setRoleOverride(role);
    _sender?.dispose();
    _receiver?.dispose();
    _sender = null;
    _receiver = null;
    setState(() {
      _role = role;
      _buildRole();
    });
  }

  @override
  void dispose() {
    _sender?.dispose();
    _receiver?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = _role == AppRole.sender
        ? SenderScope(
            controller: _sender!,
            child: SenderHome(onSwitchRole: () => _switchRole(AppRole.receiver)),
          )
        : ReceiverScope(
            controller: _receiver!,
            child: TvHome(onSwitchRole: () => _switchRole(AppRole.sender)),
          );

    return MaterialApp(
      title: 'LanCast',
      debugShowCheckedModeBanner: false,
      theme: Sea.theme(),
      locale: const Locale('fa'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fa'), Locale('en')],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery.withNoTextScaling(child: child ?? const SizedBox()),
      ),
      home: home,
    );
  }
}
