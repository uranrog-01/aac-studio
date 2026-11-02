# Smaller symbols, real artwork, and what is missing (v1.5.2)

## Smaller download, same pictures

| Picture set | Before | After | How |
|---|---|---|---|
| 3D (417) | 79.3 MB PNG | 13.8 MB | Lossless WebP. The 56 pictures at 1254 px were resized to 512 px, the largest size a button shows. |
| Noto (4,054) | 66.2 MB PNG | 47.6 MB | Lossless WebP: identical pixels |
| Numbers (21) | PNG | WebP | Lossless |
| Twemoji (3,838) | 72 px PNG + SVG | SVG only | The blurry PNG copies were removed. The app now draws the sharp SVG. |
| Native code | arm64, arm32, x86_64 | arm64, arm32 | x86_64 is only for PC emulators and some Chromebooks |

Proloquo2Go 2.3 for comparison: 14,186 symbols at 151×128 px, 7.8 KB each, 111 MB in total, and a 384 MB app.
Its symbols are small and blur on modern tablets. AAC Studio keeps 256–512 px (raster) or vector (SVG) pictures.

Rerun with `python tools/compress_symbols.py` (idempotent).

## Every picture has artwork and a word name

`python tools/audit_artwork.py` renders all pictures and flags pictures that are empty or show only a blank box.

- Mulberry "cream" and "sour cream" had their artwork tiny inside a huge canvas. They are now cropped.
- OpenMoji-black "new button" was empty upstream. It was removed (the colour version remains).
- An adult-themed flag was removed because it is unsuitable for a children's AAC app.
- 1,263 code-named pictures ("e002", "1f1e6") now have word names. Names come from OpenMoji/CLDR data, or were written by hand for 66 pictures after looking at them (`tools/fix_symbol_names.py`).

Result: 20,891 pictures, all with real artwork. Two remaining flags are correct ("yellow square", "white large square").

## What is missing

Proloquo2Go 2.3 has symbols for **12,688 distinct words**. AAC Studio has pictures for **1,408** of them.
AAC Studio's 20,891 pictures are mostly emoji (objects, food, animals, faces, flags), while AAC needs:

- core words: the, of, and, to, is, that, with, if, but
- pronouns: he, she, they, me, them
- everyday verbs: have, do, know, see, show, love
- describing words: big, small, new, old
- time and people words

1,250 missing words are among the 10,000 most common English words. They are listed most common first in
`docs/symbol-gaps.json`. No Proloquo2Go artwork was used; only the word list was compared.

Filling these needs real AAC artwork, not text tiles or empty pictures. ARASAAC (about 13,000 pictograms,
CC BY-NC-SA, non-commercial) covers most of these words. The app already searches it online. Bundling it offline
would add an estimated 60–100 MB as lossless WebP.
