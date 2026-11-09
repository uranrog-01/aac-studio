import 'dart:js_interop';

@JS('aacWeb.setFullscreen')
external void _setFullscreen(bool on);

/// Web: browsers only allow full screen after a tap, so the page enters it
/// on the next tap (Android Chrome, iPad, computers). An iPhone shows the
/// app without browser bars when it is added to the Home Screen.
class ScreenMode {
  static Future<void> apply(bool fullScreen) async {
    try {
      _setFullscreen(fullScreen);
    } catch (_) {/* Older page without the helper. */}
  }
}
