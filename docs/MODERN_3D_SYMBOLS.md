# Soft 3D vocabulary artwork — 1.4.0

All 478 starter buttons and 36 category pictures now use a consistent soft 3D
picture set. Microsoft Fluent Emoji supplies objects and expressions; 56 original
illustrations supply human actions, relationships and objects without a suitable
direct match. Alphabet, number and color cards have clean dimensional styling.
All pictures are transparent PNGs, at least 256 pixels square; the generated
illustrations retain their original high-resolution files unchanged. The set has
417 unique images, including 301 Fluent images, 56 generated scenes, 49
letter/number cards and 11 color indicators.

The actual actions are depicted: eating, drinking, giving, opening, reading,
writing, cooking, brushing teeth, breathing, listening, helping and taking turns.
Orange fruit and orange color have different images; chicken in Eat & drink is
cooked poultry; cricket is an insect; dates are fruit. Labels, message text and
spoken text stay synchronized. Abstract words use a consistent visual convention.

Pictures now fill the space available inside a tile rather than stopping at a
fixed 52-pixel size. High-quality image sampling and bounded decode sizes support
clear pictures on phones and tablets. Symbol search puts exact modern matches
first, accepts the original Fluent names as aliases and avoids duplicate images.

Pack version 6 upgrades the factory pictures on existing installations while
keeping custom pictures, edited labels, favorites, voice choices and layouts.
Even a button whose voice was edited gets the new picture when its image still
matches a known factory reference. A backup is made before the pack upgrade.

The source manifest is `modern-symbol-manifest.json`; all starter artwork is
rendered with its labels in `symbol-review-1.png` through `symbol-review-4.png`.
`tools/audit_symbols.py --render` validates assignments, label/speech/message
agreement, navigation links, PNG resolution, transparency and image checksums.
The optional legacy library remains available for custom vocabularies.

Art provenance: [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji)
and its [MIT license](https://github.com/microsoft/fluentui-emoji/blob/1ffb34c752ecf5d402f04cfb4b392c77f57c54bc/LICENSE).
See `THIRD_PARTY_SYMBOLS.md` for bundled notices.

Validation: all 25 Flutter tests passed and `flutter analyze --no-pub` reported
no issues. The image audit validated all 478 buttons, 36 categories, 24,898 index
names and 20,894 referenced image files. Every modern picture passed resolution,
transparency and checksum checks.
