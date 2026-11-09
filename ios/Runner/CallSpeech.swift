import AVFoundation
import Flutter

/// Speech that the other person hears during a phone or FaceTime call
/// (iOS 13+: AVSpeechSynthesizer.mixToTelephonyUplink). Used instead of
/// the normal speech plugin when "Speak into phone and FaceTime calls" is
/// on. Outside a call it sounds the same as normal speech.
final class CallSpeech: NSObject {
  static let shared = CallSpeech()
  private let synthesizer = AVSpeechSynthesizer()
  private var channel: FlutterMethodChannel?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "aac/call_speech",
                                       binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "available":
        if #available(iOS 13.0, *) { result(true) } else { result(false) }
      case "speak":
        let args = call.arguments as? [String: Any] ?? [:]
        result(self.speak(args) ? 1 : 0)
      case "stop":
        self.synthesizer.stopSpeaking(at: .immediate)
        result(1)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func speak(_ args: [String: Any]) -> Bool {
    guard let text = args["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    if #available(iOS 13.0, *) {
      synthesizer.mixToTelephonyUplink = true
    }
    if (args["interrupt"] as? Bool) == true && synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    let utterance = AVSpeechUtterance(string: text)
    // Same 0-1 speed scale as the speech plugin (0.5 is normal on iOS).
    if let rate = args["rate"] as? Double {
      utterance.rate = Float(max(0, min(1, rate)))
    }
    if let pitch = args["pitch"] as? Double {
      utterance.pitchMultiplier = Float(max(0.5, min(2, pitch)))
    }
    if let volume = args["volume"] as? Double {
      utterance.volume = Float(max(0, min(1, volume)))
    }
    let name = args["voiceName"] as? String ?? ""
    let locale = args["locale"] as? String ?? ""
    if !name.isEmpty,
       let voice = AVSpeechSynthesisVoice.speechVoices().first(where: {
         $0.name == name && (locale.isEmpty || $0.language == locale)
       }) {
      utterance.voice = voice
    } else if !locale.isEmpty, let voice = AVSpeechSynthesisVoice(language: locale) {
      utterance.voice = voice
    }
    synthesizer.speak(utterance)
    return true
  }
}
