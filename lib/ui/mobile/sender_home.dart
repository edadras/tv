import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/scope.dart';
import '../common/glass.dart';
import 'connect_sheet.dart';
import 'library_tab.dart';
import 'remote_tab.dart';

/// The phone shell: browse on one side, remote on the other.
class SenderHome extends StatefulWidget {
  const SenderHome({super.key, required this.onSwitchRole});

  final VoidCallback onSwitchRole;

  @override
  State<SenderHome> createState() => _SenderHomeState();
}

class _SenderHomeState extends State<SenderHome> {
  int _tab = 0;

  void _goToRemote() => setState(() => _tab = 1);

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final connected = sender.hasReceiver;

    return Scaffold(
      backgroundColor: Sea.abyss,
      body: GlassBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const _Wordmark(),
                    const Spacer(),
                    // A long TV name must shrink the pill, not push the
                    // buttons off the edge of a narrow phone.
                    Flexible(
                      child: StatusPill(
                        label: connected
                            ? 'متصل به ${sender.receivers.first.name}'
                            : (sender.isHosting ? 'آماده‌ی اتصال' : 'خاموش'),
                        color: connected ? Sea.ok : Sea.textDim,
                        icon: connected ? Icons.cast_connected_rounded : Icons.cast_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: Icons.qr_code_rounded,
                      size: 40,
                      tooltip: 'اتصال تلویزیون',
                      onPressed: () => showConnectSheet(context, widget.onSwitchRole),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    LibraryTab(onCastStarted: _goToRemote),
                    const RemoteTab(),
                  ],
                ),
              ),
              _NavBar(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
                playing: sender.snapshot.playing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => Sea.accentGradient.createShader(r),
      child: const Text(
        'LanCast',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -.4,
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onChanged, required this.playing});

  final int index;
  final ValueChanged<int> onChanged;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: GlassPanel(
        padding: const EdgeInsets.all(6),
        radius: 999,
        strong: true,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.video_library_rounded,
              label: 'فیلم‌ها',
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
            _NavItem(
              icon: playing ? Icons.graphic_eq_rounded : Icons.settings_remote_rounded,
              label: 'کنترل',
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected ? Sea.accentGradient : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: selected ? Sea.abyss : Sea.textDim),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Sea.abyss : Sea.textDim,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
