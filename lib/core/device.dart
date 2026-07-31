import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which half of the app we are running.
enum AppRole {
  /// Phone/tablet: picks the film, hosts the files, drives the remote.
  sender,

  /// Android TV / box: plays what the phone sends.
  receiver,
}

/// Device facts we need once at startup, plus the couple of platform calls
/// that have no plugin worth the dependency.
class DeviceFacts {
  const DeviceFacts({
    required this.name,
    required this.isTelevision,
    required this.isLowEnd,
    this.apkPath,
  });

  final String name;
  final bool isTelevision;

  /// Cheap TV sticks choke on full-screen backdrop blur, so we dial it back.
  final bool isLowEnd;

  /// Path to our own installed APK, so the phone can serve it to the TV.
  final String? apkPath;

  static const _channel = MethodChannel('lancast/native');

  static Future<DeviceFacts> load() async {
    if (!Platform.isAndroid) {
      return DeviceFacts(
        name: Platform.localHostname,
        isTelevision: false,
        isLowEnd: false,
      );
    }

    var name = 'Android';
    var tv = false;
    var sdk = 34;
    String? apk;

    try {
      final info = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
      if (info != null) {
        name = (info['name'] as String?)?.trim().isNotEmpty ?? false
            ? (info['name'] as String).trim()
            : name;
        tv = (info['isTelevision'] as bool?) ?? false;
        sdk = (info['sdkInt'] as num?)?.toInt() ?? sdk;
        apk = info['apkPath'] as String?;
      }
    } on PlatformException catch (e) {
      debugPrint('native channel failed: ${e.message}');
    } on MissingPluginException {
      // Running without the native half (tests, desktop): defaults are fine.
    }

    return DeviceFacts(
      name: name,
      isTelevision: tv,
      // Pre-Pie TV boxes are the ones that visibly drop frames behind blur.
      isLowEnd: tv && sdk < 28,
      apkPath: apk,
    );
  }

  /// Keeps the TV screen on while a film is playing.
  static Future<void> keepAwake(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('keepAwake', {'on': enabled});
    } on PlatformException catch (e) {
      debugPrint('keepAwake: ${e.message}');
    } on MissingPluginException {
      // Non-fatal: the screen may dim, playback still works.
    }
  }

  /// True when we can read the user's films straight off storage.
  static Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasStorageAccess') ?? false;
    } on PlatformException catch (e) {
      debugPrint('hasStorageAccess: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks for storage access. On Android 11+ this opens the "all files access"
  /// settings screen and returns false immediately — the caller re-checks with
  /// [hasStorageAccess] once the app is resumed.
  static Future<bool> requestStorageAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestStorageAccess') ?? false;
    } on PlatformException catch (e) {
      debugPrint('requestStorageAccess: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
