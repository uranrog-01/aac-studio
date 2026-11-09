"""Builds assets/i18n/<code>.json from tools/data/i18n/<code>.txt.

Source format (UTF-8), one entry per line, "English|translation":
    [ui]      app text (buttons, hints, settings), keyed by its English text
    [words]   board words and category names, keyed by the English label
Lines starting with # are comments. The saved board stays in English; the
app translates words when it shows and speaks them (lib/engine/i18n.dart).

Reports words on the board that have no translation yet (they stay in
English). Usage: python tools/build_i18n.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/data/i18n'
OUT = ROOT / 'assets/i18n'


def read(path):
    data = {'ui': {}, 'words': {}}
    section = None
    for number, raw in enumerate(path.read_text(encoding='utf8').splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line in ('[ui]', '[words]'):
            section = line[1:-1]
            continue
        if section is None or '|' not in line:
            raise SystemExit(f'{path.name}:{number}: expected "English|translation"')
        english, translated = (part.strip() for part in line.split('|', 1))
        if not english or not translated:
            raise SystemExit(f'{path.name}:{number}: empty side')
        key = english if section == 'ui' else english.lower()
        if key in data[section] and data[section][key] != translated:
            raise SystemExit(f'{path.name}:{number}: "{english}" translated twice')
        data[section][key] = translated
    return data


def read_extra(path):
    """Newer app texts, all languages in one file:
        @ English text
        sq|translation
        fr|translation
    """
    out = {}
    english = None
    if not path.exists():
        return out
    for number, raw in enumerate(path.read_text(encoding='utf8').splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('@ '):
            english = line[2:].strip()
            continue
        if english is None or '|' not in line:
            raise SystemExit(f'{path.name}:{number}: expected "@ English" or "code|text"')
        code, text = (p.strip() for p in line.split('|', 1))
        out.setdefault(code, {})[english] = text
    return out


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    pack = json.loads((ROOT / 'assets/sample_pack.json').read_text(encoding='utf8'))
    labels = {b['label'].lower() for b in pack['buttons']} | \
        {f['label'].lower() for f in pack['folders']}
    # Letters and numbers are read by the voice in the chosen language.
    labels = {l for l in labels if not (len(l) == 1 or l.isdigit())}
    OUT.mkdir(parents=True, exist_ok=True)
    extra = read_extra(SOURCE / '_ui_extra.txt')
    for path in sorted(p for p in SOURCE.glob('*.txt') if not p.name.startswith('_')):
        data = read(path)
        data['ui'].update(extra.get(path.stem, {}))
        (OUT / f'{path.stem}.json').write_text(
            json.dumps(data, ensure_ascii=False, sort_keys=True, indent=0) + '\n',
            encoding='utf8')
        done = len(labels & data['words'].keys())
        print(f'{path.stem}: {len(data["ui"])} app texts, {done} of {len(labels)} '
              f'board words ({100 * done // len(labels)}%)')


if __name__ == '__main__':
    main()
