# AAC Studio

An original, open-source AAC (Augmentative and Alternative Communication) app
builder with a **live preview studio**: the same code runs as an iPhone, iPad,
or Android-tablet preview on Windows, and ships to real devices from one
codebase.

Built as a clean-room project informed by a reverse-engineering study of
Proloquo2Go 2.3 (see `../work/notes/ARCHITECTURE.md`). **No copyrighted code,
symbols, voices, or artwork from that app is included.**

## Modes

| Mode | What it is |
|---|---|
| My AAC | The original app (M0-M2): sample vocabulary, folder grid navigation, message window, word-class color coding, platform TTS. Emoji symbols out of the box; ARASAAC/Mulberry symbol packs plug into the same SymbolRef abstraction. |
| P2G Explorer | Research viewer that renders a **locally extracted** Proloquo2Go IPA database (vocabulary, folders, grid layouts, buttons, actions) with locally pre-rendered symbol images. Local study tooling only - nothing is redistributed. |

## Studio shell

- Preview inside iPhone 15 / iPhone SE / iPad Air / Android tablet frames
  at correct logical sizes, portrait + landscape.
- The grid engine picks the vocabulary's view width that best fits the device
  (same behavior as the studied app's per-device grid variants).

## Run

    flutter pub get
    flutter run -d windows      # native Windows studio (needs VS C++ Build Tools)
    flutter run -d chrome       # quick web preview (original mode only)

Requirements: Flutter 3.24+, Windows: VS Build Tools with the C++ workload,
Developer Mode enabled (plugin symlinks), nuget.exe on PATH (flutter_tts).

## Project layout

    lib/
    +-- models/domain.dart        # vocabulary / folder / view / button / action model
    +-- data/pack_loader.dart     # JSON vocabulary packs (original content)
    +-- data/p2g_loader.dart      # research viewer: reads extracted cache DBs
    +-- engine/speech.dart        # TTS abstraction (platform voices)
    +-- features/grid/            # grid engine + message window + session controller
    +-- features/modes.dart       # My AAC + P2G Explorer wiring
    +-- studio/                   # device frames + studio shell
    assets/sample_pack.json       # the original sample vocabulary

## Roadmap (M0-M8)

- [x] M0 Studio scaffold, device frames, shell
- [x] M1 Data layer: pack format + loader; P2G research loader
- [x] M2 Grid engine: navigation, message window, TTS
- [ ] M3 Voice styles (rate/pitch/volume per button), speech settings UI
- [ ] M4 Typing view + word prediction + auto-learn
- [ ] M5 Editor (add/edit buttons/folders), symbol chooser, restrictions lock
- [ ] M6 Backup/restore (ZIP), Wi-Fi backup server on desktop
- [ ] M7 Android + iOS device builds and tablet layouts
- [ ] M8 Your features: cloud sync, AI symbol search, themes, ...

## Licensing

Code: MIT (see LICENSE). Sample vocabulary content: original, MIT.
Symbol packs you add (e.g., ARASAAC) carry their own licenses - check before
redistribution. The P2G Explorer is a personal study tool; do not distribute
extracted data or rendered symbols.
