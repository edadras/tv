import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../state/scope.dart';
import '../../state/sender_controller.dart';
import '../common/glass.dart';

/// The pairing card: QR + address for the TV browser, the list of attached
/// screens, and the sideload link for the native TV app.
Future<bool?> showConnectSheet(
  BuildContext context,
  VoidCallback? onSwitchRole, {
  bool askToContinue = false,
}) {
  final controller = SenderScope.read(context);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    builder: (_) => SenderScope(
      controller: controller,
      child: _ConnectSheet(onSwitchRole: onSwitchRole, askToContinue: askToContinue),
    ),
  );
}

class _ConnectSheet extends StatelessWidget {
  const _ConnectSheet({required this.onSwitchRole, required this.askToContinue});

  final VoidCallback? onSwitchRole;
  final bool askToContinue;

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);
    final url = sender.shareUrl;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: GlassPanel(
        strong: true,
        glow: Sea.azure,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Sea.glassStroke,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Text(
                'اتصال به تلویزیون',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Sea.text),
              ),
              const SizedBox(height: 6),
              const Text(
                'یکی از این دو راه را انتخاب کنید',
                style: TextStyle(color: Sea.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 18),

              if (sender.error != null)
                _Warning(text: sender.error!)
              else if (url.isEmpty)
                const _Warning(text: 'در حال آماده‌سازی شبکه…')
              else ...[
                _Numbered(
                  number: '۱',
                  title: 'بدون نصب: مرورگر تلویزیون',
                  body: 'این آدرس را در مرورگر تلویزیون تایپ کنید. صفحه‌ی پخش باز می‌شود و '
                      'کنترلش با همین گوشی است.',
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 148,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Sea.navy,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Sea.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _AddressChip(url: url),
                const SizedBox(height: 20),
                _Numbered(
                  number: '۲',
                  title: 'با نصب: اپ روی تلویزیون',
                  body: 'در همان صفحه‌ی مرورگر، دکمه‌ی «دانلود فایل نصبی» را بزنید تا همین اپ '
                      'روی تلویزیون نصب شود. بعد از آن تلویزیون خودش گوشی را پیدا می‌کند.',
                ),
              ],

              const SizedBox(height: 18),
              _Receivers(sender: sender),

              if (onSwitchRole != null) ...[
                const SizedBox(height: 14),
                GlassButton(
                  label: 'این دستگاه، پخش‌کننده باشد',
                  icon: Icons.tv_rounded,
                  filled: false,
                  compact: true,
                  onPressed: () {
                    Navigator.of(context).pop(false);
                    onSwitchRole!();
                  },
                ),
              ],

              if (askToContinue) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: 'بعداً وصل می‌شوم',
                        filled: false,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlassButton(
                        label: 'باشه',
                        icon: Icons.check_rounded,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('آدرس کپی شد')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Sea.azure.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Sea.azure.withValues(alpha: .4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy_rounded, size: 15, color: Sea.azure),
            const SizedBox(width: 8),
            Text(
              url.replaceFirst('http://', ''),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Sea.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered({required this.number, required this.title, required this.body});

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Sea.accentGradient),
          child: Text(
            number,
            style: const TextStyle(
              color: Sea.abyss,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Sea.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(color: Sea.textDim, fontSize: 12.5, height: 1.8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Receivers extends StatelessWidget {
  const _Receivers({required this.sender});

  final SenderController sender;

  @override
  Widget build(BuildContext context) {
    final peers = sender.receivers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('صفحه‌های متصل'),
        if (peers.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Sea.glassStrokeSoft),
            ),
            child: const Text(
              'هنوز چیزی وصل نشده',
              style: TextStyle(color: Sea.textFaint, fontSize: 12.5),
            ),
          )
        else
          for (final peer in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    peer.kind == 'tv' ? Icons.tv_rounded : Icons.public_rounded,
                    size: 18,
                    color: Sea.ok,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      peer.name,
                      style: const TextStyle(color: Sea.text, fontSize: 13.5),
                    ),
                  ),
                  StatusPill(
                    label: peer.kind == 'tv' ? 'اپ تلویزیون' : 'مرورگر',
                    color: Sea.ok,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Sea.danger.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Sea.danger.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering_error_rounded, color: Sea.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Sea.text, fontSize: 13, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}
