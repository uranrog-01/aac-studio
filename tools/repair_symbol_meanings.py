"""Explicit, reviewed starter-picture assignments. No fuzzy label matching.

Original communication SVGs are MIT licensed with the app. Existing Mulberry
and emoji artwork retains its own license (see THIRD_PARTY_SYMBOLS.md).
"""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf8')


def person(x=64, y=20, shirt='#6ba9dc'):
    return (f'<circle cx="{x}" cy="{y}" r="12" fill="#f3cdab"/>'
            f'<path d="M{x-19} {y+52}V{y+31}q0-15 19-15t19 15v21Z" fill="{shirt}"/>'
            f'<path d="M{x-11} {y+52}v20m22-20v20" fill="none"/>'
            f'<path d="M{x-4} {y-1}h1m7 0h1" fill="none" stroke-width="3"/>')


def arrow(x1, y1, x2, y2, color='#256caa'):
    # A filled triangle head, supported by Flutter's SVG renderer.
    import math
    a = math.atan2(y2-y1, x2-x1)
    pts = [(x2, y2)] + [(x2-13*math.cos(a+d), y2-13*math.sin(a+d)) for d in (-.55, .55)]
    return (f'<path d="M{x1} {y1}L{x2} {y2}" stroke="{color}" stroke-width="7" fill="none"/>'
            f'<polygon points="{" ".join(f"{x},{y}" for x,y in pts)}" fill="{color}" stroke="{color}"/>')


def heart(x=64, y=54, color='#db5568'):
    return f'<path d="M{x} {y+28}C{x-52} {y-6} {x-22} {y-31} {x} {y-10}C{x+22} {y-31} {x+52} {y-6} {x} {y+28}Z" fill="{color}"/>'


def icons():
    # Arrows show speaker/self, listener/other, possession, object and turn.
    result = {
        'i': person(64, 22) + arrow(113, 52, 69, 52),
        'you': person(85, 22, '#86b98a') + arrow(14, 52, 68, 52),
        'my': person(64, 22) + '<circle cx="64" cy="52" r="9" fill="#db5568"/>' + arrow(113, 52, 72, 52),
        'it': '<rect x="42" y="55" width="40" height="40" rx="5" fill="#eabb58"/>' + arrow(110, 21, 71, 58),
        'need': person(43, 25) + '<path d="M80 63h32l-5 33H85Z" fill="#b8e6f5"/>' + arrow(75, 31, 85, 60),
        'like': heart() + '<path d="m46 57 12 12 25-28" stroke="white" stroke-width="7" fill="none"/>',
        'dont-like': heart(color='#cdd7de') + '<path d="m44 34 40 44m0-44-40 44" stroke="#c63c4e" stroke-width="8"/>',
        'my-turn': person(35, 27) + person(97, 27, '#86b98a') + '<circle cx="35" cy="27" r="17" fill="none" stroke="#dc9d26" stroke-width="5"/>' + arrow(99, 106, 34, 106),
        'again': '<path d="M98 43a39 39 0 1 0 1 42" fill="none" stroke="#256caa" stroke-width="10"/><path d="M101 19v30H71" fill="none" stroke="#256caa" stroke-width="10"/>',
        'please': person(64, 24) + '<path d="M45 55q17 16 33-1" fill="none" stroke="#f3cdab" stroke-width="11"/>' + '<circle cx="67" cy="54" r="7" fill="#f3cdab"/>',
        'thank-you': person(36, 25) + '<path d="M36 47Q52 61 75 48" fill="none" stroke="#f3cdab" stroke-width="10"/>' + heart(97, 26) + arrow(63, 83, 105, 83),
        'breathe': '<path d="M31 16q32 0 32 27l11 14-12 7v24H44v20H22" fill="#f3cdab"/>' + '<path d="M77 48h28q17 0 17-10t-15-9M78 63h34M77 77h24q15 0 15 11t-13 10" fill="none" stroke="#59a9c5" stroke-width="5"/>',
        'high-five': '<path d="M19 105V64L8 50q-4-7 3-9l15 13V23q0-7 6-7t6 7v25-33q0-7 6-7t6 7v34-29q0-7 6-7t6 7v41q0 25-21 44Z" fill="#f3cdab"/>' + '<path d="M109 105V64l11-14q4-7-3-9l-15 13V23q0-7-6-7t-6 7v25-33q0-7-6-7t-6 7v34-29q0-7-6-7t-6 7v41q0 25 21 44Z" fill="#d59b73"/>' + '<path d="m58 106 6-11 6 11M52 115l-9 4m33-4 9 4" fill="none" stroke="#dc9d26" stroke-width="4"/>',
        'bedroom': '<path d="M13 105V23h101v82" fill="#e9f0f5"/><path d="M32 58h17v18H32Z" fill="#f4d16e"/><path d="M78 58h25v29H78Z" fill="#91c5e4"/><path d="M23 101V70h36v31m-36-9h81v-8q0-8-11-8H59m45 16v9" fill="#d7897b"/><rect x="76" y="32" width="25" height="23" fill="#b8e6f5"/>',
        'park': '<path d="M5 110q60-35 118 0" fill="#91bd70"/><path d="M31 52v47" stroke="#9b734e" stroke-width="8"/><path d="M31 13c-28 0-32 47 0 47s28-47 0-47Z" fill="#79ac5a"/><path d="M63 72h50v15H63Zm4 15v15m41-15v15" fill="#c98d60"/>',
        'clear': '<rect x="11" y="19" width="106" height="88" rx="10" fill="#e9f0f5"/><path d="M26 40h76M26 58h76M26 76h36" stroke="#7d96a6" stroke-width="5"/><path d="m77 71 25 25m0-25L77 96" stroke="#c63c4e" stroke-width="7"/>',
        'places': '<path d="m9 91 34-58 41 5 35 56-48 18Z" fill="#dcebc8"/><path d="m43 34 28 78m13-74-13 74" fill="none" stroke="#90b7cc" stroke-width="6"/><path d="M65 65C24 28 46 9 65 9s41 19 0 56Z" fill="#da6375"/><circle cx="65" cy="27" r="7" fill="white"/>',
        'colors': '<path d="M64 12C-2 12-3 113 62 113c33 0 22-27 14-30s0-14 15-13c39 6 42-58-27-58Z" fill="#e4cda5"/>' + ''.join(f'<circle cx="{x}" cy="{y}" r="10" fill="{c}"/>' for x,y,c in [(37,36,'#d84b58'),(68,29,'#e8bd40'),(95,44,'#75a85a'),(29,68,'#4b99c9'),(44,95,'#a372b5')]),
        'ninja-star': '<path d="M64 7 78 43 121 64 85 78 64 121 50 85 7 64 43 50Z" fill="#8496a5"/><path d="m64 7-6 47L7 64l47 6 10 51 6-47 51-10-47-6Z" fill="#d2dce3" stroke="none"/><circle cx="64" cy="64" r="10" fill="white"/>',
    }
    return result


def main():
    path = ASSETS / 'sample_pack.json'
    pack = read(path)
    if pack.get('packVersion', 0) >= 6:
        print('The modern 3D pack supersedes this historical v5 repair. No changes made.')
        return
    history_path = ASSETS / 'factory_symbol_history.json'
    history = read(history_path) if history_path.exists() else {'buttons': {}, 'folders': {}}
    # Keep previous known factory references so migrations repair these only.
    for kind in ('buttons', 'folders'):
        for item in pack[kind]:
            refs = history[kind].setdefault(item['id'], [])
            ref = {k: item.get(k) for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}
            if ref not in refs:
                refs.append(ref)
    write(history_path, history)

    art = icons()
    folder = ASSETS / 'symbols' / 'communication'
    folder.mkdir(exist_ok=True)
    for name, content in art.items():
        label = name.replace('-', ' ')
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'
               f'<title>{html.escape(label)}</title><g stroke="#354653" stroke-width="2.5" '
               f'stroke-linecap="round" stroke-linejoin="round">{content}</g></svg>\n')
        (folder / f'{name}.svg').write_text(svg, encoding='utf8')

    # Vocabulary concepts use actions/relationships rather than unrelated objects.
    communication = {
        'b1': 'i', 'b2': 'you', 'b3': 'my', 'b4': 'it', 'b6': 'need',
        'b7': 'like', 'b8': 'dont-like', 'b16': 'my-turn', 'b17': 'again',
        'b23': 'thank-you', 'b24': 'please', 'b59': 'breathe',
        'b101': 'park', 'b106': 'bedroom', 'clearBtn': 'clear', 'x166': 'high-five',
        'x76': 'ninja-star',
    }
    mulberry = {
        'b9': 'more', 'b10': 'help_,_to', 'b12': 'go_,_to', 'b13': 'finish',
        'b15': 'open_,_to', 'b18': 'look_,_to', 'b19': 'make_,_to',
        'b21': 'hello', 'b37': 'mum_parent', 'b38': 'dad_parent',
        'b42': 'grandmother', 'b43': 'grandfather', 'b50': 'yawn_,_to', 'b52': 'excited_man',
        'b54': 'relax_,_to', 'b61': 'hug_,_to', 'b62': 'rest_,_to',
        'b63': 'drink_,_to', 'b64': 'count_,_to', 'b69': 'eat_,_to',
        'b85': 'play_,_to', 'b93': 'sing_,_to', 'b94': 'draw_,_to',
        'b97': 'lego', 'b108': 'work_,_to', 'b109': 'read_book_,_to',
        'b110': 'write_,_to', 'b115': 'hear_,_to',
        'x148': 'cockerel', 'x162': 'sleep_male_,_to', 'x163': 'cook_,_to',
    }
    assignments = {bid: ('communication', key) for bid, key in communication.items()}
    assignments.update({bid: ('mulberry', key) for bid, key in mulberry.items()})
    assignments['x64'] = ('twemoji', '1f3c8')  # American football; soccer already has its own tile.
    # Category links and folder metadata share precisely the same artwork.
    categories = {
        'play': ('mulberry', 'play_,_to'),
        'places': ('communication', 'places'),
        'colors': ('communication', 'colors'),
        'toys': ('mulberry', 'toys'),
        'kitchen': ('mulberry', 'cooker'),
        'plants': ('mulberry', 'plant'),
    }
    for item in pack['folders']:
        if item['id'] in categories:
            item['symbolPack'], item['symbolKey'] = categories[item['id']]
    folders = {f['id']: f for f in pack['folders']}
    changes = []
    for item in pack['buttons']:
        previous = history['buttons'][item['id']][0]
        before = (previous['symbolPack'], previous['symbolKey'])
        if item['id'] == 'x76':
            item['label'] = 'ninja star'
            item['spoken'] = 'ninja star'
            item['symbol'] = '✦'
        if item['id'] in assignments:
            item['symbolPack'], item['symbolKey'] = assignments[item['id']]
        if item['kind'] == 'folder':
            target = next(a['data'] for a in item['actions'] if a['kind'] == 'gotoFolder')
            if target in categories:
                item['symbolPack'], item['symbolKey'] = categories[target]
        after = (item['symbolPack'], item['symbolKey'])
        if before != after:
            changes.append({'id': item['id'], 'label': item['label'], 'before': before, 'after': after})
    pack['packVersion'] = 5
    write(path, pack)
    index_path = ASSETS / 'symbol_index.json'
    index = [e for e in read(index_path) if e['p'] != 'communication']
    index.extend({'p': 'communication', 'k': key, 'n': key.replace('-', ' ')} for key in art)
    index_path.write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')), encoding='utf8')
    if changes:
        write(ROOT / 'docs' / 'symbol-meaning-repairs.json', changes)
    print(f'{len(changes)} starter links corrected; {len(art)} original communication pictograms')


if __name__ == '__main__':
    main()
