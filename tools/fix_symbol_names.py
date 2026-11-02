"""Give every indexed picture a real word name and drop pictures without artwork.

- Code-like names (e.g. "e002", "1f1e6") get the OpenMoji/CLDR annotation for the
  same hexcode, else a hand-written name below (checked by looking at each picture),
  else the Unicode character name.
- Removes index rows (and files) whose artwork is empty or unsuitable for children.
- Crops Mulberry SVGs whose artwork sits tiny inside a huge canvas.

Usage: python tools/fix_symbol_names.py <dir with openmoji*.json from the OpenMoji npm package>
"""
import io
import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / 'assets/symbol_index.json'
SYMBOLS = ROOT / 'assets/symbols'

# OpenMoji extras missing from every published openmoji.json (named by sight).
MANUAL = {
    'E06E': 'video call', 'E06F': 'tree logo', 'E070': 'blue butterfly',
    'E0CD': 'brown bottle', 'E0CE': 'salt shaker', 'E0CF': 'pepper mill',
    'E0D0': 'salt mill', 'E14B': 'sneaker', 'E14C': 'high top sneaker',
    'E14D': '3D printer', 'E14E': 'open frame 3D printer', 'E14F': 'snorkel mask',
    'E158': 'electric fan', 'E159': 'bike helmet', 'E15A': 'person with VR headset',
    'E15B': 'wooden stool', 'E15C': 'slide sandal', 'E15D': 'table football player white',
    'E15E': 'table football player black', 'E15F': 'rubber duck',
    'E160': 'rubber duck in water', 'E161': 'electric charging station',
    'E162': 'waste basket', 'E163': 'desk lamp', 'E164': 'garden clog',
    'E165': 'water gun', 'E18A': 'pirate captain', 'E18B': 'dark helmet costume',
    'E18C': 'pirate man', 'E18D': 'pirate woman', 'E18E': 'pirate with sword',
    'E18F': 'pirate with hook', 'E190': 'person figure', 'E191': 'person figure with ponytail',
    'E1DA': 'open hand', 'E1DB': 'calculator', 'E217': 'old town building',
    'E218': 'cargo bike', 'E219': 'sinking ship', 'E21A': 'submarine',
    'E21B': 'submarine under water', 'E21C': 'lake monster',
    'E420': 'intersex inclusive pride flag', 'E421': 'lesbian flag',
    'E422': 'gay men flag', 'E423': 'bisexual flag', 'E424': 'pansexual flag',
    'E425': 'asexual flag', 'E426': 'demisexual flag', 'E427': 'greysexual flag',
    'E428': 'polysexual flag', 'E429': 'aroace flag', 'E42A': 'aromantic flag',
    'E42B': 'polyamory flag', 'E42D': 'intersex flag', 'E42E': 'nonbinary flag',
    'E42F': 'genderfluid flag', 'E430': 'genderqueer flag', 'E431': 'agender flag',
    'E432': 'demigirl flag', 'E433': 'demiboy flag', 'E434': 'demigender flag',
    'E435': 'genderflux flag', 'E50A': '109 tower building',
}
# Empty upstream artwork, or not suitable for a children's AAC app.
REMOVE = {('openmoji_black', '1F195'), ('openmoji', 'E42C'), ('openmoji_black', 'E42C')}
CROP = ['cream', 'sour_cream']

CODE_NAME = re.compile(r'^(u?[0-9a-f]{4,6}([ _-]u?[0-9a-f]{4,6})*|e[0-9a-f]{3})$', re.I)


def hexcode(key):
    parts = key.lower().replace('emoji_u', '').replace('_', '-').split('-')
    return '-'.join(p.lstrip('u').upper() for p in parts if p)


def unicode_name(key):
    try:
        return ' '.join(unicodedata.name(chr(int(p, 16))) for p in hexcode(key).split('-')
                        if p not in ('FE0F', '200D')).lower()
    except ValueError:
        return None


def crop_svg(path):
    """Shrink the viewBox to the drawn artwork plus a 6% margin."""
    from PIL import Image
    import resvg_py
    svg = path.read_text(encoding='utf8')
    m = re.search(r'viewBox="([\d.\s-]+)"', svg)
    x0, y0, w, h = map(float, m.group(1).split())
    px = 2048
    im = Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=px, height=px))))
    left, top, right, bottom = im.getchannel('A').getbbox()
    sx, sy = w / px, h / px
    bw, bh = (right - left) * sx, (bottom - top) * sy
    side = max(bw, bh) * 1.12
    cx, cy = x0 + (left + right) / 2 * sx, y0 + (top + bottom) / 2 * sy
    box = f'{cx - side / 2:.2f} {cy - side / 2:.2f} {side:.2f} {side:.2f}'
    svg = svg.replace(m.group(0), f'viewBox="{box}"', 1)
    svg = re.sub(r'(<svg[^>]*?)\swidth="[^"]*"', r'\1', svg, count=1)
    svg = re.sub(r'(<svg[^>]*?)\sheight="[^"]*"', r'\1', svg, count=1)
    path.write_text(svg, encoding='utf8')


def main():
    names = {}
    for f in sorted(Path(sys.argv[1]).glob('openmoji*.json')):
        for e in json.loads(f.read_text(encoding='utf8')):
            names.setdefault(e['hexcode'].upper(), e['annotation'])
    index = json.loads(INDEX.read_text(encoding='utf8'))
    renamed = 0
    kept = []
    for e in index:
        if (e['p'], e['k']) in REMOVE:
            continue
        if CODE_NAME.match(e['n'].strip()) and not (e['p'] == 'mulberry' and e['n'] == 'dead'):
            code = hexcode(e['k'])
            e['n'] = MANUAL.get(code) or names.get(code) or unicode_name(e['k']) or e['n']
            renamed += 1
        kept.append(e)
    # Skin-tone variants carry Unicode jargon when CLDR names are missing.
    for e in kept:
        e['n'] = (e['n'].replace('emoji modifier fitzpatrick type-1-2', 'light skin tone')
                  .replace('emoji modifier fitzpatrick type-3', 'medium-light skin tone')
                  .replace('emoji modifier fitzpatrick type-4', 'medium skin tone')
                  .replace('emoji modifier fitzpatrick type-5', 'medium-dark skin tone')
                  .replace('emoji modifier fitzpatrick type-6', 'dark skin tone'))
    for pack, key in REMOVE:
        (SYMBOLS / pack / f'{key}.svg').unlink(missing_ok=True)
    for key in CROP:
        crop_svg(SYMBOLS / 'mulberry' / f'{key}.svg')
    INDEX.write_text(json.dumps(kept, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    print(f'renamed {renamed}, removed {len(index) - len(kept)} rows, cropped {len(CROP)}')


if __name__ == '__main__':
    main()
