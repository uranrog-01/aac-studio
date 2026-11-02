"""Build a self-contained PWA with a bounded starter-board offline cache.

Run from studio: python tools/build_web.py [--flutter C:/tools/flutter/bin/flutter.bat]
Upload the CONTENTS of build/web-pwa to a static HTTPS host. No signing credentials.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/web-pwa'


def finalize(output: Path):
    shutil.copyfile(ROOT / 'web/app_bridge.js', output / 'app_bridge.js')
    # Native voice data is unnecessary in a browser; never change source assets.
    native_voice = output / 'assets/assets/voices/piper-en-us-ljspeech-medium.tar.bz2'
    native_voice.unlink(missing_ok=True)
    for package in ['piper_phonemize', 'sherpa_onnx', 'sherpa_onnx_web']:
        for file in (output / 'assets/packages' / package).rglob('*'):
            if file.is_file(): file.unlink()
    for file in (output / 'canvaskit').rglob('*'):
        if file.is_file() and file.relative_to(output / 'canvaskit').as_posix() not in {'canvaskit.js', 'canvaskit.wasm'}:
            file.unlink()
    pack = json.loads((output / 'assets/assets/sample_pack.json').read_text(encoding='utf-8'))
    starter = set()
    for item in pack['buttons'] + pack['folders']:
        folder, key = item.get('symbolPack'), item.get('symbolKey')
        if folder and key:
            folder = {'modern3d': 'modernflat', 'twemoji_svg': 'twemoji'}.get(folder, folder)
            starter.add(f'assets/assets/symbols/mulberry/{key}.svg' if folder == 'mulberry'
                        else f'assets/assets/flat_symbols/{folder}/{key}.webp')
    # Emergency picture words also appear in the typing screen.
    keyboard = (ROOT / 'lib/features/grid/keyboard_view.dart').read_text(encoding='utf-8')
    starter.update(f'assets/assets/flat_symbols/modernflat/{key}.webp'
                   for key in re.findall(r"pack: 'modernflat', key: '([^']+)'", keyboard))
    symbols = sorted(p.relative_to(output).as_posix()
                     for parent in ['assets/assets/flat_symbols', 'assets/assets/symbols/mulberry']
                     for p in (output / parent).rglob('*') if p.is_file() and p.suffix in {'.webp', '.svg'})
    # Keep runtime, fonts, JSON, icons and CanvasKit local for offline startup.
    core = sorted(p.relative_to(output).as_posix() for p in output.rglob('*')
                  if p.is_file() and '/flat_symbols/' not in p.as_posix() and '/symbols/mulberry/' not in p.as_posix()
                  and p.name not in {'aac-sw.js', 'flutter_service_worker.js',
                                     '.last_build_id', 'offline-symbols.json', 'web-build.json'}
                  and not p.name.endswith('.map'))
    core = sorted(set(core) | starter)
    missing = [p for p in core if not (output / p).is_file()]
    if missing:
        raise RuntimeError(f'Missing starter images: {missing}')
    (output / 'offline-symbols.json').write_text(json.dumps(symbols), encoding='utf-8')
    core.append('offline-symbols.json')
    digest = hashlib.sha256()
    for path in core:
        digest.update(path.encode())
        digest.update((output / path).read_bytes())
    build_id = digest.hexdigest()[:20]
    bridge = (output / 'app_bridge.js').read_text(encoding='utf-8').replace('__BUILD_ID__', build_id)
    (output / 'app_bridge.js').write_text(bridge, encoding='utf-8')
    worker = (ROOT / 'web/aac-sw.js').read_text(encoding='utf-8')
    worker = worker.replace('__CORE_FILES__', json.dumps(core)).replace('__BUILD_ID__', build_id)
    (output / 'aac-sw.js').write_text(worker, encoding='utf-8')
    # Prevent an obsolete generated Flutter worker from competing for the scope.
    (output / 'flutter_service_worker.js').unlink(missing_ok=True)
    report = {
        'buildId': build_id, 'symbolFiles': len(symbols),
        'starterPictures': len(starter), 'coreFiles': len(core),
        'starterDownloadBytes': sum((output / p).stat().st_size for p in core),
        'allPicturesBytes': sum((output / p).stat().st_size for p in symbols),
        'requiresHttps': True, 'iphoneDeviceTested': False,
    }
    (output / 'web-build.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    version = json.loads((output / 'version.json').read_text(encoding='utf-8'))['version']
    target = ROOT / f'dist/v{version}/AACStudio-{version}-web.zip'
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in sorted(output.rglob('*')):
            if file.is_file(): archive.write(file, file.relative_to(output).as_posix())
    checksum = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix('.zip.sha256').write_text(f'{checksum}  {target.name}\n', encoding='utf-8')
    print(json.dumps(report, indent=2))
    print(f'Web package: {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default='C:/tools/flutter/bin/flutter.bat')
    parser.add_argument('--finalize-only', action='store_true')
    parser.add_argument('--base-href', default='/')
    args = parser.parse_args()
    if not args.finalize_only:
        # This is generated output only. Verify the exact absolute target first.
        resolved = OUTPUT.resolve()
        assert resolved == (ROOT.resolve() / 'build' / 'web-pwa')
        assert resolved.is_relative_to(ROOT.resolve() / 'build')
        if resolved.exists(): shutil.rmtree(resolved)
        subprocess.run([args.flutter, 'build', 'web', '--release',
                        '--no-web-resources-cdn', '--no-wasm-dry-run',
                        '--base-href', args.base_href, '--output', str(OUTPUT)], cwd=ROOT, check=True)
    finalize(OUTPUT)
