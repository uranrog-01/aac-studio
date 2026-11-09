"""Writes the English lists translators work from (tools/data/i18n/_source/).

ui.txt             app texts (from tools/data/i18n/fr.txt, the reference)
core_words.txt     Home and starter category words and category names
library_words.txt  word library, each with its category for meaning
                   ("bat<TAB>Sports" is the bat you play with)
Letters and digits are left out: the voice reads them in each language.
Usage: python -I tools/i18n_sources.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tools/data/i18n/_source'


def main():
    pack = json.loads((ROOT / 'assets/sample_pack.json').read_text(encoding='utf8'))
    buttons = {b['id']: b for b in pack['buttons']}
    folder_label = {f['id']: f['label'] for f in pack['folders']}
    page_of = {}
    for page, views in pack['views'].items():
        for cell in views[0]['cells']:
            page_of.setdefault(cell['btn'], folder_label.get(page, page))

    def keep(label):
        return not (len(label) == 1 or label.isdigit())

    core, library = {}, {}
    for b in pack['buttons']:
        if not keep(b['label']):
            continue
        target = library if b['id'].startswith('v11_') else core
        target.setdefault(b['label'].lower(), (b['label'], page_of.get(b['id'], '')))
    for f in pack['folders']:
        core.setdefault(f['label'].lower(), (f['label'], 'category name'))
    for key in core:
        library.pop(key, None)

    ui = []
    section = None
    for line in (ROOT / 'tools/data/i18n/fr.txt').read_text(encoding='utf8').splitlines():
        if line in ('[ui]', '[words]'):
            section = line
        elif section == '[ui]' and '|' in line:
            ui.append(line.split('|', 1)[0])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'ui.txt').write_text('\n'.join(ui) + '\n', encoding='utf8')
    for name, items in (('core_words.txt', core), ('library_words.txt', library)):
        lines = [f'{label}\t{page}' for label, page in
                 sorted(items.values(), key=lambda x: x[0].lower())]
        (OUT / name).write_text('\n'.join(lines) + '\n', encoding='utf8')
    print(f'{len(ui)} app texts, {len(core)} core words, {len(library)} library words')


if __name__ == '__main__':
    main()
