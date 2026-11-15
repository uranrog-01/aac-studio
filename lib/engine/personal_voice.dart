import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple Personal Voice (iOS 17+): a voice that sounds like the person,
/// recorded in Settings > Accessibility > Personal Voice. The app asks
/// once for permission; then it is in the voice list like any voice.
class PersonalVoice {
  static const _channel = MethodChannel('aac_studio/personal_voice');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 'authorized', 'denied', 'unsupported', 'notDetermined' or 'unknown'.
  static Future<String> request() async {
    if (!supported) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('request') ?? 'unknown';
    } catch (_) {
      return 'unsupported';
    }
  }
}
