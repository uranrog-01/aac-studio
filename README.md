# AAC Studio

An original, open-source AAC (Augmentative and Alternative Communication) app
builder with a **live preview studio**: the same code runs as an iPhone, iPad,
or Android-tablet preview on Windows, and ships to real devices from one
codebase.

Built as a clean-room project informed by a reverse-engineering study of
Proloquo2Go 2.3 (see `../work/notes/ARCHITECTURE.md`). **No copyrighted code,
symbols, voices, or artwork from that app is included.**

## Features (M0-M5)

| Mode | What it is |
|---|---|
| My AAC | The original app: sample vocabulary, folder grid navigation, message window, word-class color coding, platform TTS with per-button voice styles, typing view with word prediction + auto-learn, full button editor with 23.8k-picture symbol search, caregiver restrictions lock. |
| P2G Explorer | Research viewer that renders a **locally extracted** Proloquo2Go IPA database (vocabulary, folders, grid layouts, buttons, actions) with locally pre-rendered symbol images. Local study tooling only - nothing is redistributed. |

### M3 - Voice styles
Per-button rate/pitch overrides + global speech settings (test voice button).

### M4 - Typing + prediction
Unified symbol, alphabet and number keyboard (plus hardware keyboard), prediction bar over an
open 9.9k-word English frequency lexicon; in the other 20 languages the
board's own words are suggested. Auto-learn: every sentence you send teaches
the predictor your words, kept per language.

### M5 - Editor + restrictions
Edit mode: tap any button to change label, spoken text, word class, symbol
(search about 7,300 bundled open pictures: modern flat, Mulberry and flags), voice
overrides, delete; Add button to create new ones. Everything persists to a
local editable pack. Restrictions: 4-digit PIN gates edit mode.

## Studio shell

- Preview inside iPhone 15 / iPhone SE / iPad Air / Android tablet frames
  at correct logical sizes, portrait + landscape.
- The grid engine picks the vocabulary's view width that best fits the device.

## Run

For a one-click Windows release build, double-click **`build.bat`** in this
folder or the parent project folder. It collects APK, web ZIP, and a fresh
unsigned IPA from GitHub's Mac runner. One-time GitHub login and details:
**[Build instructions](docs/BUILD.md)**. The IPA requires signing before iPhone
installation.

    flutter pub get
    flutter run -d windows      # native Windows studio (needs VS C++ Build Tools)
    flutter run -d chrome       # quick web preview
    flutter build apk --release # Android APK
    flutter build ios --release --no-codesign   # on macOS / Codemagic (see codemagic.yaml)

Requirements: Flutter 3.24+, Windows: VS Build Tools with the C++ workload,
Developer Mode enabled (plugin symlinks), nuget.exe on PATH (flutter_tts).
Android: SDK with platform 35 + build-tools 35 (see android/local.properties).
Android OS floor: **Android 7.0+ (Fire OS 6+)** — the Flutter engine requires API 24; older 2015-2018 Fire tablets (Fire OS 5) are below that floor. Slim per-CPU APKs ship alongside the universal one in each GitHub release.

## Project layout

    lib/
    +-- models/domain.dart        # vocabulary / folder / view / button / action model
    +-- data/pack_loader.dart     # JSON vocabulary packs (load + save)
    +-- data/p2g_loader.dart      # research viewer: reads extracted cache DBs
    +-- engine/speech.dart        # TTS abstraction + per-utterance voice styles
    +-- engine/prediction.dart    # word prediction + auto-learn
    +-- engine/symbol_library.dart# 23.8k open pictures: search + render
    +-- engine/storage.dart       # packs / settings / learned words persistence
    +-- engine/settings_controller.dart
    +-- features/grid/            # grid engine, message window, keyboard view
    +-- features/editor/          # M5 button editor with symbol picker
    +-- features/settings/        # M3 speech + M5 restrictions sheet
    +-- features/modes.dart       # My AAC + P2G Explorer wiring
    +-- studio/                   # device frames + studio shell
    assets/                       # sample pack + 23.8k pictures + prediction lexicon

## Wireless install (no USB)

The studio panel has an **Install on device** section: click *Start Wi-Fi
install* — the studio serves your built packages over your LAN and shows a QR
code. Scan it with the phone/tablet (same Wi-Fi), open the link, download.
Nothing leaves your network.

- **Android**: the served `.apk` installs directly — allow "Install unknown
  apps" for your browser when asked. Build it with `flutter build apk --release`.
- **iPhone / iPad (iOS/iPadOS 15+)**: the served `.ipa` is **unsigned**; iOS
  will download it but never self-install it (an unsigned file is invisible to
  the installer — this is why a QR scan can appear to "do nothing"). Sideload
  it instead:
  1. Get `AACStudio-unsigned.ipa` from the Codemagic **iOS (unsigned IPA)**
     workflow (it also lands in `dist/`), or build on a Mac with
     `flutter build ios --release --no-codesign` and zip `Runner.app` into a
     `Payload/` folder.
  2. On Windows: install [Sideloadly](https://sideloadly.io) (or
     [AltStore](https://altstore.io)), plug the iPhone in via USB, load the
     IPA, sign with a free Apple ID, install. The app is native **arm64** and
     runs on any modern iOS; free accounts need a re-sign every 7 days.
  3. Trust the developer profile under Settings → General → VPN & Device
     Management on first launch.
- **True tap-to-install OTA** (the `itms-services://` QR style): requires a
  **paid** Apple Developer account ($99/yr) — signed IPA + HTTPS-hosted
  manifest with a trusted certificate. Self-signed HTTP QRs fail silently on
  iOS by design. Add a signing group in Codemagic's UI to go this route.

Full decision tree (TrollStore on old iOS, Sideloadly + free Apple ID,
on-device SideStore/ESign bootstrap, security warnings about fake "ESign
iOS" repos) and the USB install helper: **[docs/IOS_SIGNING.md](docs/IOS_SIGNING.md)**.

## Input & access

- **Typing view**: one symbol/alphabet/number keyboard + hardware keyboard; every keystroke goes
  live into the message window (no send button); prediction bar + auto-learn;
  **tap the chat banner to speak it**.
- **Edit mode**: always gated by a code (default **1234**, changeable in
  Speech & restrictions settings).

## Licensing

Code: MIT (see LICENSE). Sample vocabulary content: original, MIT.
Symbols: open packs with their own licenses - see THIRD_PARTY_SYMBOLS.md
(Fluent Emoji Flat MIT, Mulberry CC BY-SA, Twemoji flags CC-BY, names from
Unicode CLDR). Symbol packs you add (e.g., ARASAAC) carry their own
licenses - check before redistribution. The P2G Explorer is a personal study
tool; do not distribute extracted data or rendered symbols.

## Communication reliability update

See [repair and verification notes](docs/COMMUNICATION_FIXES.md) for speech, keyboard, category and symbol fixes, supported OS limits, and physical-device checks.

See [message and picture corrections](docs/SYMBOL_AND_MESSAGE_FIXES.md) for the single message box, consolidated Clear control, 57 corrected image assignments and SVG color rendering repairs.

Version 1.6.0 uses [flat illustrations and WebP throughout the symbol library](docs/FLAT_SYMBOLS.md), with a maximum size of 340 × 340 pixels. It supersedes the 1.4.0 soft 3D starter artwork.

Version 1.7.0 adds 110 reviewed modern flat pictures, bringing that collection to
3,374. The [10,000-symbol expansion](docs/MODERN_FLAT_10000.md) remains in progress;
queued concepts are not counted as finished images.

## Piper offline speech (1.3.0)

Piper LJ Speech medium (US English, female voice) is bundled and enabled by
default. No account, server, or voice download is needed after installation.
The first launch prepares the voice in the background; device speech remains
available during setup and automatically takes over if Piper fails.

Choose **Speech & restrictions > Piper offline voice** to switch between
Piper and device speech. Rate and volume work with Piper. Pitch changes use
the device voice so existing button overrides keep working.

The voice archive is approximately 64 MiB; native libraries and pronunciation
data add further installation space. [Offline speech notes](docs/PIPER_SPEECH.md)
cover implementation, checks, licenses, and device limitations. The combined
build includes a GPL phonemizer; the original code's MIT notice does not
replace its distribution terms.

## Simpler Home and voice choice (pack v7)

Home has 40 buttons with no duplicates. Settings has five plain groups and a voice picker. See [docs/SIMPLER_HOME_AND_VOICE.md](docs/SIMPLER_HOME_AND_VOICE.md).

## Easier Home (board v13)

Home starts with what is needed most, one idea per row: asking (I, want,
more, help, stop), answers (yes, no, all done, wait, again), body needs (eat,
drink, water, toilet, sleep), how I feel, feelings, people, doing, places,
greetings and questions: 64 words, then 16 categories. "All categories" is
grouped by topic. A Home page that was never rearranged moves to this layout
when the app updates; a page the person changed keeps its own order and only
gains the new words. Built by `tools/simplify_home_v13.py`.

## Languages

21 languages (English plus 20 translations) for the app's own text and all
board words. Sources are `tools/data/i18n/<code>.txt` and `_ui_extra.txt`;
run `python tools/build_i18n.py` after editing. A word with two meanings can
be translated per button (`@<button id>|translation`), and words a girl or
woman says differently go in `[words_f]` / `[forms_f]` (Albanian so far:
Settings > Language & voice > "The person speaking is").

`python tools/review_sheets.py --lang sq` writes one page per category to
`build/review-sheets/` with every picture next to its word, for a human check.

`.github/workflows/test.yml` runs the analyzer, the tests and a check that
the translation files match their sources on every push.

## Board v14, Settings and the app lock

- **Core words with pictures:** 38 more words (me, him, her, us, they, mine,
  have, know, different, later, ...). 19 pictures are composed from bundled
  artwork by `tools/compose_core_words.py`; the rest use bundled pictures
  that were not on the board. No picture generator is involved.
- **Start small and grow:** Settings > Caregiver > Words on Home shows the
  first 10, 25 or 45 Home words, or all. Words never move.
- **Updates never move buttons:** an installed board keeps its order and only
  gains new words. Caregiver > "Use the new Home layout" switches on purpose.
- **Settings** is a short menu; each section opens on its own page. Voices are
  listed as Female, Male and Other.
- **Lock the app on the screen** (Caregiver > Safety): Back never leaves the
  app, Android pins it, and unlocking (More > Unlock the app) needs the code.
  iPhone and iPad cannot be locked by an app: start Guided Access as well.

## Albanian recorded voice (1.9.1)

Phones, tablets and most browsers have no Albanian voice, so an English voice
used to read Albanian words with English sounds. All 3,234 Albanian board
words, category names and sentence forms now ship as recordings of the
Albanian Piper voice "Edon" (`assets/voices/clips/sq/`, 12 MB), made with the
official Piper program at a calm 80% pace. They play first on every device,
including the web app; the downloadable live voice covers typed text, and the
device voice is used only for words without a recording. Rebuild them with
`tools/build_voice_clips.py` (see its header) after Albanian words change.
