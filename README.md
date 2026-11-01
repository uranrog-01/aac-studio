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
| My AAC | The original app: sample vocabulary, folder grid navigation, message window, word-class color coding, platform TTS with per-button voice styles, typing view with word prediction + auto-learn, full button editor with 24k+ symbol search, caregiver restrictions lock. |
| P2G Explorer | Research viewer that renders a **locally extracted** Proloquo2Go IPA database (vocabulary, folders, grid layouts, buttons, actions) with locally pre-rendered symbol images. Local study tooling only - nothing is redistributed. |

### M3 - Voice styles
Per-button rate/pitch overrides + global speech settings (test voice button).

### M4 - Typing + prediction
On-screen QWERTY keyboard (plus hardware keyboard), prediction bar over an
open 9.9k-word frequency lexicon, auto-learn: every sentence you send teaches
the predictor your words.

### M5 - Editor + restrictions
Edit mode: tap any button to change label, spoken text, word class, symbol
(search 24,296 bundled open symbols across 6 packs, or pick an emoji), voice
overrides, delete; Add button to create new ones. Everything persists to a
local editable pack. Restrictions: 4-digit PIN gates edit mode.

## Studio shell

- Preview inside iPhone 15 / iPhone SE / iPad Air / Android tablet frames
  at correct logical sizes, portrait + landscape.
- The grid engine picks the vocabulary's view width that best fits the device.

## Run

    flutter pub get
    flutter run -d windows      # native Windows studio (needs VS C++ Build Tools)
    flutter run -d chrome       # quick web preview
    flutter build apk --release # Android APK
    flutter build ios --release --no-codesign   # on macOS / Codemagic (see codemagic.yaml)

Requirements: Flutter 3.24+, Windows: VS Build Tools with the C++ workload,
Developer Mode enabled (plugin symlinks), nuget.exe on PATH (flutter_tts).
Android: SDK with platform 35 + build-tools 35 (see android/local.properties).

## Project layout

    lib/
    +-- models/domain.dart        # vocabulary / folder / view / button / action model
    +-- data/pack_loader.dart     # JSON vocabulary packs (load + save)
    +-- data/p2g_loader.dart      # research viewer: reads extracted cache DBs
    +-- engine/speech.dart        # TTS abstraction + per-utterance voice styles
    +-- engine/prediction.dart    # word prediction + auto-learn
    +-- engine/symbol_library.dart# 24k open symbols: search + render
    +-- engine/storage.dart       # packs / settings / learned words persistence
    +-- engine/settings_controller.dart
    +-- features/grid/            # grid engine, message window, keyboard view
    +-- features/editor/          # M5 button editor with symbol picker
    +-- features/settings/        # M3 speech + M5 restrictions sheet
    +-- features/modes.dart       # My AAC + P2G Explorer wiring
    +-- studio/                   # device frames + studio shell
    assets/                       # sample pack + 24k symbols + prediction lexicon

## Licensing

Code: MIT (see LICENSE). Sample vocabulary content: original, MIT.
Symbols: six open packs with their own licenses - see THIRD_PARTY_SYMBOLS.md
(Twemoji CC-BY, Noto Apache-2.0, OpenMoji CC BY-SA, Mulberry CC BY-SA, names
from Unicode CLDR). Symbol packs you add (e.g., ARASAAC) carry their own
licenses - check before redistribution. The P2G Explorer is a personal study
tool; do not distribute extracted data or rendered symbols.
