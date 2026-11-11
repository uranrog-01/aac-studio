"""Builds picture review sheets: every board button with its picture and word.

One page per category, so a person can look through all pictures and spot
a wrong one (a "plane" tool showing an airplane). The word is shown in
English and, with --lang, in that language as the app shows it.

Usage (from studio): python tools/review_sheets.py [--lang sq]
Open build/review-sheets/index.html in a browser.
"""
import argparse
import html
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/review-sheets'
STYLE = ('body{font:14px system-ui;background:#f4f4f4;margin:16px}'
         '.c{display:inline-block;width:150px;vertical-align:top;background:#fff;'
         'border-radius:10px;margin:5px;padding:8px;text-align:center}'
         '.c img{width:120px;height:120px;object-fit:contain}'
         '.c b{display:block}.c small{color:#777;word-break:break-all}'
         '.missing{background:#ffd9d9}a{margin-right:12px;line-height:2}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lang', help='language code, e.g. sq')
    args = parser.parse_args()
    pack = json.loads((ROOT / 'assets/sample_pack.json').read_text(encoding='utf8'))
    words = {}
    if args.lang:
        words = json.loads((ROOT / f'assets/i18n/{args.lang}.json')
                           .read_text(encoding='utf8'))['words']
    buttons = {b['id']: b for b in pack['buttons']}
    folders = {f['id']: f['label'] for f in pack['folders']}
    OUT.mkdir(parents=True, exist_ok=True)
    links, missing = [], 0
    for folder, views in pack['views'].items():
        cells = []
        for cell in views[0]['cells']:
            b = buttons.get(cell.get('btn'))
            if b is None:
                continue
            key = b.get('symbolKey') or ''
            path = (ROOT / f'assets/flat_symbols/modernflat/{key}.webp'
                    if b.get('symbolPack') == 'modernflat'
                    else ROOT / f'assets/symbols/mulberry/{key}.svg')
            found = path.exists()
            missing += not found
            shown = words.get('@' + b['id'].lower()) or words.get(b['label'].lower())
            src = os.path.relpath(path, OUT).replace('\\', '/')
            cells.append(
                f'<div class="c{"" if found else " missing"}">'
                f'<img src="{html.escape(src)}" loading="lazy">'
                f'<b>{html.escape(b["label"])}</b>'
                + (f'{html.escape(shown)}<br>' if shown else '')
                + f'<small>{html.escape(key)}</small></div>')
        name = folders.get(folder, folder)
        (OUT / f'{folder}.html').write_text(
            f'<!doctype html><meta charset="utf-8"><title>{html.escape(name)}</title>'
            f'<style>{STYLE}</style><a href="index.html">All categories</a>'
            f'<h1>{html.escape(name)} ({len(cells)})</h1>' + ''.join(cells),
            encoding='utf8')
        links.append(f'<a href="{folder}.html">{html.escape(name)} ({len(cells)})</a>')
    (OUT / 'index.html').write_text(
        f'<!doctype html><meta charset="utf-8"><title>Picture review</title>'
        f'<style>{STYLE}</style><h1>Picture review</h1>'
        f'<p>{len(buttons)} buttons, {missing} without a picture file.</p>'
        + ' '.join(links), encoding='utf8')
    print(f'{len(links)} pages in {OUT} ({missing} missing pictures)')


if __name__ == '__main__':
    main()
