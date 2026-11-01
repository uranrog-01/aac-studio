# Third-party symbol packs (bundled open-licensed assets)

Third-party collections under `assets/symbols/` retain their own licenses.
The original `communication/*.svg` pictograms and `learning/*.png` letter/number
cards are covered by AAC Studio's MIT license. Communication pictogram sources
are in `tools/repair_symbol_meanings.py`.
Index names come from Unicode CLDR English annotations (Unicode License).

The `modern3d/` starter set combines Microsoft Fluent Emoji 3D PNGs (MIT;
Copyright Microsoft Corporation, pinned revision
`1ffb34c752ecf5d402f04cfb4b392c77f57c54bc`) with 56 original generated action
and object illustrations, plus original rendered letter/number and color cards.
Microsoft's complete notice is bundled as `modern3d/LICENSE-Microsoft.txt`.
The original illustrations and cards use the app's MIT license. Source paths,
generation briefs, assignments and checksums are in
`docs/modern-symbol-manifest.json`; importer: `tools/modernize_symbols.py`.
The original letter/number cards are rendered with the Windows Segoe UI font;
no font software is redistributed.

| Pack | Directory | Source | Count | License | Attribution requirement |
|---|---|---|---|---|---|
| Twemoji (PNG 72) | `twemoji/*.png` | github.com/jdecked/twemoji v15.1.0 | 3,838 | CC-BY 4.0 | Keep this file; credit "Twemoji by Twitter, maintained by jdecked" |
| Twemoji (SVG) | `twemoji/*.svg` | same | 3,838 | CC-BY 4.0 | same |
| Noto Emoji | `noto/*.png` | github.com/googlefonts/noto-emoji | 4,054 | Apache-2.0 | Keep this file |
| OpenMoji (color) | `openmoji/*.svg` | github.com/hfg-gmuend/openmoji | 4,565 | CC BY-SA 4.0 | Credit "OpenMoji"; share-alike applies to the pack |
| OpenMoji (black) | `openmoji_black/*.svg` | same | 4,565 | CC BY-SA 4.0 | same |
| Mulberry | `mulberry/*.svg` | github.com/mulberrysymbols/mulberry-symbols | 3,436 | CC BY-SA 3.0 | Credit "Mulberry Symbols by Paul Beerr"; share-alike applies to the pack |
| CLDR names index | `symbol_index.json` | unicode.org/cldr (annotations en) | names | Unicode License | — |

**Not bundled (license or provenance reasons):**
- SymbolStix / Proloquo2Go assets — proprietary (N2Y LLC); never include them.
- ARASAAC pictograms — CC BY-NC-SA (non-commercial): add them as an optional
  runtime-downloaded pack for non-commercial use only; do not commit them here.

Totals: 24,898 searchable symbol names, including aliases. The modern starter
set uses 417 unique PNGs: 301 Fluent Emoji, 56 generated illustrations, 49
letter/number cards and 11 color indicators. Legacy packs remain available.
