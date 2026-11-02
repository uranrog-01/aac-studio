"""Render every indexed symbol and flag ones without real artwork or a usable name.

Checks each picture at 96 px: fails to load, empty (almost no painted pixels),
or a single flat colour (placeholder box). Names are flagged when they are
codes rather than words. Writes docs/artwork-audit.json.

Needs Pillow and resvg-py. Usage: python tools/audit_artwork.py
"""
import io
import json
import re
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SVG_PACKS = {'openmoji', 'openmoji_black', 'mulberry', 'communication', 'twemoji_svg'}


def asset(pack, key):
    if pack == 'mulberry':
        return ROOT / 'assets/symbols/mulberry' / f'{key}.svg'
    folder = 'twemoji' if pack == 'twemoji_svg' else 'modernflat' if pack == 'modern3d' else pack
    return ROOT / 'assets/flat_symbols' / folder / f'{key}.webp'


def check(item):
    from PIL import Image
    import resvg_py
    pack, key = item
    path = asset(pack, key)
    try:
        if path.suffix == '.svg':
            png = resvg_py.svg_to_bytes(svg_string=path.read_text(encoding='utf8'),
                                        width=96, height=96)
            im = Image.open(io.BytesIO(bytes(png))).convert('RGBA')
        else:
            im = Image.open(path).convert('RGBA').resize((96, 96))
    except Exception as e:  # noqa: BLE001 - report every failure
        return pack, key, f'does not load: {e.__class__.__name__}'
    alpha = im.getchannel('A')
    painted = sum(1 for a in alpha.getdata() if a > 32)
    if painted < 96 * 96 * 0.01:
        return pack, key, 'empty (no artwork)'
    # As shown on a button: a placeholder box or blank shape has no contrast.
    from PIL import ImageStat
    shown = Image.alpha_composite(Image.new('RGBA', im.size, 'white'), im).convert('L')
    if ImageStat.Stat(shown).stddev[0] < 4:
        return pack, key, 'no visible drawing'
    bbox = alpha.point(lambda a: 255 if a > 32 else 0).getbbox()
    box = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]) if bbox else 0
    inner = shown.crop(bbox) if bbox else shown
    if box >= 96 * 96 * 0.9 and ImageStat.Stat(inner).stddev[0] < 6:
        return pack, key, 'solid box placeholder'
    return None


CODE_NAME = re.compile(r'^(u?[0-9a-f]{4,6}([ _-]u?[0-9a-f]{4,6})*|e[0-9a-f]{3}|[0-9a-f]{4,}-.*)$', re.I)


def main():
    index = json.loads((ROOT / 'assets/symbol_index.json').read_text(encoding='utf8'))
    names = {}
    for e in index:
        names.setdefault((e['p'], e['k']), []).append(e['n'])
    with ProcessPoolExecutor() as pool:
        problems = [p for p in pool.map(check, names, chunksize=64) if p]
    bad_names = [(p, k, n) for (p, k), ns in names.items() for n in ns
                 if not n.strip() or CODE_NAME.match(n.strip())]
    report = {
        'pictures': len(names),
        'artwork_problems': [{'pack': p, 'key': k, 'problem': why} for p, k, why in problems],
        'code_names': [{'pack': p, 'key': k, 'name': n} for p, k, n in bad_names],
    }
    (ROOT / 'docs/artwork-audit.json').write_text(json.dumps(report, indent=1), encoding='utf8')
    by = {}
    for p, _, why in problems:
        by[(p, why)] = by.get((p, why), 0) + 1
    print(f'{len(names)} pictures checked; {len(problems)} without proper artwork; '
          f'{len(bad_names)} code-like names')
    for (p, why), n in sorted(by.items()):
        print(f'  {p:15} {why:30} {n}')


if __name__ == '__main__':
    main()
