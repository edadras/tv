import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../net/discovery.dart';
import '../../net/lan.dart';
import '../../net/receiver_link.dart';
import '../../state/scope.dart';
import '../common/glass.dart';
import 'tv_player.dart';

/// TV entry point: find the phone, then get out of the way.
class TvHome extends StatefulWidget {
  const TvHome({super.key, required this.onSwitchRole});

  final VoidCallback onSwitchRole;

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  Discovery? _discovery;
  StreamSubscription<List<DiscoveredHost>>? _hostsSub;
  Timer? _seekTimer;
  List<DiscoveredHost> _hosts = const [];
  List<String> _selfAddresses = const [];
  final _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startDiscovery();
    Lan.addresses().then((a) {
      if (mounted) setState(() => _selfAddresses = a);
    });
  }

  Future<void> _startDiscovery() async {
    final d = await Discovery.bind();
    if (!mounted) {
      d?.dispose();
      return;
    }
    _discovery = d;
    _hostsSub = d?.hosts.listen((hosts) {
      if (!mounted) return;
      setState(() => _hosts = hosts);
      // Exactly one phone on the network is the common case: just attach.
      final receiver = ReceiverScope.read(context);
      if (hosts.length == 1 && receiver.status != LinkStatus.connected) {
        receiver.connect(hosts.first.url);
      }
    });
    unawaited(d?.seek());
    _seekTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final receiver = ReceiverScope.read(context);
      if (receiver.status != LinkStatus.connected) unawaited(_discovery?.seek());
    });
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    _hostsSub?.cancel();
    _discovery?.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receiver = ReceiverScope.of(context);

    // Playing beats everything else on screen.
    if (receiver.media != null) return const TvPlayer();

    return Scaffold(
      backgroundColor: Sea.abyss,
      body: GlassBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
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
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        const Spacer(),
                        StatusPill(
                          label: switch (receiver.status) {
                            LinkStatus.connected => 'متصل',
                            LinkStatus.connecting => 'در حال اتصال',
                            LinkStatus.retrying => 'تلاش دوباره',
                            LinkStatus.failed => 'اتصال برقرار نشد',
                            LinkStatus.idle => 'آماده',
                          },
                          color: receiver.status == LinkStatus.connected ? Sea.ok : Sea.textDim,
                          icon: Icons.wifi_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      receiver.status == LinkStatus.connected
                          ? 'وصل شد. حالا از گوشی یک فیلم انتخاب کنید.'
                          : 'اپ را روی گوشی باز کنید؛ هر دو باید به یک وای‌فای وصل باشند.',
                      style: const TextStyle(color: Sea.textDim, fontSize: 19, height: 1.9),
                    ),
                    const SizedBox(height: 28),

                    if (receiver.status == LinkStatus.connected)
                      const _WaitingIndicator()
                    else ...[
                      const SectionLabel('گوشی‌های پیداشده'),
                      if (_hosts.isEmpty)
                        const _Searching()
                      else
                        for (final h in _hosts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassPanel(
                              radius: Sea.radiusSm,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              onTap: () => receiver.connect(h.url),
                              child: Row(
                                children: [
                                  const Icon(Icons.smartphone_rounded, color: Sea.azure),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          h.name,
                                          style: const TextStyle(
                                            color: Sea.text,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          h.url.replaceFirst('http://', ''),
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(
                                            color: Sea.textFaint,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.link_rounded, color: Sea.ok),
                                ],
                              ),
                            ),
                          ),
                      const SizedBox(height: 20),
                      const SectionLabel('یا آدرس را دستی وارد کنید'),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _manual,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(color: Sea.text, fontSize: 18),
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                hintText: '192.168.1.5:8787',
                                hintStyle: const TextStyle(color: Sea.textFaint),
                                filled: true,
                                fillColor: Sea.glassFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Sea.radiusSm),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (v) {
                                if (v.trim().isNotEmpty) receiver.connect(v.trim());
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          GlassButton(
                            label: 'اتصال',
                            icon: Icons.login_rounded,
                            onPressed: () {
                              final v = _manual.text.trim();
                              if (v.isNotEmpty) receiver.connect(v);
                            },
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selfAddresses.isEmpty
                                ? 'این تلویزیون هنوز آی‌پی شبکه ندارد'
                                : 'آی‌پی این تلویزیون: ${_selfAddresses.first}',
                            style: const TextStyle(color: Sea.textFaint, fontSize: 13),
                          ),
                        ),
                        GlassButton(
                          label: 'این دستگاه، فرستنده باشد',
                          icon: Icons.smartphone_rounded,
                          filled: false,
                          compact: true,
                          onPressed: widget.onSwitchRole,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Sea.radiusSm),
        border: Border.all(color: Sea.glassStrokeSoft),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Sea.azure),
          ),
          SizedBox(width: 14),
          Text(
            'در حال جست‌وجوی گوشی در شبکه…',
            style: TextStyle(color: Sea.textDim, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _WaitingIndicator extends StatelessWidget {
  const _WaitingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Sea.radius),
        color: Sea.ok.withValues(alpha: .08),
        border: Border.all(color: Sea.ok.withValues(alpha: .3)),
      ),
      child: const Column(
        children: [
          Icon(Icons.cast_connected_rounded, size: 44, color: Sea.ok),
          SizedBox(height: 14),
          Text(
            'منتظر فیلم از گوشی',
            style: TextStyle(color: Sea.text, fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
