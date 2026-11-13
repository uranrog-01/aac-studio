"""Board v16: six more games in the Games category.

Satisfying games first (pop it, slime, sand, paint swirl), then two
nonverbal picture games (tap and hear, match pairs). Their pictures are
drawn here. Run once from studio: python tools/add_games_v16.py
"""
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
FLAT = ROOT / 'assets/flat_symbols/modernflat'
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'
INDEX = ROOT / 'assets/symbol_index.json'
MANIFEST = ROOT / 'docs/flat-symbol-manifest.json'
S = 680


def webp(image):
    out = io.BytesIO()
    image.resize((340, 340), Image.LANCZOS).save(out, 'WEBP', lossless=True, method=6, exact=True)
    return out.getvalue()


def canvas():
    image = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def popit():
    image, d = canvas()
    rows = [(239, 83, 80), (255, 167, 38), (255, 213, 79), (102, 187, 106), (66, 165, 245), (149, 117, 205)]
    d.rounded_rectangle([40, 40, S - 40, S - 40], radius=110, fill=(240, 240, 240, 255))
    band = (S - 80) / 6
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=110, fill=255)
    bands = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bands)
    for r, colour in enumerate(rows):
        bd.rectangle([40, 40 + r * band, S - 40, 40 + (r + 1) * band], fill=colour + (255,))
    image.paste(bands, (0, 0), mask)
    d = ImageDraw.Draw(image)
    for r, colour in enumerate(rows):
        for c in range(6):
            x, y = 40 + band * (c + 0.5), 40 + band * (r + 0.5)
            rad = band * 0.36
            pressed = (r + c) % 4 == 0
            shade = tuple(int(v * (0.78 if pressed else 1.0)) for v in colour)
            d.ellipse([x - rad, y - rad + 4, x + rad, y + rad + 4], fill=(0, 0, 0, 50))
            d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=shade + (255,))
            if not pressed:
                d.ellipse([x - rad * 0.55, y - rad * 0.6, x - rad * 0.05, y - rad * 0.25],
                          fill=(255, 255, 255, 150))
    return webp(image)


def slime():
    image, d = canvas()
    pts = []
    for i in range(120):
        a = i / 120 * 2 * math.pi
        r = 230 + 26 * math.sin(3 * a + 0.6) + 14 * math.sin(5 * a)
        pts.append((S / 2 + math.cos(a) * r, S / 2 + 20 + math.sin(a) * r * 0.78))
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + 22) for x, y in pts], fill=(0, 0, 0, 70))
    image = Image.alpha_composite(image, shadow.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(image)
    d.polygon(pts, fill=(61, 220, 151, 255))
    d.ellipse([190, 170, 330, 230], fill=(220, 255, 238, 200))
    for x, y, r in [(400, 330, 16), (300, 380, 10), (450, 420, 12), (230, 320, 8), (360, 450, 9)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 110))
    return webp(image)


def sand():
    image, d = canvas()
    colours = [(240, 98, 146), (255, 183, 77), (129, 199, 132), (100, 181, 246), (186, 104, 200)]
    base = S - 70
    for k, colour in enumerate(colours):
        h = 360 - k * 60
        w = 560 - k * 70
        d.polygon([(S / 2 - w / 2, base - k * 18), (S / 2, base - h), (S / 2 + w / 2, base - k * 18)],
                  fill=colour + (255,))
    for x in range(S // 2 - 6, S // 2 + 7, 4):
        for y in range(30, 300, 9):
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 210, 120, 255))
    return webp(image)


def swirl():
    image, d = canvas()
    d.ellipse([30, 30, S - 30, S - 30], fill=(241, 234, 219, 255))
    colours = [(31, 111, 178), (242, 179, 61), (217, 72, 95), (47, 166, 127), (106, 76, 147)]
    for k in range(5, 0, -1):
        colour = colours[k - 1]
        pts = []
        for i in range(200):
            a = i / 200 * 2 * math.pi
            r = 48 * k + 18 * math.sin(4 * a + k)
            twist = a + 0.0035 * r * math.sin(a * 2)
            pts.append((S / 2 + math.cos(twist) * r, S / 2 + math.sin(twist) * r))
        d.polygon(pts, fill=colour + (255,))
    return webp(image)


def pairs():
    image, d = canvas()
    for x0, angle, front in [(70, -9, False), (300, 8, True)]:
        card = Image.new('RGBA', (300, 420), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        if front:
            cd.rounded_rectangle([6, 6, 294, 414], radius=36, fill=(255, 255, 255, 255),
                                 outline=(67, 160, 71, 255), width=14)
            cd.ellipse([80, 120, 220, 260], fill=(255, 202, 40, 255))
            cd.polygon([(150, 300), (110, 350), (190, 350)], fill=(239, 83, 80, 255))
        else:
            cd.rounded_rectangle([6, 6, 294, 414], radius=36, fill=(63, 111, 216, 255),
                                 outline=(255, 255, 255, 255), width=10)
            star = [(150 + math.cos(math.radians(-90 + i * 36)) * (70 if i % 2 == 0 else 30),
                     210 + math.sin(math.radians(-90 + i * 36)) * (70 if i % 2 == 0 else 30))
                    for i in range(10)]
            cd.polygon(star, fill=(255, 255, 255, 200))
        card = card.rotate(angle, expand=True, resample=Image.BICUBIC)
        image.alpha_composite(card, (x0, 100))
    return webp(image)


# game id, board word, picture key (drawn here unless it is an existing file)
GAMES = [
    ('popit', 'pop it', 'vocab-pop-it', popit),
    ('slime', 'slime', 'vocab-slime', slime),
    ('sand', 'sand', 'vocab-sand-art', sand),
    ('marbling', 'paint swirl', 'vocab-paint-swirl', swirl),
    ('hear', 'tap and hear', 'fluent-speaking-head', None),
    ('pairs', 'match pairs', 'vocab-match-pairs', pairs),
]


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    if pack['packVersion'] >= 16:
        raise SystemExit('Board is already v16.')
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    index = json.loads(INDEX.read_text(encoding='utf8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    cells = pack['views']['games'][0]['cells']
    satisfying = []
    for game, label, key, draw in GAMES:
        if draw is not None:
            data = draw()
            (FLAT / f'{key}.webp').write_bytes(data)
            manifest['files'][f'modernflat/{key}.webp'] = hashlib.sha256(data).hexdigest()
            manifest.setdefault('composedPictures', {})[key] = {
                'label': label, 'from': ['drawn by tools/add_games_v16.py']}
            index.append({'p': 'modernflat', 'k': key, 'n': label})
        assert (FLAT / f'{key}.webp').exists(), key
        button = {'id': f'game_{game}', 'kind': 'action', 'label': label, 'class': 'other',
                  'symbol': '🎮', 'symbolPack': 'modernflat', 'symbolKey': key,
                  'actions': [{'kind': 'sensoryGames', 'data': game}]}
        assert button['id'] not in buttons
        buttons[button['id']] = button
        pack['buttons'].append(button)
        history['buttons'][button['id']] = [
            {k: button[k] for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}]
        if game in ('hear', 'pairs'):
            cells.append({'btn': button['id']})
        else:
            satisfying.append({'btn': button['id']})
    # The satisfying games lead the page.
    pack['views']['games'][0]['cells'] = satisfying + cells
    labels, pictures = set(), set()
    for c in pack['views']['games'][0]['cells']:
        b = buttons[c['btn']]
        assert b['label'] not in labels and (b['symbolPack'], b['symbolKey']) not in pictures, b['label']
        labels.add(b['label'])
        pictures.add((b['symbolPack'], b['symbolKey']))
    manifest['fileCount'] = len(manifest['files'])
    manifest['counts']['modernflat'] = len(list(FLAT.glob('*.webp')))
    manifest['indexNames'] = len(index)
    manifest['uniqueIndexedPictures'] = len({(e['p'], e['k']) for e in index})
    manifest['bytes'] = sum(p.stat().st_size for p in (ROOT / 'assets/flat_symbols').glob('*/*.webp'))
    pack['packVersion'] = 16
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    INDEX.write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    print(f"Games has {len(pack['views']['games'][0]['cells'])} games")


if __name__ == '__main__':
    main()
