# Communication and symbol repair — 1.2.0 (build 7)

## Changes

- Speech shares initialization across first/rapid taps, confines queue mode to Android, configures iOS playback audio, retries rejected speech and displays actionable failure feedback. Saved rate, pitch and volume now apply on mobile as well as desktop.
- Android manifest declares TTS engine discovery. iOS configuration follows the [flutter_tts platform documentation](https://pub.dev/packages/flutter_tts).
- One scrollable keyboard contains symbol shortcuts, A–Z, 0–9, case, space, punctuation and delete. Device software keyboard is suppressed; hardware editing, prediction and learning remain available. Backspace respects Unicode graphemes and selected text.
- The whole message panel speaks the composed message. Tapping a word no longer unexpectedly deletes it; Delete and Clear remain explicit toolbar actions.
- Small-screen toolbar wraps, and vocabulary cells scroll instead of shrinking to unusable heights. Tap ripples are disabled. Artwork is static, with visible labels.
- Fixed 335 invalid single-letter starter image references, placeholder black-square images and ambiguous matches (cricket insect versus sport, dates fruit versus calendar, orange color versus fruit, cooking pot versus plant pot).
- 36 categories, 478 starter buttons, including 29 fruit choices, 12 vegetables, A–Z and 0–20. Existing category locations remain, with additional fruit/vegetable links under Eat & drink.
- Pack v4 upgrades back up saved data, preserve existing layouts, custom buttons, edits and favorites, and repair known factory artwork. Folder artwork and custom image paths survive serialization. Word-class parsing handles properNoun correctly.

## Verification

- `flutter analyze --no-pub`
- `flutter test --no-pub --no-test-assets` — 11 regression tests. Tests serve actual asset bytes from the filesystem through a mock asset channel to avoid duplicating the 24k-entry library; platform speech calls are mocked, not audible device tests.
- `python tools/audit_symbols.py --render` — 24,296 index entries, 20,479 unique referenced files, all 478 buttons and 36 folders checked; SVG parsing and PNG header checks, button IDs and navigation references validated.
- Rendered and visually reviewed all 478 starter symbols in `symbol-review-1.png` through `symbol-review-3.png`. This is not a semantic review of every optional library image or a clinical suitability assessment. A caregiver can customize pictures to the communicator's understanding and preferences.

## Device limits and remaining physical checks

The installed Flutter engine requires Android API 24 (Android 7 / Fire OS 6). The iOS project currently targets iOS/iPadOS 15 or later. This build cannot run on every older device. No physical Android or iPad listening test was available in this workspace, and an iOS installer requires a macOS build/signing environment.

Before rollout, test first tap after cold start, repeated taps, full-message speech, silent switch, media volume, Bluetooth routing, interruption/resume, airplane mode with downloaded voices, portrait/landscape, large text, and the oldest supported Android/iPad hardware. Speech needs an installed usable device voice. The app reports engine rejection, but cannot detect a muted speaker or disconnected audio route.

The Windows test host cannot exercise the plugin's native iOS audio-category implementation. That call is platform-gated inside flutter_tts and must be verified on an iPad. Android release builds currently emit a future Kotlin-plugin compatibility warning from flutter_tts; no dependency upgrade was introduced merely to suppress it.

## Android installer

Built and inspected `dist/AAC-Studio-1.2.0-android.apk`: package `com.aacstudio.app`, version 1.2.0 / code 7, minimum API 24; arm64-v8a, armeabi-v7a and x86_64. The APK's vocabulary matches the source byte-for-byte, and every starter button/folder artwork file is included. This local release uses the project's existing debug signing configuration; it is a local test/update installer, not a store-signed release. An installed build signed with a different key cannot be updated with this APK.

SHA-256: `050178cf9b5ff23de5efb94071abdb588191558f76b16fd453074bd77ef7b38e`.
