import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../media/url_source.dart';
import '../../model/protocol.dart';
import '../../state/scope.dart';
import '../common/glass.dart';

/// Paste a link and send it to the TV.
///
/// Returns true when something was cast, so the caller can jump to the remote.
Future<bool?> showLinkSheet(BuildContext context) {
  final controller = SenderScope.read(context);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    builder: (_) => SenderScope(controller: controller, child: const _LinkSheet()),
  );
}

class _LinkSheet extends StatefulWidget {
  const _LinkSheet();

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _field = TextEditingController();
  UrlSource? _parsed;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _recent = Prefs.instance.recentLinks;
    _field.addListener(_reparse);
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// If there is already a video link on the clipboard, offer it — that is
  /// almost always why someone opened this sheet.
  Future<void> _prefillFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    if (_field.text.isNotEmpty) return;
    if (UrlSource.parse(text) == null) return;
    _field.text = text;
    _field.selection = TextSelection.collapsed(offset: text.length);
  }

  void _reparse() {
    final next = UrlSource.parse(_field.text);
    if (next?.url != _parsed?.url || next?.kind != _parsed?.kind) {
      setState(() => _parsed = next);
    }
  }

  Future<void> _cast() async {
    final source = _parsed;
    if (source == null) return;
    final sender = SenderScope.read(context);
    final navigator = Navigator.of(context);
    await sender.castLink(source);
    if (mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final sender = SenderScope.of(context);

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const Center(
                child: Text(
                  'پخش از لینک',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Sea.text),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'لینک یوتیوب، پخش زنده، یا آدرس مستقیم ویدیو',
                  style: TextStyle(color: Sea.textDim, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 18),

              TextField(
                controller: _field,
                autofocus: true,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _parsed == null ? null : _cast(),
                style: const TextStyle(color: Sea.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'https://…',
                  hintStyle: const TextStyle(color: Sea.textFaint),
                  filled: true,
                  fillColor: Sea.glassFill,
                  prefixIcon: const Icon(Icons.link_rounded, color: Sea.textFaint, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'چسباندن',
                    icon: const Icon(Icons.content_paste_rounded, size: 19, color: Sea.azure),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) _field.text = text;
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Sea.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _KindHint(source: _parsed, hasText: _field.text.trim().isNotEmpty),

              const SizedBox(height: 16),
              GlassButton(
                label: sender.hasReceiver ? 'پخش روی تلویزیون' : 'پخش (تلویزیونی وصل نیست)',
                icon: Icons.cast_rounded,
                onPressed: _parsed == null ? null : _cast,
              ),

              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionLabel('لینک‌های اخیر'),
                for (final url in _recent.take(6))
                  _RecentTile(
                    url: url,
                    onTap: () {
                      _field.text = url;
                      _field.selection = TextSelection.collapsed(offset: url.length);
                    },
                    onRemove: () async {
                      await Prefs.instance.forgetLink(url);
                      if (mounted) setState(() => _recent = Prefs.instance.recentLinks);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells the user what will happen before they commit to it.
class _KindHint extends StatelessWidget {
  const _KindHint({required this.source, required this.hasText});

  final UrlSource? source;
  final bool hasText;

  @override
  Widget build(BuildContext context) {
    if (source == null) {
      return Text(
        hasText ? 'این آدرس شناخته نشد' : 'آدرس را وارد یا از حافظه بچسبانید',
        style: TextStyle(
          color: hasText ? Sea.danger : Sea.textFaint,
          fontSize: 12.5,
        ),
      );
    }

    final (icon, label, detail, tone) = switch (source!.kind) {
      MediaKind.youtube => (
          Icons.smart_display_rounded,
          'یوتیوب',
          'با پخش‌کننده‌ی رسمی یوتیوب پخش می‌شود؛ کیفیت را خودش با سرعت شبکه تنظیم می‌کند.',
          Sea.danger,
        ),
      MediaKind.adaptive => (
          Icons.sensors_rounded,
          'پخش زنده',
          'چند کیفیت دارد؛ اگر سرعت اینترنت افت کند، پخش‌کننده خودش کیفیت را پایین می‌آورد.',
          Sea.ok,
        ),
      MediaKind.direct => (
          Icons.movie_rounded,
          'ویدیوی مستقیم',
          'با موتور FFmpeg پخش می‌شود، پس تقریباً هر فرمتی کار می‌کند.',
          Sea.azure,
        ),
      MediaKind.file => (Icons.insert_drive_file_rounded, 'فایل', '', Sea.azure),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(Sea.radiusSm),
        border: Border.all(color: tone.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: tone, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: Sea.textDim, fontSize: 11.5, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.url, required this.onTap, required this.onRemove});

  final String url;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final source = UrlSource.parse(url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        onTap: onTap,
        radius: Sea.radiusSm,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              switch (source?.kind) {
                MediaKind.youtube => Icons.smart_display_rounded,
                MediaKind.adaptive => Icons.sensors_rounded,
                _ => Icons.link_rounded,
              },
              size: 17,
              color: Sea.textFaint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: const TextStyle(color: Sea.textDim, fontSize: 12),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Sea.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
