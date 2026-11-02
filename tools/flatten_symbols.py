"""Build the entire bundled symbol library as flat, <=340px, transparent WebP.

--prepare renders existing flat vector/raster collections and pinned Fluent Flat
sources. --apply installs the separately generated flat action illustrations,
updates the starter pack and writes a complete, reproducible output manifest.
Original source artwork is retained under assets/symbols but is not bundled.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

from PIL import Image
import resvg_py

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT.parent / 'work/flat_symbol_sources'
DEST = ROOT / 'assets/flat_symbols'
SOURCE = ROOT / 'assets/symbols'
REVISION = '1ffb34c752ecf5d402f04cfb4b392c77f57c54bc'
BASE = f'https://raw.githubusercontent.com/microsoft/fluentui-emoji/{REVISION}/'
MAX_SIDE = 340
ENCODING_MARKER = b'<x:xmpmeta xmlns:x="adobe:ns:meta/">AAC-flat-WebP-q94-v1</x:xmpmeta>'
PACKS = ('twemoji', 'noto', 'openmoji', 'openmoji_black', 'mulberry',
         'communication', 'learning')
EXTRA_SCENES = {
    'bye': 'GOODBYE: a friendly child in a blue shirt standing just outside an open doorway, looking back toward the viewer and raising one hand in a clear farewell wave. The door and a small step imply leaving; the waving child is the main focus.',
    'break': 'TAKE A BREAK: a friendly person sitting comfortably upright on a simple chair, hands relaxed on their lap, a closed blue book resting on a small desk beside them. Calm open eyes and relaxed smile. Clearly a short rest from an activity, not sleeping, not injury, no broken objects.',
    'too-loud': 'TOO LOUD: a friendly person visibly covering both ears with their own hands, eyebrows showing mild discomfort, with three simple red sound waves from a small loudspeaker beside them. Clear ear-covering response to excessive sound. Not anger, not crying, no violence.',
}


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf8')


def fluent_tree():
    path = ROOT.parent / 'work/modern_symbol_sources/fluent-emoji-tree.json'
    if not path.exists():
        request = urllib.request.Request(
            f'https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/{REVISION}?recursive=1',
            headers={'User-Agent':'AAC-Studio'})
        write(path, json.load(urllib.request.urlopen(request, timeout=90)))
    tree = read(path)
    assert not tree.get('truncated'), 'Incomplete Fluent source catalog'
    return tree


def flat_path(source3d, paths):
    """Exact same Fluent concept and skin-tone variant, never fuzzy matching."""
    candidate = source3d.replace('/3D/', '/Flat/').replace('_3d', '_flat').replace('.png', '.svg')
    if candidate not in paths:
        raise ValueError(f'No exact flat variant: {source3d}')
    return candidate


def download(job):
    key, source = job
    path = CACHE / 'fluent' / f'{key}.svg'
    if not path.exists():
        request = urllib.request.Request(BASE + urllib.parse.quote(source),
                                         headers={'User-Agent': 'AAC-Studio'})
        for attempt in range(3):
            try:
                path.write_bytes(urllib.request.urlopen(request, timeout=90).read())
                break
            except Exception:
                if attempt == 2:
                    raise
    ET.parse(path)
    return path


def render(job):
    source, output = map(Path, job[:2])
    force = len(job) > 2 and job[2]
    if not force and output.exists() and output.stat().st_mtime >= source.stat().st_mtime:
        with Image.open(output) as image:
            if max(image.size) <= MAX_SIDE and image.format == 'WEBP':
                return
    if source.suffix == '.svg':
        document = ET.parse(source).getroot()
        bounds = re.split(r'[\s,]+', document.attrib.get('viewBox', '').strip())
        if len(bounds) == 4:
            w, h = float(bounds[2]), float(bounds[3])
        else:
            w, h = [float(re.sub(r'[^0-9.]', '', document.attrib.get(k, '128')))
                    for k in ('width', 'height')]
        scale = MAX_SIDE * 2 / max(w, h)
        image = Image.open(io.BytesIO(resvg_py.svg_to_bytes(
            svg_path=str(source), width=max(1, round(w*scale)),
            height=max(1, round(h*scale)))))
    else:
        image = Image.open(source)
    image = image.convert('RGBA')
    image.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
    # Preserve native resolution for smaller raster originals. A 128px picture
    # inside a 340px canvas would appear tiny under Flutter's BoxFit.contain.
    side = max(image.size)
    canvas = Image.new('RGBA', (side, side))
    canvas.paste(image, ((side-image.width)//2, (side-image.height)//2))
    if canvas.getchannel('A').getbbox() is None:
        raise ValueError(f'Empty artwork: {source}')
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, 'WEBP', lossless=True, quality=100, method=4, exact=True)
    with Image.open(output) as decoded:
        assert decoded.convert('RGBA').tobytes() == canvas.tobytes(), output


def optimize(path):
    """Use quality-94 encoding only when smaller; preserve alpha exactly.

    The marker prevents repeated lossy recompression on later exporter runs.
    Simpler flat line art usually keeps its smaller lossless encoding.
    """
    image = Image.open(path)
    if image.info.get('xmp') == ENCODING_MARKER:
        return
    image = image.convert('RGBA')
    output = io.BytesIO()
    image.save(output, 'WEBP', quality=94, method=4, exact=True, xmp=ENCODING_MARKER)
    raw = output.getvalue()
    if len(raw) < path.stat().st_size:
        decoded = Image.open(io.BytesIO(raw)).convert('RGBA')
        assert decoded.getchannel('A').tobytes() == image.getchannel('A').tobytes(), path
        path.write_bytes(raw)


def prepare():
    (CACHE / 'fluent').mkdir(parents=True, exist_ok=True)
    modern = read(ROOT / 'docs/modern-symbol-manifest.json')
    tree = fluent_tree()
    paths = {e['path'] for e in tree['tree']}
    fluent = {key: flat_path(path, paths) for key, path in modern['fluentSources'].items()}
    write(CACHE / 'fluent_sources.json', fluent)
    with ThreadPoolExecutor(max_workers=12) as pool:
        list(pool.map(download, fluent.items()))
    jobs = []
    for pack in PACKS:
        for file in sorted((SOURCE / pack).iterdir()):
            if file.suffix.lower() in ('.svg', '.webp', '.png'):
                source = CACHE/f'type-{file.stem}.svg' if pack == 'learning' else file
                jobs.append((str(source), str(DEST / pack / (file.stem + '.webp'))))
    jobs.extend((str(CACHE/'fluent'/f'{key}.svg'), str(DEST/'modernflat'/f'{key}.webp'))
                for key in fluent)
    # Code-native letter/number and color indicators: solid fills, no extrusion.
    for text in [*'ABCDEFGHIJKLMNOPQRSTUVWXYZ', *map(str, range(21)), 'ABC', '123']:
        size = 82 if len(text) == 1 else 65 if len(text) == 2 else 53
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><text x="64" y="85" text-anchor="middle" font-family="Segoe UI" font-weight="700" font-size="{size}" fill="#2475BD">{text}</text></svg>'''
        path = CACHE / f'type-{text.lower()}.svg'
        path.write_text(svg, encoding='utf8')
        jobs.append((str(path), str(DEST/'modernflat'/f'type-{text.lower()}.webp')))
    colors = {'red':'#F04452','blue':'#247DEC','green':'#42AB64','yellow':'#F9CE35',
              'purple':'#9659CC','orange':'#F79A2E','pink':'#ED8AB8','brown':'#966748',
              'black':'#303840','white':'#FFFFFF','gray':'#9BA8B6'}
    for name, color in colors.items():
        path = CACHE/f'color-{name}.svg'
        path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><circle cx="64" cy="64" r="49" fill="{color}" stroke="{color if name != "white" else "#B8C2CC"}" stroke-width="3"/></svg>', encoding='utf8')
        jobs.append((str(path), str(DEST/'modernflat'/f'color-{name}.webp')))
    with ProcessPoolExecutor(max_workers=8) as pool:
        for number, _ in enumerate(pool.map(render, jobs, chunksize=12), 1):
            if number % 1000 == 0:
                print(f'Rendered {number}/{len(jobs)}', flush=True)
    write(CACHE/'render_sources.json', jobs)
    write(CACHE/'generation_jobs.json', {**modern['generatedScenes'], **EXTRA_SCENES})
    print(f'Prepared {len(jobs)} flat WebP assets; custom scenes remain for --apply.', flush=True)


def expand():
    """Add the complete Fluent flat collection, beyond the starter vocabulary."""
    (CACHE / 'fluent').mkdir(parents=True, exist_ok=True)
    tree = fluent_tree()
    modern = read(ROOT/'docs/modern-symbol-manifest.json')
    existing = set(modern['fluentSources'])
    sources, entries = {}, []
    for item in tree['tree']:
        path = item['path']
        if item['type'] != 'blob' or '/Flat/' not in path or not path.endswith('.svg'):
            continue
        parts = path.split('/')
        tone = parts[2] if len(parts) == 5 else 'Default'
        title = parts[1]
        key = 'fluent-' + re.sub('[^a-z0-9]+', '-', title.lower()).strip('-')
        if tone != 'Default':
            key += '-' + tone.lower()
            title += ': ' + tone.lower().replace('-', ' ') + ' skin tone'
        assert key not in sources, key
        sources[key] = path
        entries.append({'p':'modernflat', 'k':key, 'n':title})
    extra = {k:v for k,v in sources.items() if k not in existing}
    with ThreadPoolExecutor(max_workers=16) as pool:
        for number, _ in enumerate(pool.map(download, extra.items()), 1):
            if number % 500 == 0:
                print(f'Downloaded {number}/{len(extra)} extra flat illustrations', flush=True)
    jobs = [(str(CACHE/'fluent'/f'{k}.svg'), str(DEST/'modernflat'/f'{k}.webp')) for k in extra]
    with ProcessPoolExecutor(max_workers=6) as pool:
        list(pool.map(render, jobs, chunksize=12))
    write(CACHE/'expanded_fluent_sources.json', sources)
    write(CACHE/'expanded_entries.json', entries)
    print(f'Expanded modern flat collection to {len(sources)} Fluent illustrations.', flush=True)


def refresh_small():
    jobs = []
    for file in sorted((SOURCE/'noto').glob('*.webp')):
        with Image.open(file) as image:
            if max(image.size) < MAX_SIDE:
                jobs.append((str(file), str(DEST/'noto'/file.name), True))
    # Legacy number references share the new solid-fill typography design.
    for file in sorted((SOURCE/'learning').glob('*.webp')):
        source = CACHE/f'type-{file.stem}.svg'
        assert source.exists(), source
        jobs.append((str(source), str(DEST/'learning'/file.name), True))
    with ProcessPoolExecutor(max_workers=8) as pool:
        list(pool.map(render, jobs, chunksize=16))
    print(f'Removed extra padding / refreshed flat number cards: {len(jobs)} files.', flush=True)


def apply():
    modern = read(ROOT / 'docs/modern-symbol-manifest.json')
    generated = read(CACHE / 'generation_manifest.json')
    scenes = {**modern['generatedScenes'], **EXTRA_SCENES}
    assert set(generated) == set(scenes), 'Missing flat scene originals'
    for key, path in generated.items():
        render((path, DEST/'modernflat'/f'scene-{key}.webp'))
    # Keep the separately reviewed 10k expansion when rebuilding base exports.
    extra_path = ROOT/'docs/modern-flat-expansion-assets.json'
    approved_expansion = read(extra_path) if extra_path.exists() else {}
    for key, item in approved_expansion.items():
        assert (DEST/'modernflat'/f'{key}.webp').exists(), key
        scenes[key] = item['scene']
    encoding_path = CACHE/'encoding_status.json'
    encoded = read(encoding_path) if encoding_path.exists() else {}
    exports = sorted(DEST.glob('*/*.webp'))
    def stamp(path):
        stat = path.stat()
        return [stat.st_size, stat.st_mtime_ns]
    pending = [p for p in exports if encoded.get(p.relative_to(DEST).as_posix()) != stamp(p)]
    with ProcessPoolExecutor(max_workers=8) as pool:
        for number, _ in enumerate(pool.map(optimize, pending, chunksize=24), 1):
            if number % 5000 == 0:
                print(f'Checked WebP encoding {number}', flush=True)
    write(encoding_path, {p.relative_to(DEST).as_posix():stamp(p) for p in exports})
    pack = read(ROOT/'assets/sample_pack.json')
    history = read(ROOT/'assets/factory_symbol_history.json')
    for kind in ('buttons', 'folders'):
        for item in pack[kind]:
            ref = {k:item.get(k) for k in ('label','symbol','symbolPack','symbolKey')}
            refs = history[kind].setdefault(item['id'], [])
            if ref not in refs:
                refs.append(ref)
            if item['symbolPack'] == 'modern3d':
                item['symbolPack'] = 'modernflat'
            replacements = {'b22':'scene-bye',
                            'core_yes':'fluent-person-gesturing-ok',
                            'core_no':'fluent-person-gesturing-no',
                            'core_wait':'fluent-hourglass-not-done',
                            'calm_break':'scene-break', 'calm_loud':'scene-too-loud'}
            if kind == 'buttons' and item['id'] in replacements:
                item['symbolPack'] = 'modernflat'
                item['symbolKey'] = replacements[item['id']]
            assert (DEST/item['symbolPack']/f'{item["symbolKey"]}.webp').exists(), item
    pack['packVersion'] = 8
    index = read(ROOT/'assets/symbol_index.json')
    for entry in index:
        if entry['p'] == 'modern3d':
            entry['p'] = 'modernflat'
        folder = 'twemoji' if entry['p'] == 'twemoji_svg' else entry['p']
        assert (DEST/folder/f'{entry["k"]}.webp').exists(), entry
    if (CACHE/'expanded_entries.json').exists():
        seen = {(e['p'],e['k'],e['n'].casefold()) for e in index}
        for entry in read(CACHE/'expanded_entries.json'):
            identity = (entry['p'],entry['k'],entry['n'].casefold())
            if identity not in seen:
                index.append(entry)
                seen.add(identity)
    for kind in ('buttons','folders'):
        for item in pack[kind]:
            entry = {'p':item['symbolPack'], 'k':item['symbolKey'], 'n':item['label']}
            if entry not in index:
                index.append(entry)
    files = {}
    counts = {}
    total_bytes = 0
    for path in sorted(DEST.glob('*/*.webp')):
        with Image.open(path) as image:
            image.load()
            assert image.format == 'WEBP' and 0 < min(image.size) <= max(image.size) <= 340, path
            assert image.convert('RGBA').getchannel('A').getbbox(), path
        files[path.relative_to(DEST).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        counts[path.parent.name] = counts.get(path.parent.name,0) + 1
        total_bytes += path.stat().st_size
    fluent_sources = read(CACHE/'fluent_sources.json')
    if (CACHE/'expanded_fluent_sources.json').exists():
        fluent_sources.update(read(CACHE/'expanded_fluent_sources.json'))
    manifest = {'style':'Flat 2D', 'format':'WebP; smaller of lossless and quality 94, with lossless alpha', 'maxWidth':340, 'maxHeight':340,
                'fluentRevision':REVISION, 'fluentSources':fluent_sources,
                'generatedScenes':scenes,
                'assignments':[{'kind':kind, 'id':item['id'], 'label':item['label'],
                                'pack':item['symbolPack'], 'key':item['symbolKey']}
                               for kind in ('buttons','folders') for item in pack[kind]],
                'fileCount':len(files), 'indexNames':len(index),
                'uniqueIndexedPictures':len({(e['p'],e['k']) for e in index}),
                'counts':counts, 'bytes':total_bytes, 'files':files,
                'rendering':'Original flat vector artwork and exact Fluent Flat variants; at most 340px, smaller raster originals retain native resolution without added padding. Generated scenes exported with LANCZOS resampling. No original 3D images used.'}
    write(ROOT/'docs/flat-symbol-manifest.json', manifest)
    write(ROOT/'assets/factory_symbol_history.json', history)
    write(ROOT/'assets/sample_pack.json', pack)
    (ROOT/'assets/symbol_index.json').write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')), encoding='utf8')
    print(f'Applied {len(files)} flat WebP pictures ({total_bytes/1e6:.1f} MB), {len(index)} searchable names.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--expand', action='store_true')
    parser.add_argument('--refresh-small', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.prepare:
        prepare()
    if args.expand:
        expand()
    if args.refresh_small:
        refresh_small()
    if args.apply:
        apply()
