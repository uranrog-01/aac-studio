"""Board v15: a Games category on Home and the question word "why".

Games holds one button per sensory game (lib/features/sensory): each opens
its game directly. The old "Sensory games" button in Calm down still opens
the games menu. Two small pictures (spinner, kaleidoscope) are drawn here.
Run once from studio: python tools/add_games_v15.py
"""
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
FLAT = ROOT / 'assets/flat_symbols/modernflat'
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'
INDEX = ROOT / 'assets/symbol_index.json'
MANIFEST = ROOT / 'docs/flat-symbol-manifest.json'

# game id, board word, picture pack, picture key
GAMES = [
    ('bubbles', 'bubbles', 'modernflat', 'fluent-bubbles'),
    ('lights', 'light painting', 'modernflat', 'fluent-sparkler'),
    ('water', 'water ripples', 'modernflat', 'fluent-water-wave'),
    ('kaleidoscope', 'kaleidoscope', 'modernflat', 'vocab-kaleidoscope'),
    ('lava', 'lava lamp', 'mulberry', 'lava_lamp'),
    ('xylophone', 'xylophone', 'mulberry', 'xylophone'),
    ('spinner', 'spinner', 'modernflat', 'vocab-spinner'),
]
COLOURS = [(239, 83, 80), (255, 167, 38), (255, 238, 88), (102, 187, 106),
           (38, 198, 218), (66, 165, 245), (126, 87, 194), (236, 64, 122)]


def webp(image):
    out = io.BytesIO()
    image.resize((340, 340), Image.LANCZOS).save(out, 'WEBP', lossless=True, method=6, exact=True)
    return out.getvalue()


def spinner():
    s = 680
    image = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    c = s / 2
    for arm, colour in enumerate([(66, 165, 245), (239, 83, 80), (102, 187, 106)]):
        a = math.radians(-90 + arm * 120)
        x, y = c + math.cos(a) * 200, c + math.sin(a) * 200
        d.line([(c, c), (x, y)], fill=colour + (255,), width=110)
        d.ellipse([x - 105, y - 105, x + 105, y + 105], fill=colour + (255,))
        d.ellipse([x - 50, y - 50, x + 50, y + 50], fill=(255, 255, 255, 235))
    d.ellipse([c - 85, c - 85, c + 85, c + 85], fill=(236, 239, 241, 255))
    d.ellipse([c - 42, c - 42, c + 42, c + 42], fill=(69, 90, 100, 255))
    return webp(image)


def kaleidoscope():
    s = 680
    image = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    c = s / 2
    d.ellipse([20, 20, s - 20, s - 20], fill=(26, 26, 46, 255))
    for ring, (radius, size) in enumerate([(235, 62), (150, 50), (75, 36)]):
        for k in range(8):
            a = math.radians(k * 45 + ring * 22.5)
            x, y = c + math.cos(a) * radius, c + math.sin(a) * radius
            d.ellipse([x - size, y - size, x + size, y + size],
                      fill=COLOURS[(k + ring * 3) % 8] + (255,))
    d.ellipse([c - 30, c - 30, c + 30, c + 30], fill=(255, 255, 255, 255))
    return webp(image)


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    if pack['packVersion'] >= 15:
        raise SystemExit('Board is already v15.')
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    index = json.loads(INDEX.read_text(encoding='utf8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    views = pack['views']

    for key, label, data in [('vocab-spinner', 'spinner', spinner()),
                             ('vocab-kaleidoscope', 'kaleidoscope', kaleidoscope())]:
        (FLAT / f'{key}.webp').write_bytes(data)
        manifest['files'][f'modernflat/{key}.webp'] = hashlib.sha256(data).hexdigest()
        manifest.setdefault('composedPictures', {})[key] = {'label': label, 'from': ['drawn by tools/add_games_v15.py']}
        index.append({'p': 'modernflat', 'k': key, 'n': label})

    def add(button):
        assert button['id'] not in buttons, button['id']
        buttons[button['id']] = button
        pack['buttons'].append(button)
        history['buttons'][button['id']] = [
            {k: button[k] for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}]
        return {'btn': button['id']}

    layouts = history.setdefault('layouts', {})
    for folder in ('home', 'allcats'):
        layouts.setdefault(folder, []).append([c['btn'] for c in views[folder][0]['cells']])

    # ---- the Games category
    pack['folders'].append({'id': 'games', 'label': 'Games', 'symbol': '🎮',
                            'symbolPack': 'modernflat', 'symbolKey': 'fluent-video-game'})
    history['folders']['games'] = [{'label': 'Games', 'symbol': '🎮', 'symbolPack': 'modernflat',
                                    'symbolKey': 'fluent-video-game'}]
    cells = []
    for game, label, pack_name, key in GAMES:
        path = FLAT / f'{key}.webp' if pack_name == 'modernflat' \
            else ROOT / f'assets/symbols/mulberry/{key}.svg'
        assert path.exists(), key
        cells.append(add({'id': f'game_{game}', 'kind': 'action', 'label': label,
                          'class': 'other', 'symbol': '🎮', 'symbolPack': pack_name,
                          'symbolKey': key,
                          'actions': [{'kind': 'sensoryGames', 'data': game}]}))
    views['games'] = [{'columns': 4, 'cells': cells}]

    def folder_button(button_id):
        return add({'id': button_id, 'kind': 'folder', 'label': 'Games', 'class': 'other',
                    'symbol': '🎮', 'symbolPack': 'modernflat',
                    'symbolKey': 'fluent-video-game',
                    'actions': [{'kind': 'gotoFolder', 'data': 'games'}]})

    def after(folder, label, cell):
        items = views[folder][0]['cells']
        at = next(i for i, c in enumerate(items) if buttons[c['btn']]['label'] == label)
        items.insert(at + 1, cell)

    after('home', 'Play', folder_button('home_games'))
    after('allcats', 'Play', folder_button('all_games'))
    views['play'][0]['cells'].append(folder_button('play_games'))

    # ---- "why" joins what / where / who on Home
    why = add({'id': 'v15_home_why', 'kind': 'item', 'label': 'why', 'class': 'question',
               'symbol': '❓', 'symbolPack': 'mulberry', 'symbolKey': 'why',
               'actions': [{'kind': 'addText', 'data': 'why'}]})
    after('home', 'who', why)

    for folder in views:
        seen_labels, seen_pictures = set(), set()
        for c in views[folder][0]['cells']:
            b = buttons[c['btn']]
            assert b['label'].lower() not in seen_labels, (folder, b['label'])
            assert (b['symbolPack'], b['symbolKey']) not in seen_pictures, (folder, b['label'])
            seen_labels.add(b['label'].lower())
            seen_pictures.add((b['symbolPack'], b['symbolKey']))

    manifest['fileCount'] = len(manifest['files'])
    manifest['counts']['modernflat'] = len(list(FLAT.glob('*.webp')))
    manifest['indexNames'] = len(index)
    manifest['uniqueIndexedPictures'] = len({(e['p'], e['k']) for e in index})
    manifest['bytes'] = sum(p.stat().st_size for p in (ROOT / 'assets/flat_symbols').glob('*/*.webp'))
    pack['packVersion'] = 15
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    INDEX.write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    home = views['home'][0]['cells']
    words = sum(buttons[c['btn']]['kind'] == 'item' for c in home)
    print(f'Home: {words} words + {len(home) - words} categories; Games has {len(cells)} games')


if __name__ == '__main__':
    main()
