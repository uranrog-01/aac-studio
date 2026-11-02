"""Validate artwork and links. --render needs Pillow and resvg-py (or CairoSVG)."""
import argparse
import io
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def asset(pack, key):
    extension = 'webp' if pack in ('noto', 'learning', 'modern3d') else 'svg'
    folder = 'twemoji' if pack == 'twemoji_svg' else pack
    return ROOT / 'assets' / 'symbols' / folder / f'{key}.{extension}'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    pack = json.loads((ROOT / 'assets/sample_pack.json').read_text(encoding='utf8'))
    index = json.loads((ROOT / 'assets/symbol_index.json').read_text(encoding='utf8'))
    files = {asset(e['p'], e['k']) for e in index}
    files.update(asset(b['symbolPack'], b['symbolKey']) for b in pack['buttons'] + pack['folders'])
    for path in files:
        if path.suffix == '.svg':
            ET.parse(path)
        else:
            raw = path.read_bytes()
            assert raw[:4] == b'RIFF' and raw[8:12] == b'WEBP', path
            assert struct.unpack('<I', raw[4:8])[0] + 8 == len(raw), path
    buttons = {b['id']: b for b in pack['buttons']}
    assert len(buttons) == len(pack['buttons']), 'Duplicate button IDs'
    folders = {f['id'] for f in pack['folders']}
    for folder, views in pack['views'].items():
        assert folder in folders
        for view in views:
            for cell in view['cells']:
                assert cell['btn'] in buttons, cell
    for b in buttons.values():
        assert b['symbolKey'] != '2b1b', f'Placeholder artwork: {b["id"]}'
        if b['kind'] == 'item':
            assert b.get('spoken', b['label']) == b['label'], f'Speech/label mismatch: {b["id"]}'
            for action in b.get('actions', []):
                if action['kind'] == 'addText':
                    assert action['data'] == b['label'], f'Message/label mismatch: {b["id"]}'
        for action in b.get('actions', []):
            if action['kind'] == 'gotoFolder': assert action['data'] in folders
    if pack.get('packVersion', 0) >= 6:
        manifest = json.loads((ROOT / 'docs/modern-symbol-manifest.json').read_text(encoding='utf8'))
        import hashlib
        for entry in manifest['assignments']:
            items = buttons if entry['kind'] == 'buttons' else {f['id']:f for f in pack['folders']}
            b = items[entry['id']]
            assert b['label'] == entry['label']
            assert b['symbolPack'] == 'modern3d' and b['symbolKey'] == entry['key'], entry
        from PIL import Image
        for key, expected in manifest['files'].items():
            path = asset('modern3d', key)
            assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, key
            image = Image.open(path)
            assert min(image.size) >= 256, (key, image.size)
            assert image.mode == 'RGBA', (key, image.mode)
            assert image.getchannel('A').getextrema() == (0,255), key
    else:
        repairs = json.loads((ROOT / 'docs/symbol-meaning-repairs.json').read_text(encoding='utf8'))
        for repair in repairs:
            b = buttons[repair['id']]
            assert [b['symbolPack'], b['symbolKey']] == repair['after'], repair
    folder_map = {f['id']: f for f in pack['folders']}
    for b in buttons.values():
        if b['kind'] == 'folder':
            target = next(a['data'] for a in b['actions'] if a['kind'] == 'gotoFolder')
            f = folder_map[target]
            assert (b['symbolPack'], b['symbolKey']) == (f['symbolPack'], f['symbolKey']), b['id']
    print(f"PASS: {len(index)} index entries; {len(files)} unique files; {len(buttons)} buttons; {len(folders)} categories")
    if args.render:
        from PIL import Image, ImageDraw
        try:
            import resvg_py
            def render_svg(path):
                return resvg_py.svg_to_bytes(svg_path=str(path), width=80, height=80)
        except ImportError:
            import cairosvg
            def render_svg(path):
                return cairosvg.svg2png(url=str(path), output_width=80, output_height=80)
        items = pack['buttons'] + pack['folders']
        for page in range((len(items)+159)//160):
            chunk = items[page*160:(page+1)*160]
            sheet = Image.new('RGB', (1200, ((len(chunk)+9)//10)*120), 'white')
            draw = ImageDraw.Draw(sheet)
            for i, b in enumerate(chunk):
                path = asset(b['symbolPack'], b['symbolKey'])
                icon = Image.open(io.BytesIO(render_svg(path))) if path.suffix=='.svg' else Image.open(path)
                icon = icon.convert('RGBA'); icon.thumbnail((76,76))
                assert icon.getbbox(), f'Empty image: {path}'
                x, y = (i%10)*120, (i//10)*120
                sheet.paste(icon, (x+(120-icon.width)//2,y), icon)
                draw.text((x+3,y+80), b['label'], fill='black')
                draw.text((x+3,y+99), b['id'], fill='#777777')
            sheet.save(ROOT / 'docs' / f'symbol-review-{page+1}.png')
        print('Rendered every starter symbol into docs/symbol-review-*.png')

if __name__ == '__main__': main()
