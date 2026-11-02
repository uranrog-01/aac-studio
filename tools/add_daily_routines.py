"""Pack v9: a Daily routines category for the modern flat routine pictures.

Linked from Actions and My body. Idempotent; existing installs receive it
through the normal pack upgrade (new folder, new cells appended).
Usage: python tools/add_daily_routines.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'

# Hygiene and dressing first (most used), then chores, then school tasks.
ROUTINES = [
    'wash hands', 'dry hands', 'wash face', 'wipe face', 'blow nose', 'brush hair',
    'wash hair', 'get dressed', 'put on socks', 'put on shoes', 'take off shoes',
    'zip coat', 'put clothes away', 'fold clothes', 'hang clothes', 'wipe table',
    'wash dishes', 'sweep floor', 'mop floor', 'vacuum floor', 'take out trash',
    'cut paper', 'erase', 'paint picture',
]
FOLDER = {'id': 'routines', 'label': 'Daily routines', 'symbol': '🧼',
          'symbolPack': 'modernflat', 'symbolKey': 'vocab-wash-hands'}
LINKED_FROM = ['actions', 'body']


def slug(label):
    return label.replace(' ', '-')


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    for label in ROUTINES:
        key = f'vocab-{slug(label)}'
        assert (ROOT / 'assets/flat_symbols/modernflat' / f'{key}.webp').exists(), key
        buttons[f'routine_{slug(label)}'] = {
            'id': f'routine_{slug(label)}', 'kind': 'item', 'label': label, 'class': 'verb',
            'symbol': '🧼', 'symbolPack': 'modernflat', 'symbolKey': key,
            'actions': [{'kind': 'addText', 'data': label}]}
    buttons['sub_routines'] = {
        'id': 'sub_routines', 'kind': 'folder', 'label': FOLDER['label'], 'class': 'other',
        'symbol': FOLDER['symbol'], 'symbolPack': FOLDER['symbolPack'],
        'symbolKey': FOLDER['symbolKey'], 'actions': [{'kind': 'gotoFolder', 'data': 'routines'}]}
    if not any(f['id'] == 'routines' for f in pack['folders']):
        pack['folders'].append(dict(FOLDER))
    pack['views']['routines'] = [{'columns': 4, 'cells': [
        {'btn': f'routine_{slug(label)}'} for label in ROUTINES]}]
    for parent in LINKED_FROM:
        cells = pack['views'][parent][0]['cells']
        if not any(c['btn'] == 'sub_routines' for c in cells):
            cells.append({'btn': 'sub_routines'})
    pack['buttons'] = list(buttons.values())
    pack['packVersion'] = 9
    for kind in ('buttons', 'folders'):
        for item in pack[kind]:
            ref = {k: item.get(k) for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}
            refs = history[kind].setdefault(item['id'], [])
            if ref not in refs:
                refs.append(ref)
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    print(f'{len(ROUTINES)} routines; pack v9; {len(pack["buttons"])} buttons, '
          f'{len(pack["folders"])} categories')


if __name__ == '__main__':
    main()
