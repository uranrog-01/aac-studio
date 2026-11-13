import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android screen pinning is managed separately from the caregiver lock.
class AppLock {
  static const _channel = MethodChannel('aac_studio/app_lock');

  /// Whether this device can pin the app by itself.
  static bool get canPin =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isApple =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool?> start() => _invoke('start');
  static Future<bool?> stop() => _invoke('stop');
  static Future<bool?> active() => _invoke('active');

  static String statusLabel(bool? active) => switch (active) {
        true => 'Screen pinning is active',
        false => 'Screen pinning is off',
        null => 'Screen pinning status unavailable',
      };

  static Future<bool?> _invoke(String method) async {
    if (!canPin) return null;
    try {
      return await _channel.invokeMethod<bool>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
