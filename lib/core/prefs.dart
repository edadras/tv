import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/protocol.dart';
import 'device.dart';

/// Small persisted settings bag. Loaded once at startup so nothing on the
/// hot path ever awaits disk.
class Prefs {
  Prefs._(this._store);

  final SharedPreferences _store;

  static late Prefs instance;

  static Future<void> init() async {
    instance = Prefs._(await SharedPreferences.getInstance());
  }

  // Role override: null means "decide from the hardware".
  AppRole? get roleOverride {
    final v = _store.getString('role');
    return AppRole.values.where((r) => r.name == v).firstOrNull;
  }

  Future<void> setRoleOverride(AppRole? role) async {
    if (role == null) {
      await _store.remove('role');
    } else {
      await _store.setString('role', role.name);
    }
  }

  String? get lastHost => _store.getString('lastHost');
  Future<void> setLastHost(String? v) async =>
      v == null ? _store.remove('lastHost') : _store.setString('lastHost', v);

  String? get lastFolder => _store.getString('lastFolder');
  Future<void> setLastFolder(String v) => _store.setString('lastFolder', v);

  SubtitleStyleSpec get subtitleStyle {
    final raw = _store.getString('subStyle');
    if (raw == null) return const SubtitleStyleSpec();
    try {
      return SubtitleStyleSpec.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return const SubtitleStyleSpec();
    }
  }

  Future<void> setSubtitleStyle(SubtitleStyleSpec s) =>
      _store.setString('subStyle', jsonEncode(s.toJson()));

  /// Per-film subtitle offset, so re-opening a film keeps the sync you dialled in.
  int subDelayFor(String mediaKey) => _store.getInt('delay:$mediaKey') ?? 0;
  Future<void> setSubDelayFor(String mediaKey, int ms) =>
      _store.setInt('delay:$mediaKey', ms);

  /// Resume point, keyed by file path.
  int resumeFor(String mediaKey) => _store.getInt('resume:$mediaKey') ?? 0;
  Future<void> setResumeFor(String mediaKey, int ms) =>
      _store.setInt('resume:$mediaKey', ms);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
