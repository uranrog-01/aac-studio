# Flat symbol library — 1.6.0

The 1.7.0 expansion is documented in [Modern flat expansion toward 10,000](MODERN_FLAT_10000.md).
The notes below describe the 1.6.0 baseline.

All bundled symbol pictures use WebP and fit within 340 × 340 pixels. New
modern artwork is 340 × 340; smaller raster originals retain their native
resolution without extra padding, so they fill buttons correctly. Source
proportions are preserved. Original artwork under `assets/symbols`
is retained for maintenance and is excluded from Flutter's asset bundle.

The modern collection includes the complete pinned Microsoft Fluent **Flat**
collection, rather than the previous 301-image selection from its 3D collection.
Each flat replacement uses the exact original concept and skin-tone variant;
there is no fuzzy filename matching. Letters, numbers and colors use solid fills.
Human actions and uncommon objects use 59 original flat illustrations, including
the first-version “give” illustration. The other 58 were generated individually
with the built-in image generation tool using that first image as a style
reference. Generated originals are resized with LANCZOS and encoded as WebP.
The exporter chooses lossless encoding or quality 94, whichever produces the
smaller file. Transparency is preserved exactly. Already compressed exports are
marked to prevent repeated lossy recompression.

The existing Twemoji, Noto, OpenMoji, Mulberry and communication collections are
converted from their original two-dimensional artwork, rather than being
claimed as newly drawn illustrations. Their original word assignments and
licenses are preserved. The new modern flat choices take priority for exact
search matches. The library count reports distinct picture references rather
than counting search aliases as additional pictures.

Pack version 8 upgrades recognized factory pictures while preserving custom
photos, custom picture selections, edited labels, voices, favorites and layouts.
Saved `modern3d` and `twemoji_svg` references resolve through compatibility
aliases to the corresponding flat WebP assets.

The complete inventory, dimensions, checksums, upstream source paths, scene
briefs and starter assignments are in `flat-symbol-manifest.json`. Labeled
starter review sheets are `symbol-review-1.png` through `symbol-review-4.png`;
`flat-symbol-preview.png` shows a selection at larger size.

Reproduce the exports with `python tools/flatten_symbols.py --prepare --expand`,
then `--apply` after the individually generated originals are recorded in
`../work/flat_symbol_sources/generation_manifest.json`. The complete source tree
for Fluent is cached in `../work/modern_symbol_sources/fluent-emoji-tree.json`.
The pinned revision is `1ffb34c752ecf5d402f04cfb4b392c77f57c54bc`.

Run `python tools/audit_symbols.py --render` to check every exported symbol,
including format, dimensions, checksums, existence, IDs and label/message/speech
agreement. Flutter tests additionally decode every WebP with Flutter's codec,
exercise legacy reference compatibility, and check migration and message input.

Style prompt used for each scene: a polished flat 2D colorful AAC illustration,
readable at 340 pixels, matching the first-version give image's friendly
proportions and blue/yellow clothing palette; simple clear silhouettes, natural
hands, only relevant props, genuinely transparent background, no 3D rendering,
clay, extrusion, photographic materials, cast shadows, text, grid or watermark.
The exact concept-specific scene briefs are recorded in the manifest.

See `THIRD_PARTY_SYMBOLS.md` and the bundled Microsoft notice for attribution.

Validation: all 32 Flutter tests pass and Flutter analysis reports no issues.
The complete audit checks 23,912 searchable names, 23,738 indexed picture
references, 451 starter buttons and 35 categories. All 23,759 exported WebP
files pass the checksum, format and maximum 340 × 340 pixel checks; Flutter also
decodes every exported picture with its own image codec.

Android 1.6.0 (build 5003), Windows x64, and a standalone WebP symbol archive
are available in `dist/v1.6.0/`. Every packaged WebP matches the source manifest,
and the app bundles exclude legacy source / 3D artwork. Checksums and build
verification are recorded in `flat-build-verification.json`.
