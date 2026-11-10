import 'package:flutter/foundation.dart';

import 'speech.dart';

/// State of an offline voice download ("Albanian voice"), shared by
/// Settings and the app so it keeps going after Settings is closed.
class VoiceDownload {
  final String code;
  final double progress; // 0..1
  final String? error;
  final bool done;
  const VoiceDownload(this.code,
      {this.progress = 0, this.error, this.done = false});
}

class VoiceDownloads {
  static final ValueNotifier<VoiceDownload?> current = ValueNotifier(null);

  /// Downloads the offline voice for [code] if the app has one and it is
  /// not on the device yet. Safe to call repeatedly.
  static Future<void> ensure(SpeechEngine speech, String code) async {
    if (!SpeechEngine.hasOfflineVoice(code)) return;
    final running = current.value;
    if (running != null &&
        running.code == code &&
        running.error == null &&
        !running.done) {
      return;
    }
    if (await SpeechEngine.offlineVoiceReady(code)) {
      current.value = VoiceDownload(code, progress: 1, done: true);
      return;
    }
    current.value = VoiceDownload(code);
    try {
      await speech.downloadOfflineVoice(code,
          onProgress: (v) => current.value = VoiceDownload(code, progress: v));
      current.value = VoiceDownload(code, progress: 1, done: true);
    } catch (e) {
      current.value = VoiceDownload(code,
          error: 'The voice could not be downloaded. Check the internet '
              'connection and try again.');
    }
  }
}
