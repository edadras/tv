import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../media/library.dart';
import '../../state/scope.dart';
import '../common/glass.dart';
import 'connect_sheet.dart';

/// Browse the phone's storage and cast a file with one tap.
class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, required this.onCastStarted});

  final VoidCallback onCastStarted;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> with WidgetsBindingObserver {
  bool _granted = false;
  bool _awaitingGrant = false;
  bool _checking = true;
  String? _folder;
  List<LibraryEntry> _entries = const [];
  List<LibraryEntry> _shortcuts = const [];
  List<LibraryEntry> _recent = const [];
  bool _loading = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "All files access" on Android 11+ is a Settings screen with no result,
    // so the grant is only visible once the user comes back to us.
    if (state == AppLifecycleState.resumed && _awaitingGrant) {
      _awaitingGrant = false;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final ok = await _hasAccess();
    if (!mounted) return;
    setState(() {
      _granted = ok;
      _checking = false;
    });
    if (ok) await _openFolder(Prefs.instance.lastFolder ?? await Library.defaultRoot());
  }

  Future<bool> _hasAccess() async {
    if (!Platform.isAndroid) return true;
    if (await DeviceFacts.hasStorageAccess()) return true;
    // Some boxes grant neither permission but still allow the read.
    final root = await Library.defaultRoot();
    if (root == null) return false;
    try {
      await Directory(root).list().first;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestAccess() async {
    _awaitingGrant = true;
    final granted = await DeviceFacts.requestStorageAccess();
    if (!mounted) return;
    if (granted) {
      _awaitingGrant = false;
      setState(() => _granted = true);
      await _openFolder(Prefs.instance.lastFolder ?? await Library.defaultRoot());
    }
    // Otherwise the settings screen is now open; didChangeAppLifecycleState
    // picks the result up when the user returns.
  }

  Future<void> _openFolder(String? path) async {
    if (path == null) return;
    setState(() => _loading = true);
    final entries = await Library.list(path);
    final shortcuts = _shortcuts.isEmpty ? await Library.shortcuts() : _shortcuts;
    if (!mounted) return;
    setState(() {
      _folder = path;
      _entries = entries;
      _shortcuts = shortcuts;
      _loading = false;
    });
    unawaitedSave(path);
  }

  void unawaitedSave(String path) {
    Prefs.instance.setLastFolder(path);
  }

  Future<void> _scanRecent() async {
    setState(() => _scanning = true);
    final found = await Library.recentVideos();
    if (!mounted) return;
    setState(() {
      _recent = found;
      _scanning = false;
    });
  }

  Future<void> _pickWithSystemPicker() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) await _cast(path);
  }

  Future<void> _cast(String path) async {
    final sender = SenderScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!sender.hasReceiver) {
      // Nothing is listening yet: show the pairing card instead of casting
      // into the void, so the user always knows what is missing.
      final proceed = await showConnectSheet(context, null, askToContinue: true);
      if (proceed != true) return;
    }
    await sender.castFile(path);
    if (!mounted) return;
    widget.onCastStarted();
    messenger.showSnackBar(
      SnackBar(content: Text('در حال پخش: ${Fmt.title(p.basenameWithoutExtension(path))}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Center(child: CircularProgressIndicator(color: Sea.azure));
    }
    if (!_granted) return _PermissionGate(onGrant: _requestAccess, onPick: _pickWithSystemPicker);

    final parent = _folder == null ? null : p.dirname(_folder!);
    final canGoUp = _folder != null &&
        parent != _folder &&
        !Library.roots.contains(_folder) &&
        _folder != '/';

    return RefreshIndicator(
      color: Sea.azure,
      backgroundColor: Sea.navyHigh,
      onRefresh: () => _openFolder(_folder),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          _PathBar(
            folder: _folder,
            canGoUp: canGoUp,
            onUp: () => _openFolder(parent),
            onPicker: _pickWithSystemPicker,
          ),
          const SizedBox(height: 12),
          if (_shortcuts.isNotEmpty) ...[
            const SectionLabel('میان‌بُرها'),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _shortcuts.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  if (i == _shortcuts.length) {
                    return GlassButton(
                      label: _scanning ? 'در حال جست‌وجو…' : 'جست‌وجوی فیلم‌ها',
                      icon: Icons.travel_explore_rounded,
                      filled: false,
                      compact: true,
                      onPressed: _scanning ? null : _scanRecent,
                    );
                  }
                  final s = _shortcuts[i];
                  return GlassButton(
                    label: s.name,
                    icon: Icons.folder_rounded,
                    filled: false,
                    compact: true,
                    onPressed: () => _openFolder(s.path),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_recent.isNotEmpty) ...[
            SectionLabel(
              'آخرین فیلم‌های پیداشده',
              trailing: GestureDetector(
                onTap: () => setState(() => _recent = const []),
                child: const Text('بستن', style: TextStyle(color: Sea.azure, fontSize: 12)),
              ),
            ),
            for (final e in _recent.take(12))
              _EntryTile(entry: e, onTap: () => _cast(e.path)),
            const SizedBox(height: 16),
          ],
          const SectionLabel('این پوشه'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator(color: Sea.azure)),
            )
          else if (_entries.isEmpty)
            const _Empty()
          else
            for (final e in _entries)
              _EntryTile(
                entry: e,
                onTap: () => e.isDirectory ? _openFolder(e.path) : _cast(e.path),
              ),
        ],
      ),
    );
  }
}

class _PathBar extends StatelessWidget {
  const _PathBar({
    required this.folder,
    required this.canGoUp,
    required this.onUp,
    required this.onPicker,
  });

  final String? folder;
  final bool canGoUp;
  final VoidCallback onUp;
  final VoidCallback onPicker;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      radius: Sea.radiusSm,
      child: Row(
        children: [
          GlassIconButton(
            icon: Icons.arrow_forward_rounded,
            size: 36,
            onPressed: canGoUp ? onUp : null,
            tooltip: 'پوشه‌ی بالاتر',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder == null ? '—' : _short(folder!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: const TextStyle(color: Sea.textDim, fontSize: 12.5),
            ),
          ),
          GlassIconButton(
            icon: Icons.folder_open_rounded,
            size: 36,
            onPressed: onPicker,
            tooltip: 'انتخاب با فایل‌منیجر گوشی',
          ),
        ],
      ),
    );
  }

  static String _short(String path) =>
      path.replaceFirst('/storage/emulated/0', 'حافظه‌ی داخلی');
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isFolder = entry.isDirectory;
    final isSub = entry.isSubtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        onTap: onTap,
        radius: Sea.radiusSm,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: isFolder
                    ? Sea.violet.withValues(alpha: .16)
                    : (isSub ? Sea.aqua.withValues(alpha: .14) : Sea.azure.withValues(alpha: .16)),
              ),
              child: Icon(
                isFolder
                    ? Icons.folder_rounded
                    : (isSub ? Icons.subtitles_rounded : Icons.movie_rounded),
                size: 20,
                color: isFolder ? Sea.violet : (isSub ? Sea.aqua : Sea.azure),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.title(isFolder ? entry.name : p.basenameWithoutExtension(entry.name)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Sea.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isFolder)
                    Text(
                      '${p.extension(entry.name).replaceFirst('.', '').toUpperCase()}'
                      ' • ${Fmt.bytes(entry.size)}',
                      style: const TextStyle(color: Sea.textFaint, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            Icon(
              isFolder ? Icons.chevron_left_rounded : Icons.play_circle_fill_rounded,
              color: isFolder ? Sea.textFaint : Sea.azure,
              size: isFolder ? 22 : 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({required this.onGrant, required this.onPick});

  final VoidCallback onGrant;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassPanel(
          strong: true,
          glow: Sea.azure,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_special_rounded, size: 46, color: Sea.azure),
              const SizedBox(height: 14),
              const Text(
                'دسترسی به فایل‌ها',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Sea.text),
              ),
              const SizedBox(height: 8),
              const Text(
                'برای اینکه فیلم بدون کپی‌شدن و با سرعت کامل پخش شود، '
                'اپ باید فایل اصلی را روی حافظه بخواند.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Sea.textDim, fontSize: 13.5, height: 1.8),
              ),
              const SizedBox(height: 18),
              GlassButton(label: 'اجازه می‌دهم', icon: Icons.check_rounded, onPressed: onGrant),
              const SizedBox(height: 10),
              GlassButton(
                label: 'به‌جایش از فایل‌منیجر انتخاب می‌کنم',
                icon: Icons.folder_open_rounded,
                filled: false,
                compact: true,
                onPressed: onPick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.movie_filter_outlined, size: 38, color: Sea.textFaint),
            SizedBox(height: 10),
            Text(
              'ویدیویی در این پوشه نیست',
              style: TextStyle(color: Sea.textFaint, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
