import 'dart:developer' as developer;

/// Debug-only logging for the layers that stay free of Flutter imports
/// (`model/`, `net/`, `subs/`), so they can run and be tested as plain Dart.
///
/// The assert trick means the call disappears entirely in release builds.
void logDebug(String message) {
  assert(() {
    developer.log(message, name: 'lancast');
    return true;
  }());
}
