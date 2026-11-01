"""Pack v7: remove duplicate buttons, nest sub-categories, add missing core words.

Idempotent. Rewrites assets/sample_pack.json, assets/factory_symbol_history.json
(adds known refs + the `retired` cell map used by PackUpgrade.merge),
assets/symbol_index.json (drops exact duplicate rows) and prunes
docs/modern-symbol-manifest.json assignments for removed or re-pictured buttons.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'
INDEX = ROOT / 'assets/symbol_index.json'
MANIFEST = ROOT / 'docs/modern-symbol-manifest.json'

CORE = [f'b{i}' for i in range(1, 25)]
HOME_CATEGORIES = ['fpeople', 'ffeelings', 'fcalm', 'ffood', 'fplay', 'fplaces',
                   'fschool', 'fanimals', 'fbody', 'fx_clothes', 'fx_furniture',
                   'fx_actions', 'fx_time']

# Cells removed from installed packs too (unless the user edited or starred them).
RETIRED = {
    'home': ['fx_people', 'fx_feelings', 'fx_calm', 'fx_food', 'fx_play',
             'fx_places', 'fx_school', 'fx_animals', 'fx_body', 'speakBtn',
             'clearBtn', 'sensoryBtn', 'fx_vehicles', 'fx_weather', 'fx_colors',
             'fx_instruments', 'fx_sports', 'fx_toys', 'fx_kitchen', 'fx_plants',
             'fx_insects', 'fx_sea', 'fx_wild', 'fx_birds', 'fx_jobs',
             'fx_snacks', 'fx_fruitveg', 'fx_health', 'fx_school2', 'fx_places2',
             'category_fruits', 'category_vegetables', 'category_alphabet',
             'category_numbers'],
    'vehicles': ['x15'],      # "fire truck 2"
    'fruits': ['fruits_21'],  # "cherry" = "cherries"
    'plants': ['x102'],       # "blossom" = "flower"
    'toys': ['x74'],          # "drum toy" = Music > drum
    'play': ['b98'],          # "music play" -> Music category link
    'food': ['b80'],          # "fruit" beside the "Fruits" category, same picture
}

# Sub-categories: parent folder -> folders linked at the end of its page.
SUBCATEGORIES = {
    'food': ['snacks', 'kitchen'],
    'play': ['toys', 'sports', 'instruments'],
    'animals': ['wild', 'sea', 'birds', 'insects'],
    'places': ['places2', 'vehicles', 'weather', 'plants'],
    'school': ['school2', 'colors', 'alphabet', 'numbers'],
    'people': ['jobs'],
    'body': ['health'],
}

NEW_ITEMS = {
    # id: (label, class, emoji, pack, key, folder)
    'core_yes': ('yes', 'social', '🙆', 'noto', 'emoji_u1f646', 'home'),
    'core_no': ('no', 'social', '🙅', 'noto', 'emoji_u1f645', 'home'),
    'core_wait': ('wait', 'verb', '⏳', 'noto', 'emoji_u23f3', 'home'),
    'calm_break': ('break', 'noun', '⏸', 'mulberry', 'break_time_1', 'calm'),
    'calm_loud': ('too loud', 'adjective', '🔊', 'mulberry', 'loud', 'calm'),
}

NEW_PICTURES = {'b22': ('mulberry', 'go_through_door_,_to')}  # bye != hi
# Category pictures must differ from words on the page that links to them.
FOLDER_PICTURES = {
    'sports': ('modern3d', 'fluent-sports-medal'),  # Play > ball
    'vehicles': ('modern3d', 'fluent-train'),       # Places > car
    'birds': ('modern3d', 'fluent-parrot'),         # Animals > bird
    'wild': ('modern3d', 'fluent-giraffe'),         # Animals > lion
}

CLASS_FIXES = {
    'actions': 'verb',       # clap, point, sleep ... were coloured as nouns
    'colors': 'adjective',   # describing words are blue in the Fitzgerald key
}
CLASS_BY_LABEL = {('weather', 'hot'): 'adjective', ('weather', 'cold'): 'adjective'}


def write(path, text):
    # Keep each file's existing line endings so diffs show real changes only.
    crlf = b'\r\n' in path.read_bytes()
    path.write_text(text, encoding='utf8', newline='\r\n' if crlf else '\n')


def ref(button):
    return {k: button[k] for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    folders = {f['id']: f for f in pack['folders']}
    views = pack['views']

    def cells(folder):
        return views[folder][0]['cells']

    def remember(button):
        known = history['buttons'].setdefault(button['id'], [])
        if ref(button) not in known:
            known.append(ref(button))

    # Fruits & veggies only repeated Fruits + Vegetables.
    for c in cells('fruitveg') if 'fruitveg' in views else []:
        buttons.pop(c['btn'], None)
    views.pop('fruitveg', None)
    folders.pop('fruitveg', None)

    for folder, ids in RETIRED.items():
        if folder in views:
            views[folder][0]['cells'] = [c for c in cells(folder) if c['btn'] not in ids]

    for bid, (label, cls, emoji, sp, key, folder) in NEW_ITEMS.items():
        buttons[bid] = {'id': bid, 'kind': 'item', 'label': label, 'class': cls,
                        'symbol': emoji, 'symbolPack': sp, 'symbolKey': key,
                        'actions': [{'kind': 'addText', 'data': label}]}
    buttons['calm_sensory'] = {
        'id': 'calm_sensory', 'kind': 'action', 'label': 'Sensory games',
        'class': 'other', 'symbol': '🎮', 'symbolPack': 'modern3d',
        'symbolKey': 'fluent-video-game', 'actions': [{'kind': 'sensoryGames'}]}

    for fid, (sp, key) in FOLDER_PICTURES.items():
        known = history['folders'].setdefault(fid, [])
        if ref(folders[fid]) not in known:
            known.append(ref(folders[fid]))
        folders[fid]['symbolPack'], folders[fid]['symbolKey'] = sp, key
        if ref(folders[fid]) not in known:
            known.append(ref(folders[fid]))

    for parent, children in SUBCATEGORIES.items():
        for child in children:
            f = folders[child]
            bid = f'sub_{child}'
            buttons[bid] = {'id': bid, 'kind': 'folder', 'label': f['label'],
                            'class': 'other', 'symbol': f['symbol'],
                            'symbolPack': f['symbolPack'], 'symbolKey': f['symbolKey'],
                            'actions': [{'kind': 'gotoFolder', 'data': child}]}
            if not any(c['btn'] == bid for c in cells(parent)):
                cells(parent).append({'btn': bid})
    for bid in ['calm_break', 'calm_loud', 'calm_sensory']:
        if not any(c['btn'] == bid for c in cells('calm')):
            cells('calm').append({'btn': bid})

    views['home'][0]['cells'] = [{'btn': b} for b in
                                 CORE + ['core_yes', 'core_no', 'core_wait'] + HOME_CATEGORIES]

    for bid, (sp, key) in NEW_PICTURES.items():
        remember(buttons[bid])
        buttons[bid]['symbolPack'], buttons[bid]['symbolKey'] = sp, key
    for folder, cls in CLASS_FIXES.items():
        for c in cells(folder):
            if buttons[c['btn']]['kind'] == 'item':
                buttons[c['btn']]['class'] = cls
    for (folder, label), cls in CLASS_BY_LABEL.items():
        for c in cells(folder):
            if buttons[c['btn']]['label'] == label:
                buttons[c['btn']]['class'] = cls
    for b in buttons.values():
        if b['kind'] == 'folder':
            b.setdefault('class', 'other')

    used = {c['btn'] for vs in views.values() for v in vs for c in v['cells']}
    pack['buttons'] = [b for b in buttons.values() if b['id'] in used]
    pack['folders'] = list(folders.values())
    pack['packVersion'] = 7
    for b in pack['buttons']:
        remember(b)
    history['retired'] = RETIRED
    write(PACK, json.dumps(pack, ensure_ascii=False, indent=1) + '\n')
    write(HISTORY, json.dumps(history, ensure_ascii=False, indent=1) + '\n')

    manifest = json.loads(MANIFEST.read_text(encoding='utf8'))
    live = {'buttons': {b['id']: b for b in pack['buttons']}, 'folders': folders}
    manifest['assignments'] = [
        a for a in manifest['assignments']
        if live[a['kind']].get(a['id'], {}).get('symbolKey') == a['key']]
    write(MANIFEST, json.dumps(manifest, ensure_ascii=False, indent=1) + '\n')

    index = json.loads(INDEX.read_text(encoding='utf8'))
    seen, unique = set(), []
    for e in index:
        t = (e['p'], e['k'], e['n'])
        if t not in seen:
            seen.add(t)
            unique.append(e)
    write(INDEX, json.dumps(unique, ensure_ascii=False, separators=(',', ':')))
    print(f'{len(pack["buttons"])} buttons, {len(pack["folders"])} categories, '
          f'home {len(cells("home"))} cells, index {len(index)} -> {len(unique)}')


if __name__ == '__main__':
    main()
