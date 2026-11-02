"""Modern flat as the one picture style: drop duplicate emoji sets, keep Mulberry.

- Noto, OpenMoji, OpenMoji-black and non-flag Twemoji repeat the same emoji
  that modern flat (Fluent Flat) already draws. Their files move to
  ../work/removed_flat_sets (reversible) and leave the index.
- Twemoji country/region flags stay: Fluent has none.
- Mulberry stays, rendered from its original small SVGs (assets/symbols/mulberry).
- assets/symbol_aliases.json maps saved references to removed pictures onto the
  same concept in modern flat, so custom buttons from older releases keep a picture.
- Removes unsuitable artwork (weapons) and dictionary synonyms that mislead a child.

Idempotent. Usage: python tools/modernflat_only.py
"""
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from expand_modern_flat import child_alias, normal  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FLAT = ROOT / 'assets/flat_symbols'
BACKUP = ROOT.parent / 'work/removed_flat_sets'
REMOVED_PACKS = ('noto', 'openmoji', 'openmoji_black')
UNSUITABLE = {'vocab-rifle'}


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def write(path, value, compact=False):
    text = (json.dumps(value, ensure_ascii=False, separators=(',', ':')) if compact
            else json.dumps(value, ensure_ascii=False, indent=1) + '\n')
    path.write_text(text, encoding='utf8')


def hexcode(key):
    parts = key.lower().replace('emoji_u', '').replace('_', '-').split('-')
    return '-'.join(p.lstrip('u').upper() for p in parts if p and p.lstrip('u') != 'fe0f')


def concept(name):
    """'Man golfing: medium-light skin tone' == 'man golfing: medium light skin tone'."""
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', name.lower())).strip()


def move(path, folder):
    if path.exists():
        target = BACKUP / folder / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), str(target))


def main():
    index = read(ROOT / 'assets/symbol_index.json')
    manifest = read(ROOT / 'docs/flat-symbol-manifest.json')
    approved_path = ROOT / 'docs/modern-flat-expansion-assets.json'
    approved = read(approved_path)
    aliases_path = ROOT / 'assets/symbol_aliases.json'
    aliases = read(aliases_path) if aliases_path.exists() else {}

    def is_flag(e):
        return e['p'] == 'twemoji' and e['n'].lower().startswith('flag')

    def removed(e):
        return e['p'] in REMOVED_PACKS or (e['p'] == 'twemoji' and not is_flag(e)) or e['k'] in UNSUITABLE

    # Map removed pictures onto the same modern flat concept (by CLDR name).
    modern = {}
    for e in index:
        if e['p'] == 'modernflat' and e['k'] not in UNSUITABLE:
            modern.setdefault(concept(e['n']), e['k'])
    hex_names = {hexcode(e['k']): e['n'] for e in index
                 if e['p'] in ('twemoji', 'openmoji') and not re.fullmatch(r'[0-9a-fu_ -]+', e['n'], re.I)}
    for e in index:
        if removed(e) and e['p'] != 'modernflat':
            target = modern.get(concept(e['n'])) or modern.get(concept(hex_names.get(hexcode(e['k']), '')))
            if target:
                aliases.setdefault(f"{e['p']}/{e['k']}", target)

    gone = [e for e in index if removed(e)]
    index = [e for e in index if not removed(e)]

    # Dictionary synonyms only where they help a child and point to this picture.
    common = set((ROOT / 'assets/prediction_en_top10k.txt').read_text(encoding='utf8').lower().split())
    labels = {}
    for e in index:
        if e['p'] in ('modernflat', 'mulberry'):
            labels.setdefault(normal(e['n']), set()).add(e['k'])
    kept = []
    for e in index:
        item = approved.get(e['k']) if e['p'] == 'modernflat' else None
        if item and normal(e['n']) != normal(item['label']):
            taken = {n for n, keys in labels.items() if keys - {e['k']}}
            if not child_alias(e['n'], item['label'], taken, common):
                continue
        kept.append(e)
    dropped_aliases = len(index) - len(kept)
    index = kept

    # Files: removed emoji sets, non-flag Twemoji, Mulberry WebP copies, weapons.
    for pack in REMOVED_PACKS:
        for path in sorted((FLAT / pack).glob('*.webp')) if (FLAT / pack).exists() else []:
            move(path, pack)
        if (FLAT / pack).exists() and not any((FLAT / pack).iterdir()):
            (FLAT / pack).rmdir()
    flags = {e['k'] for e in index if e['p'] == 'twemoji'}
    for path in sorted((FLAT / 'twemoji').glob('*.webp')):
        if path.stem not in flags:
            move(path, 'twemoji')
    for path in sorted((FLAT / 'mulberry').glob('*.webp')) if (FLAT / 'mulberry').exists() else []:
        move(path, 'mulberry-webp')
    if (FLAT / 'mulberry').exists() and not any((FLAT / 'mulberry').iterdir()):
        (FLAT / 'mulberry').rmdir()
    for key in UNSUITABLE:
        move(FLAT / 'modernflat' / f'{key}.webp', 'unsuitable')
        approved.pop(key, None)
        manifest['generatedScenes'].pop(key, None)

    files = {rel: digest for rel, digest in manifest['files'].items() if (FLAT / rel).exists()}
    manifest['files'] = files
    manifest['fileCount'] = len(files)
    counts = {}
    for rel in files:
        counts[rel.split('/')[0]] = counts.get(rel.split('/')[0], 0) + 1
    counts['mulberry'] = len(list((ROOT / 'assets/symbols/mulberry').glob('*.svg')))
    manifest['counts'] = counts
    manifest['bytes'] = sum((FLAT / rel).stat().st_size for rel in files)
    manifest['indexNames'] = len(index)
    manifest['uniqueIndexedPictures'] = len({(e['p'], e['k']) for e in index})
    manifest['additionalReviewedArtworks'] = len(approved)
    manifest['style'] = 'Modern flat 2D; Mulberry SVG for AAC words not yet drawn; Twemoji flags'
    manifest['removedDuplicateSets'] = {
        'packs': [*REMOVED_PACKS, 'twemoji (non-flag)'],
        'reason': 'Repeated emoji that modern flat already draws; files kept in work/removed_flat_sets',
        'aliases': 'assets/symbol_aliases.json'}

    write(ROOT / 'assets/symbol_index.json', index, compact=True)
    write(aliases_path, dict(sorted(aliases.items())), compact=True)
    write(ROOT / 'docs/flat-symbol-manifest.json', manifest)
    write(approved_path, approved)
    print(f'Removed {len(gone)} index rows ({len({(e["p"], e["k"]) for e in gone})} pictures); '
          f'dropped {dropped_aliases} misleading synonyms; {len(aliases)} old references mapped; '
          f'{manifest["uniqueIndexedPictures"]} pictures remain.')


if __name__ == '__main__':
    main()
