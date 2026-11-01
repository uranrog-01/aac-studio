# Message display and symbol corrections

The typing screen now has one editable message box. It supports the on-screen
keys, hardware typing, selections and tapping the message to speak. The duplicate
message banner is removed. The grid toolbar has one **Clear** action; its duplicate
**Del** control is removed. The keyboard's Delete key still edits a selection or
one complete character, including joined emoji.

All 478 starter buttons and 36 category pictures were rendered with their labels
and reviewed in `symbol-review-1.png` through `symbol-review-4.png`. There are 57
corrected starter image assignments. Examples include pronouns, helping, breathing,
playing, reading, writing, listening, building blocks, American football, cooking,
rooster and high five. The ninja-star tile retains its original meaning and now
has a matching star picture. Keyboard shortcuts use matching action pictures too.

The actual Flutter render also exposed 327 Mulberry SVGs whose colors depended on
CSS style elements, which Flutter's SVG renderer ignores. The symbol loader now
inlines those class rules, respecting grouped selectors, rule order and inline
overrides. The app renders colored artwork and outlines instead of silhouettes.
Source SVGs and their licenses remain intact.

`symbol-meaning-repairs.json` records the assignments. Existing Mulberry and emoji
assets retain their licenses; 19 original SVG communication pictograms are MIT
licensed. These are representational communication symbols; abstract words such
as “my” and “please” necessarily use a visual convention.

Pack version 5 ships the repairs to existing installations. The migration uses
known factory references in `assets/factory_symbol_history.json`, while retaining
custom pictures, edited labels, favorites, custom buttons and existing layouts.
The normal pack upgrade creates a backup before saving.

Verification:

- `flutter analyze --no-pub`
- `flutter test --no-pub --no-test-assets`
- `python tools/audit_symbols.py --render` (Pillow and resvg-py, or CairoSVG)

The audit checks all 24,315 library entries and 20,498 unique referenced files,
SVG syntax and PNG headers, navigation links, category-picture consistency and
the corrected assignments. The visual review covers the starter vocabulary;
the optional library is checked structurally.

All 24 tests passed, including a pixel-color assertion on an actual Mulberry
picture, normalization of all 327 affected SVGs, one message editor at phone and
tablet sizes, selected deletion and joined-emoji backspace, and factory-picture
upgrades that preserve customization.

Both `flutter build windows --release --no-pub` and
`flutter build apk --release --no-pub` succeeded. In the running Windows app,
verified colored Mulberry artwork, a single editable message field, and an
installed pack upgrade from version 3 to 5. The Windows bundle's vocabulary,
history and index match source bytes and all starter artwork is present.

The Android installer is `dist/AAC-Studio-symbol-and-message-fixes-android.apk`.
Its vocabulary, history, index and all 447 unique starter artwork files match
source bytes. SHA-256:
`4a6b86c0b8af285496b890bb72c34b0b58acab8de055d24e75a253cf73312410`.
