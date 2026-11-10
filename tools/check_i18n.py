"""Checks one language's translation file before it is built.

Usage: python -I tools/check_i18n.py <code> [<code> ...]

Reads tools/data/i18n/<code>.txt and reports format errors and which app
texts, core words and library words are still missing. Uses the English
lists in tools/data/i18n/_source/ (written by tools/i18n_sources.py).
Exit code 0 only when the file is complete and valid.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'tools/data/i18n'
SOURCE = DATA / '_source'


def entries(path):
    return [line.split('\t')[0] for line in
            (SOURCE / path).read_text(encoding='utf8').splitlines() if line.strip()]


def check(code):
    path = DATA / f'{code}.txt'
    if not path.exists():
        print(f'{code}: {path} does not exist')
        return False
    ui, words, forms, problems = {}, {}, {}, []
    section = None
    for number, raw in enumerate(path.read_text(encoding='utf8').splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line in ('[ui]', '[words]', '[forms]'):
            section = line
            continue
        if section is None:
            problems.append(f'line {number}: text before [ui] or [words]')
            continue
        if line.count('|') < 1:
            problems.append(f'line {number}: no "|" in {line!r}')
            continue
        english, translated = (p.strip() for p in line.split('|', 1))
        if not english or not translated:
            problems.append(f'line {number}: empty side in {line!r}')
            continue
        target = ui if section == '[ui]' else forms if section == '[forms]' else words
        key = english if section == '[ui]' else english.lower()
        if key in target and target[key] != translated:
            problems.append(f'line {number}: {english!r} translated twice')
        target[key] = translated
    english_only = code == 'en'
    missing_ui = [] if english_only else [e for e in entries('ui.txt') if e not in ui]
    missing_core = [] if english_only else [
        e for e in entries('core_words.txt') if e.lower() not in words]
    missing_lib = [] if english_only else [
        e for e in entries('library_words.txt') if e.lower() not in words]
    missing_forms = [e for e in entries('forms.txt') if e.lower() not in forms]
    ok = not (problems or missing_ui or missing_core or missing_lib or missing_forms)
    print(f'{code}: {"OK" if ok else "INCOMPLETE"} - {len(ui)} app texts, '
          f'{len(words)} words; missing: {len(missing_ui)} app texts, '
          f'{len(missing_core)} core, {len(missing_lib)} library, '
          f'{len(missing_forms)} sentence forms; '
          f'{len(problems)} format problems')
    for p in problems[:20]:
        print('  ', p)
    for label, items in (('app text', missing_ui), ('core', missing_core),
                         ('library', missing_lib), ('sentence form', missing_forms)):
        if items:
            print(f'   first missing {label}: {items[:8]}')
    return ok


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    results = [check(code) for code in sys.argv[1:]]
    sys.exit(0 if results and all(results) else 1)
