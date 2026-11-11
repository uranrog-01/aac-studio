import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the app on the screen for a person who should not leave it.
///
/// Android pins the app (the system's "screen pinning"): Home, Back and the
/// app switcher no longer leave it. iPhone and iPad do not let an app lock
/// itself; there the caregiver starts Guided Access. In every case the app
/// itself ignores Back while locked, and unlocking needs the code.
class AppLock {
  static const _channel = MethodChannel('aac_studio/app_lock');

  /// Whether this device can pin the app by itself.
  static bool get canPin =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isApple =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> apply(bool locked) async {
    if (!canPin) return;
    try {
      await _channel.invokeMethod<bool>(locked ? 'start' : 'stop');
    } catch (_) {/* Pinning is unavailable: the in-app lock still works. */}
  }
}
