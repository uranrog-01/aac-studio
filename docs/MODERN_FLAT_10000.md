# Modern flat expansion toward 10,000

Current reviewed artwork: **3,374 modern flat symbols**. This adds **110** actual
WebP files to the 3,264-image baseline. **6,626** more are needed to reach 10,000.
Planning rows, search aliases, failed requests and unreviewed images are not
counted as completed artwork.

The new batch contains 107 accepted illustrations made with the built-in image
generation tool and three precise repo-native SVG graphics: circle, today and
whisk. All exported files are WebP and no larger than 340 × 340 pixels. The SVG
sources for the three native graphics are under `artwork/modern-flat/` and are
excluded from the app's runtime asset bundle.

The illustrations follow the first-version give picture's friendly flat style.
New vocabulary includes dressing and washing, cleaning and laundry, school and
kitchen objects, body parts, seasons, time words, places and actions. Semantic
review qualifies ambiguous labels, including **plane (geometry)**, **iron
(metal)**, **throwing beanbag** and **dishwashing worker**. The running figure is
assigned to **hurry**, the person pointing at a watch to **now**, and **whisk**
uses an actual kitchen-whisk picture. This keeps common homonyms from being
silently assigned unrelated pictures.

The authoritative completion counters are in
`modern-flat-expansion-progress.json`; approved image details, original source
paths, full prompts, generator type and checksums are in
`modern-flat-expansion-assets.json`. The full 6,736-addition planning catalog is
`modern-flat-expansion-jobs.json`, with category totals in
`modern-flat-expansion-plan.json`. The catalog is planning data, not 6,736
finished pictures.

WordNet 3.0 definitions supplied by the NLTK project help disambiguate vocabulary
meanings. The definition-data checksum is recorded in the plan. WordNet's
complete notice is included as `assets/flat_symbols/LICENSE-WordNet.txt`.
Sources: https://www.nltk.org/howto/wordnet.html and
https://wordnet.princeton.edu/license-and-commercial-use . Illustrations are
original app artwork; WordNet is not an image source.

## Current generation limit

The built-in generator returned HTTP 429 `usage_limit_reached`. Its reported
reset is **November 2, 2026, 2:35 p.m. America/New_York** (19:35 UTC).
The remaining jobs and per-image receipts are preserved in
`../work/modern_flat_expansion/`; the queue is blocked from issuing further
built-in generation requests before the reported reset. No separately billed
API fallback has been started.

The CLI/API fallback exists and requires a separately configured
`OPENAI_API_KEY` and explicit user opt-in. It is not automatically substituted
for the built-in tool. API credentials must never be pasted into chat or saved
in these artwork files.

## Resume and review

`python tools/expand_modern_flat.py progress` reports actual completed files.
The SQLite queue leases each planned job once; successful built-in generation
calls save one JSON receipt per asset. `stage` exports the generated originals
as bounded WebP. `sheet` creates labeled review sheets and a JSON sidecar with
the exact keys shown on each page. Only visually checked keys are passed to
`approve`; it then updates the app index, artwork manifest and real counters.

The generator prompt requests one clear modern flat AAC subject, only necessary
props, friendly expressive people, accurate natural object colors, natural
hands, transparent background, full-subject margin, no 3D rendering, no collage,
no labels or watermark, and readability at 340 pixels. Each concept has its own
scene specification. The original give image is supplied as a style reference.

## Validation and packages

All 33 Flutter tests pass and Flutter analysis reports no issues. Every Android
and Windows WebP matches the source manifest by SHA256. Both packages exclude
the original 3D/source collections. Signed Android, Windows x64, the complete
3,374-picture modern flat set and the 110-picture expansion-only archive are
in `dist/v1.7.0/`. Artifact checksums are in
`modern-flat-expansion-build.json`. This is a reviewed partial expansion, not
completion of the 10,000-artwork target.
