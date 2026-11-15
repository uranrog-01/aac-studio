"""Board v17: buttons that open the new tools.

Daily routines: schedule, first then, timer. Health: where it hurts.
Chat: listen. People: my photos (photo scenes). Each button opens its
tool (ActionKind.openTool); the pictures are already in the app.
Run once from studio: python tools/add_tools_v17.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'

TOOLS = [
    # page, tool, label, pack, key, emoji
    ('routines', 'schedule', 'schedule', 'modernflat', 'fluent-calendar', '📅'),
    ('routines', 'firstthen', 'first then', 'mulberry', 'first', '➡️'),
    ('routines', 'timer', 'timer', 'mulberry', 'timer_2', '⏲️'),
    ('health', 'pain', 'where it hurts', 'mulberry', 'body_outline', '🤕'),
    ('chat', 'listen', 'listen', 'modernflat', 'scene-listen', '👂'),
    ('people', 'scenes', 'my photos', 'modernflat', 'fluent-framed-picture', '🖼️'),
]


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    if pack['packVersion'] >= 17:
        raise SystemExit('Board is already v17.')
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    first_on_page = {}
    for page, tool, label, sym_pack, key, emoji in TOOLS:
        button = {'id': f'tool_{tool}', 'kind': 'action', 'label': label, 'class': 'other',
                  'symbol': emoji, 'symbolPack': sym_pack, 'symbolKey': key,
                  'actions': [{'kind': 'openTool', 'data': tool}]}
        assert button['id'] not in buttons
        pack['buttons'].append(button)
        buttons[button['id']] = button
        history['buttons'][button['id']] = [
            {k: button[k] for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}]
        first_on_page.setdefault(page, []).append({'btn': button['id']})
    for page, cells in first_on_page.items():
        view = pack['views'][page][0]
        # The tools lead their page, where they are seen first.
        view['cells'] = cells + view['cells']
        labels, pictures = set(), set()
        for c in view['cells']:
            b = buttons[c['btn']]
            assert b['label'] not in labels, (page, b['label'])
            assert (b.get('symbolPack'), b.get('symbolKey')) not in pictures, (page, b['label'])
            labels.add(b['label'])
            pictures.add((b.get('symbolPack'), b.get('symbolKey')))
    pack['packVersion'] = 17
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    print('Board v17:', ', '.join(t[2] for t in TOOLS))


if __name__ == '__main__':
    main()
