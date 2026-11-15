"""Board v18: the Games page gets 8 new games and loses two.

New satisfying games (kinetic sand, soap cutting, water beads, pressure
wash, swinging balls) and calm-down scenes (light tunnel, northern lights,
jellyfish). "Tap and hear" and "match pairs" are removed, also from boards
already installed (factory history 'retired'). Pictures are drawn here.
Run once from studio: python tools/add_games_v18.py
"""
import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
from add_games_v16 import FLAT, HISTORY, INDEX, MANIFEST, PACK, ROOT, S, canvas, webp  # noqa: E402


def shadow(image, box, blur=16, alpha=70):
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=(0, 0, 0, alpha))
    return Image.alpha_composite(image, layer.filter(ImageFilter.GaussianBlur(blur)))


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


def kinetic_sand():
    image, d = canvas()
    image = shadow(image, [70, 470, 610, 600])
    d = ImageDraw.Draw(image)
    pink = (247, 166, 193)
    # Block: top face and front face, with a clean cut through it.
    for x0, x1 in ((90, 318), (352, 590)):
        d.polygon([(x0, 260), (x1, 260), (x1 - 30, 380), (x0 - 30, 380)], fill=shade(pink, 1.12))
        d.polygon([(x0 - 30, 380), (x1 - 30, 380), (x1 - 30, 520), (x0 - 30, 520)], fill=shade(pink, 0.88))
    d.polygon([(318, 260), (318, 400), (288, 520), (288, 380)], fill=shade(pink, 0.7))
    # Grain.
    import random
    r = random.Random(4)
    for _ in range(2600):
        x, y = r.randint(60, 600), r.randint(260, 520)
        if image.getpixel((x, y))[3] > 0:
            v = r.choice([0.9, 1.08])
            d.point((x, y), fill=shade(image.getpixel((x, y)), v))
    for cx, cy, rr in [(330, 230, 14), (360, 200, 9), (300, 205, 7)]:
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=shade(pink, 1.0))
    return webp(image)


def soap():
    image, d = canvas()
    image = shadow(image, [60, 500, 620, 620])
    d = ImageDraw.Draw(image)
    layers = [(248, 187, 208), (255, 245, 157), (179, 229, 252)]
    h = 70
    for i, c in enumerate(layers):
        y0 = 470 - (i + 1) * h
        d.polygon([(70, y0 + h), (380, y0 + h), (380, y0), (70, y0)], fill=shade(c, 0.95))
        d.polygon([(380, y0 + h), (440, y0 + h - 50), (440, y0 - 50), (380, y0)], fill=shade(c, 0.78))
    top = layers[-1]
    d.polygon([(70, 260), (380, 260), (440, 210), (130, 210)], fill=shade(top, 1.12))
    # Cubes tumbling off the end.
    for i, (x, y) in enumerate([(470, 420), (540, 470), (500, 520), (575, 395)]):
        c = layers[i % 3]
        s = 52
        d.polygon([(x, y), (x + s, y), (x + s, y + s), (x, y + s)], fill=shade(c, 0.95))
        d.polygon([(x, y), (x + s, y), (x + s + 18, y - 14), (x + 18, y - 14)], fill=shade(c, 1.12))
        d.polygon([(x + s, y), (x + s + 18, y - 14), (x + s + 18, y + s - 14), (x + s, y + s)], fill=shade(c, 0.75))
    # Knife.
    d.polygon([(430, 70), (470, 70), (420, 300), (400, 300)], fill=(225, 230, 236, 255))
    d.rounded_rectangle([425, 20, 480, 90], radius=14, fill=(110, 76, 60, 255))
    return webp(image)


def beads():
    image, d = canvas()
    image = shadow(image, [80, 520, 600, 630])
    colours = [(255, 143, 177), (127, 209, 255), (156, 245, 154), (255, 224, 122), (197, 155, 255), (255, 179, 122)]
    import random
    r = random.Random(9)
    balls = []
    for row in range(5):
        for k in range(7 - row):
            x = 130 + k * 72 + row * 36 + r.randint(-6, 6)
            y = 540 - row * 64 + r.randint(-5, 5)
            balls.append((x, y, r.choice(colours)))
    for x, y, c in balls:
        rad = 38
        ball = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        bd = ImageDraw.Draw(ball)
        for s in range(rad, 0, -2):
            f = 0.62 + 0.55 * (1 - s / rad)
            bd.ellipse([x - s, y - s, x + s, y + s], fill=shade(c, f))
        bd.ellipse([x - 22, y - 26, x - 4, y - 14], fill=(255, 255, 255, 230))
        bd.arc([x - 26, y - 22, x + 26, y + 30], 20, 150, fill=(255, 255, 255, 110), width=5)
        image = Image.alpha_composite(image, ball)
    return webp(image)


def wash():
    image, d = canvas()
    d.rounded_rectangle([40, 40, S - 40, S - 40], radius=50, fill=(92, 74, 50, 255))
    # Clean stripe: bright tiles where the water has been.
    stripe = Image.new('L', (S, S), 0)
    ImageDraw.Draw(stripe).polygon([(40, 380), (380, 40), (520, 40), (40, 520)], fill=255)
    clean = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(clean)
    for y in range(40, S - 40, 100):
        for x in range(40, S - 40, 100):
            cd.rounded_rectangle([x + 4, y + 4, x + 96, y + 96], radius=8, fill=(230, 222, 208, 255))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=50, fill=255)
    from PIL import ImageChops
    image.paste(clean, (0, 0), ImageChops.multiply(stripe, mask))
    d = ImageDraw.Draw(image)
    # Nozzle and spray.
    d.line([(640, 660), (470, 300)], fill=(38, 50, 56, 255), width=30)
    d.line([(470, 300), (450, 255)], fill=(255, 193, 7, 255), width=40)
    spray = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(spray).polygon([(440, 240), (250, 200), (300, 330)], fill=(227, 246, 255, 170))
    image = Image.alpha_composite(image, spray.filter(ImageFilter.GaussianBlur(4)))
    return webp(image)


def cradle():
    image, d = canvas()
    d.rounded_rectangle([60, 560, 620, 620], radius=18, fill=(120, 76, 50, 255))
    for x in (110, 570):
        d.line([(x, 120), (x, 565)], fill=(190, 196, 204, 255), width=16)
    d.line([(110, 120), (570, 120)], fill=(225, 230, 236, 255), width=16)
    centres = [(170, 300), (290, 440), (360, 440), (430, 440), (500, 440)]
    pivots = [250, 290, 360, 430, 500]
    for (cx, cy), px in zip(centres, pivots):
        d.line([(px - 22, 125), (cx, cy - 40)], fill=(230, 230, 230, 255), width=3)
        d.line([(px + 22, 125), (cx, cy - 40)], fill=(230, 230, 230, 255), width=3)
    for cx, cy in centres:
        rad = 36
        for s in range(rad, 0, -1):
            t = s / rad
            v = int(70 + 170 * (1 - t) ** 0.6)
            d.ellipse([cx - s, cy - s, cx + s, cy + s], fill=(v, v + 4, v + 10, 255))
        d.ellipse([cx - 20, cy - 24, cx - 4, cy - 12], fill=(255, 255, 255, 255))
    return webp(image)


def tunnel():
    image, d = canvas()
    for i in range(60, 0, -1):
        t = i / 60
        hue = (t * 0.9 + 0.55) % 1.0
        r = int(128 + 110 * math.cos(6.283 * (hue + 0.0)))
        g = int(128 + 110 * math.cos(6.283 * (hue + 0.33)))
        b = int(150 + 100 * math.cos(6.283 * (hue + 0.67)))
        rad = int(40 + 270 * t)
        d.ellipse([S / 2 - rad, S / 2 - rad, S / 2 + rad, S / 2 + rad], fill=(r, g, b, 255))
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([S / 2 - 90, S / 2 - 90, S / 2 + 90, S / 2 + 90], fill=(255, 245, 225, 255))
    image = Image.alpha_composite(image, glow.filter(ImageFilter.GaussianBlur(30)))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse([30, 30, S - 30, S - 30], fill=255)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(image, (0, 0), mask)
    return webp(out)


def aurora():
    image, d = canvas()
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([30, 60, S - 30, S - 60], radius=60, fill=255)
    sky = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sky)
    for y in range(60, S - 60):
        t = (y - 60) / (S - 120)
        sd.line([(30, y), (S - 30, y)], fill=(int(5 + 20 * t), int(10 + 40 * t), int(35 + 50 * t), 255))
    curtain = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(curtain)
    for x in range(30, S - 30, 3):
        base = 330 + 60 * math.sin(x / 70) + 20 * math.sin(x / 23)
        top = base - 170 - 40 * math.sin(x / 41)
        cd.line([(x, top), (x, base)], fill=(60, 240, 150, 150), width=3)
    sky = Image.alpha_composite(sky, curtain.filter(ImageFilter.GaussianBlur(7)))
    sd = ImageDraw.Draw(sky)
    import random
    r = random.Random(3)
    for _ in range(60):
        x, y = r.randint(40, S - 40), r.randint(70, 260)
        sd.ellipse([x, y, x + 3, y + 3], fill=(255, 255, 255, 220))
    sd.polygon([(30, 480), (160, 360), (250, 440), (360, 330), (470, 450), (560, 380), (650, 470),
                (650, S - 60), (30, S - 60)], fill=(12, 20, 30, 255))
    image.paste(sky, (0, 0), mask)
    return webp(image)


GAMES = [
    # id, label, key, draw, section
    ('kineticsand', 'kinetic sand', 'vocab-kinetic-sand', kinetic_sand),
    ('soap', 'soap cutting', 'vocab-soap-cutting', soap),
    ('beads', 'water beads', 'vocab-water-beads', beads),
    ('wash', 'pressure wash', 'vocab-pressure-wash', wash),
    ('cradle', 'swinging balls', 'vocab-swinging-balls', cradle),
    ('tunnel', 'light tunnel', 'vocab-light-tunnel', tunnel),
    ('aurora', 'northern lights', 'vocab-northern-lights', aurora),
    ('jellyfish', 'jellyfish', 'fluent-jellyfish', None),
]
RETIRED = ['game_hear', 'game_pairs']
SATISFYING_FIRST = ['kineticsand', 'soap', 'beads', 'wash', 'cradle']
CALM = ['tunnel', 'aurora', 'jellyfish']


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    if pack['packVersion'] >= 18:
        raise SystemExit('Board is already v18.')
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    index = json.loads(INDEX.read_text(encoding='utf8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    view = pack['views']['games'][0]
    view['cells'] = [c for c in view['cells'] if c['btn'] not in RETIRED]
    pack['buttons'] = [b for b in pack['buttons'] if b['id'] not in RETIRED]
    retired = history.setdefault('retired', {})
    retired['games'] = sorted(set(retired.get('games', [])) | set(RETIRED))
    new = {}
    for game, label, key, draw in GAMES:
        if draw is not None:
            data = draw()
            (FLAT / f'{key}.webp').write_bytes(data)
            manifest['files'][f'modernflat/{key}.webp'] = hashlib.sha256(data).hexdigest()
            manifest.setdefault('composedPictures', {})[key] = {
                'label': label, 'from': ['drawn by tools/add_games_v18.py']}
            index.append({'p': 'modernflat', 'k': key, 'n': label})
        assert (FLAT / f'{key}.webp').exists(), key
        button = {'id': f'game_{game}', 'kind': 'action', 'label': label, 'class': 'other',
                  'symbol': '🎮', 'symbolPack': 'modernflat', 'symbolKey': key,
                  'actions': [{'kind': 'sensoryGames', 'data': game}]}
        assert button['id'] not in buttons, button['id']
        buttons[button['id']] = button
        pack['buttons'].append(button)
        history['buttons'][button['id']] = [
            {k: button[k] for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}]
        new[game] = {'btn': button['id']}
    view['cells'] = ([new[g] for g in SATISFYING_FIRST] + view['cells'] +
                     [new[g] for g in CALM])
    labels, pictures = set(), set()
    for c in view['cells']:
        b = buttons[c['btn']]
        assert b['label'] not in labels and (b['symbolPack'], b['symbolKey']) not in pictures, b['label']
        labels.add(b['label'])
        pictures.add((b['symbolPack'], b['symbolKey']))
    flat = ROOT / 'assets/flat_symbols/modernflat'
    manifest['fileCount'] = len(manifest['files'])
    manifest['counts']['modernflat'] = len(list(flat.glob('*.webp')))
    manifest['indexNames'] = len(index)
    manifest['uniqueIndexedPictures'] = len({(e['p'], e['k']) for e in index})
    manifest['bytes'] = sum(p.stat().st_size for p in (ROOT / 'assets/flat_symbols').glob('*/*.webp'))
    pack['packVersion'] = 18
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    INDEX.write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    print('Games page:', ', '.join(buttons[c['btn']]['label'] for c in view['cells']))


if __name__ == '__main__':
    main()
