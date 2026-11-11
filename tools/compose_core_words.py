"""Board v14: pictures for core words that had none.

No picture generator is used. Each picture is either artwork that was
already bundled but not used on the board, or a composite built here from
bundled artwork with one fixed visual grammar:

    the person speaking   the app's own "I" character
    him / her / they      a pointing hand or an arrow toward the face(s)
    mine / his / our ...  the person(s) with a teddy bear beside them
    these / those         a hand pointing at things near / far away

Composites are saved as modernflat/vocab-<word>.webp (340 x 340, transparent)
and recorded in docs/flat-symbol-manifest.json under "composedPictures".
Run once from studio: python tools/compose_core_words.py
"""
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
FLAT = ROOT / 'assets/flat_symbols/modernflat'
MULBERRY = ROOT / 'assets/symbols/mulberry'
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'
INDEX = ROOT / 'assets/symbol_index.json'
MANIFEST = ROOT / 'docs/flat-symbol-manifest.json'
S = 2  # drawn at double size, then reduced for smooth edges
BLUE = (30, 118, 210, 255)

SELF, BOY, GIRL, PERSON = 'scene-i', 'fluent-boy', 'fluent-girl', 'fluent-person'
TEDDY, APPLE, BALL = 'fluent-teddy-bear', 'fluent-red-apple', 'fluent-soccer-ball'
HAND_RIGHT = 'fluent-backhand-index-pointing-right'
HAND_DOWN = 'fluent-backhand-index-pointing-down'

# word: [(picture, x, y, size) ...] plus ('arrow', x1, y1, x2, y2) and
# ('unequal', cx, cy). Coordinates are on the 340 x 340 picture.
COMPOSED = {
    'me': [(SELF, 80, 80, 255), ('arrow', 20, 20, 105, 105)],
    'him': [(HAND_RIGHT, 0, 115, 135), (BOY, 140, 65, 195)],
    'her': [(HAND_RIGHT, 0, 115, 135), (GIRL, 140, 65, 195)],
    'they': [(BOY, 0, 105, 130), (GIRL, 105, 105, 130), (PERSON, 210, 105, 130)],
    'them': [(BOY, 0, 190, 120), (GIRL, 110, 190, 120), (PERSON, 220, 190, 120),
             ('arrow', 170, 15, 170, 165)],
    'us': [(SELF, 5, 120, 215), (GIRL, 185, 170, 150), ('arrow', 170, 10, 170, 110)],
    'mine': [(SELF, 0, 30, 235), (TEDDY, 195, 175, 145)],
    'his': [(BOY, 5, 25, 195), (TEDDY, 190, 175, 145)],
    'your': [('fluent-index-pointing-at-the-viewer', 5, 25, 200), (TEDDY, 190, 175, 145)],
    'our': [(SELF, 0, 10, 195), (GIRL, 165, 40, 135), (TEDDY, 105, 195, 140)],
    'their': [(BOY, 5, 10, 110), (GIRL, 115, 10, 110), (PERSON, 225, 10, 110),
              (TEDDY, 100, 165, 150)],
    'these': [(HAND_DOWN, 95, 0, 150), (APPLE, 20, 220, 100), (APPLE, 120, 220, 100),
              (APPLE, 220, 220, 100)],
    'those': [(HAND_RIGHT, 0, 175, 150), (APPLE, 185, 30, 62), (APPLE, 255, 30, 62),
              (APPLE, 220, 95, 62)],
    'have': [('fluent-palm-up-hand', 20, 95, 300), (BALL, 105, 30, 130)],
    'drop': [(BALL, 105, 10, 130), ('arrow', 170, 160, 170, 320)],
    'know': [(BOY, 10, 95, 235), ('fluent-light-bulb', 205, 5, 130)],
    'different': [('fluent-red-circle', 5, 105, 130), ('fluent-blue-square', 205, 105, 130),
                  ('unequal', 170, 170)],
    'new': [('fluent-wrapped-gift', 30, 85, 240), ('fluent-sparkles', 200, 5, 135)],
    'later': [('fluent-one-oclock', 5, 75, 190), ('arrow', 210, 170, 330, 170)],
}
# folder, label, word class, pack, key ('' = the composite for that label)
WORDS = [
    ('people', 'me', 'pronoun', 'modernflat', ''),
    ('people', 'him', 'pronoun', 'modernflat', ''),
    ('people', 'her', 'pronoun', 'modernflat', ''),
    ('people', 'us', 'pronoun', 'modernflat', ''),
    ('people', 'they', 'pronoun', 'modernflat', ''),
    ('people', 'them', 'pronoun', 'modernflat', ''),
    ('people', 'mine', 'pronoun', 'modernflat', ''),
    ('people', 'your', 'pronoun', 'modernflat', ''),
    ('people', 'his', 'pronoun', 'modernflat', ''),
    ('people', 'our', 'pronoun', 'modernflat', ''),
    ('people', 'their', 'pronoun', 'modernflat', ''),
    ('describe', 'these', 'pronoun', 'modernflat', ''),
    ('describe', 'those', 'pronoun', 'modernflat', ''),
    ('describe', 'different', 'adjective', 'modernflat', ''),
    ('describe', 'new', 'adjective', 'modernflat', ''),
    ('describe', 'with', 'preposition', 'modernflat', 'fluent-handshake'),
    ('describe', 'hard to do', 'adjective', 'modernflat', 'fluent-persevering-face'),
    ('describe', 'finished', 'adjective', 'modernflat', 'fluent-check-mark'),
    ('time', 'later', 'adverb', 'modernflat', ''),
    ('actions', 'have', 'verb', 'modernflat', ''),
    ('actions', 'drop', 'verb', 'modernflat', ''),
    ('actions', 'know', 'verb', 'modernflat', ''),
    ('actions', 'hide', 'verb', 'modernflat', 'fluent-see-no-evil-monkey'),
    ('actions', 'see', 'verb', 'modernflat', 'fluent-eye'),
    ('actions', 'climb', 'verb', 'modernflat', 'fluent-person-climbing'),
    ('actions', 'kick', 'verb', 'mulberry', 'kick_ball_1_,_to'),
    ('actions', 'close', 'verb', 'mulberry', 'close_,_to'),
    ('actions', 'keep', 'verb', 'mulberry', 'keep_,_to'),
    ('actions', 'fix', 'verb', 'mulberry', 'mend'),
    ('actions', 'win', 'verb', 'modernflat', 'fluent-trophy'),
    ('actions', 'buy', 'verb', 'modernflat', 'fluent-shopping-bags'),
    ('actions', 'throw', 'verb', 'modernflat', 'fluent-person-playing-handball'),
    ('actions', 'can', 'verb', 'modernflat', 'fluent-flexed-biceps'),
    ('feelings', 'feel', 'verb', 'modernflat', 'fluent-beating-heart'),
    ('feelings', 'shy', 'adjective', 'modernflat', 'fluent-face-with-peeking-eye'),
    ('feelings', 'lonely', 'adjective', 'modernflat', 'fluent-pensive-face'),
    ('feelings', 'proud', 'adjective', 'modernflat', 'fluent-smiling-face-with-smiling-eyes'),
    ('chat', 'say', 'verb', 'modernflat', 'fluent-speaking-head'),
    ('chat', 'tell', 'verb', 'modernflat', 'fluent-left-speech-bubble'),
]


def arrow(draw, x1, y1, x2, y2):
    x1, y1, x2, y2 = (v * S for v in (x1, y1, x2, y2))
    angle = math.atan2(y2 - y1, x2 - x1)
    head, width = 46 * S, 20 * S
    bx, by = x2 - head * math.cos(angle), y2 - head * math.sin(angle)
    draw.line([(x1, y1), (bx, by)], fill=BLUE, width=width)
    r = width // 2
    draw.ellipse([x1 - r, y1 - r, x1 + r, y1 + r], fill=BLUE)
    side = 30 * S
    draw.polygon([(x2, y2),
                  (bx + side * math.sin(angle), by - side * math.cos(angle)),
                  (bx - side * math.sin(angle), by + side * math.cos(angle))], fill=BLUE)


def unequal(draw, cx, cy):
    cx, cy = cx * S, cy * S
    w, t = 26 * S, 9 * S
    for dy in (-12 * S, 12 * S):
        draw.rounded_rectangle([cx - w, cy + dy - t // 2, cx + w, cy + dy + t // 2],
                               radius=t // 2, fill=BLUE)
    draw.line([(cx - 14 * S, cy + 30 * S), (cx + 14 * S, cy - 30 * S)], fill=BLUE, width=t)


def compose(parts):
    canvas = Image.new('RGBA', (340 * S, 340 * S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    used = []
    for part in parts:
        if part[0] == 'arrow':
            arrow(draw, *part[1:])
        elif part[0] == 'unequal':
            unequal(draw, *part[1:])
        else:
            key, x, y, size = part
            image = Image.open(FLAT / f'{key}.webp').convert('RGBA')
            image = image.resize((size * S, size * S), Image.LANCZOS)
            canvas.alpha_composite(image, (x * S, y * S))
            used.append(key)
    out = io.BytesIO()
    canvas.resize((340, 340), Image.LANCZOS).save(out, 'WEBP', lossless=True, method=6, exact=True)
    return out.getvalue(), used


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    if pack['packVersion'] >= 14:
        raise SystemExit('Board is already v14.')
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    index = json.loads(INDEX.read_text(encoding='utf8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    composed = manifest.setdefault('composedPictures', {})
    indexed = {(e['p'], e['k']) for e in index}

    for word, parts in COMPOSED.items():
        key = 'vocab-' + word.replace(' ', '-')
        data, used = compose(parts)
        (FLAT / f'{key}.webp').write_bytes(data)
        manifest['files'][f'modernflat/{key}.webp'] = hashlib.sha256(data).hexdigest()
        composed[key] = {'label': word, 'from': used}
        if ('modernflat', key) not in indexed:
            index.append({'p': 'modernflat', 'k': key, 'n': word})

    added, skipped = [], []
    for folder, label, word_class, pack_name, key in WORDS:
        key = key or 'vocab-' + label.replace(' ', '-')
        path = (FLAT / f'{key}.webp') if pack_name == 'modernflat' else (MULBERRY / f'{key}.svg')
        cells = pack['views'][folder][0]['cells']
        here = [buttons[c['btn']] for c in cells]
        if not path.exists():
            skipped.append(f'{label}: no file {key}')
            continue
        if any(b['label'].lower() == label for b in here) or \
                any((b.get('symbolPack'), b.get('symbolKey')) == (pack_name, key) for b in here):
            skipped.append(f'{label}: already on {folder}')
            continue
        button = {'id': f'v14_{folder}_' + label.replace(' ', '_'), 'kind': 'item',
                  'label': label, 'class': word_class, 'symbol': '⬜',
                  'actions': [{'kind': 'addText', 'data': label}],
                  'symbolPack': pack_name, 'symbolKey': key}
        assert button['id'] not in buttons
        buttons[button['id']] = button
        pack['buttons'].append(button)
        history['buttons'][button['id']] = [
            {k: button[k] for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}]
        # Words first, categories stay at the end of the page.
        at = next((i for i, c in enumerate(cells)
                   if buttons[c['btn']]['kind'] == 'folder'), len(cells))
        cells.insert(at, {'btn': button['id']})
        added.append(label)

    files = manifest['files']
    manifest['fileCount'] = len(files)
    manifest['counts']['modernflat'] = len(list(FLAT.glob('*.webp')))
    manifest['indexNames'] = len(index)
    manifest['uniqueIndexedPictures'] = len({(e['p'], e['k']) for e in index})
    manifest['bytes'] = sum(p.stat().st_size
                            for p in (ROOT / 'assets/flat_symbols').glob('*/*.webp'))
    pack['packVersion'] = 14
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    INDEX.write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    print(f'{len(COMPOSED)} pictures composed; {len(added)} words added: {", ".join(added)}')
    for line in skipped:
        print('  skipped', line)


if __name__ == '__main__':
    main()
