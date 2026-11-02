"""Shrink bundled raster symbols without changing what anyone sees.

- modern3d, noto, learning: PNG -> lossless WebP (identical pixels). Pictures
  wider than 512 px are first resized to 512, the largest size a button shows.
- twemoji: the 72 px PNG copies are deleted; the app draws the same Twemoji
  from its SVG, which is sharp at every size.

Idempotent. Usage: python tools/compress_symbols.py
"""
import hashlib
import json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SYMBOLS = ROOT / 'assets/symbols'
MAX_SIDE = 512


def convert(png):
    im = Image.open(png).convert('RGBA')
    if max(im.size) > MAX_SIDE:
        im = im.resize((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    out = png.with_suffix('.webp')
    im.save(out, 'WEBP', lossless=True, quality=100, method=6, exact=True)
    if Image.open(out).convert('RGBA').tobytes() != im.tobytes():
        raise ValueError(f'lossless round-trip changed pixels: {png}')
    png.unlink()
    return out.stat().st_size


def main():
    pngs = [p for pack in ('modern3d', 'noto', 'learning') for p in (SYMBOLS / pack).glob('*.png')]
    with ProcessPoolExecutor() as pool:
        sizes = list(pool.map(convert, pngs, chunksize=32))
    removed = 0
    for png in (SYMBOLS / 'twemoji').glob('*.png'):
        if png.with_suffix('.svg').exists():
            png.unlink()
            removed += 1
    # The 3D manifest records hashes of the shipped files.
    manifest_path = ROOT / 'docs/modern-symbol-manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf8'))
    manifest['files'] = {p.stem: hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in sorted((SYMBOLS / 'modern3d').glob('*.webp'))}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n',
                             encoding='utf8')
    print(f'{len(pngs)} PNG -> lossless WebP ({sum(sizes) / 1e6:.1f} MB); '
          f'{removed} Twemoji PNG duplicates removed')


if __name__ == '__main__':
    main()
