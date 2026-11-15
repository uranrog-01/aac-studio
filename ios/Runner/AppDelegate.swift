import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Speech into phone and FaceTime calls (see CallSpeech.swift).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CallSpeech") {
      CallSpeech.shared.register(with: registrar.messenger())
    }
    // Personal Voice (iOS 17+): the person's own voice, made in Settings >
    // Accessibility > Personal Voice. Once allowed it appears in the
    // voice list like any other voice.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PersonalVoice") {
      let channel = FlutterMethodChannel(
        name: "aac_studio/personal_voice", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "request" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if #available(iOS 17.0, *) {
          AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
            DispatchQueue.main.async {
              switch status {
              case .authorized: result("authorized")
              case .denied: result("denied")
              case .unsupported: result("unsupported")
              case .notDetermined: result("notDetermined")
              @unknown default: result("unknown")
              }
            }
          }
        } else {
          result("unsupported")
        }
      }
      AppDelegate.personalVoiceChannel = channel
    }
  }

  static var personalVoiceChannel: FlutterMethodChannel?
}
