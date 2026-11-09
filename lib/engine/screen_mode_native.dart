import 'package:flutter/services.dart';

/// Full screen on iPhone/iPad and Android: the status bar and navigation
/// bar are hidden; a swipe from the screen edge shows them for a moment
/// (so the person cannot get stuck, and a caregiver can still leave).
class ScreenMode {
  static Future<void> apply(bool fullScreen) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
          fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    } catch (_) {/* Desktop or tests: nothing to hide. */}
  }
}
