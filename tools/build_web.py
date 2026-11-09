"""Build a self-contained PWA with a bounded starter-board offline cache.

Run from studio: python tools/build_web.py [--flutter C:/tools/flutter/bin/flutter.bat]
Upload the CONTENTS of build/web-pwa to a static HTTPS host. No signing credentials.
"""
import argparse
import hashlib
import json
import re
import re
from pathlib import Path
import subprocess
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/web-pwa'


def finalize(output: Path, archive_target: Path | None = None):
    # Recent Flutter releases no longer always emit version.json. Read the
    # source version so packaging never depends on an old generated file.
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
                      (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
    if not match:
        raise RuntimeError('Expected version: major.minor.patch+build in pubspec.yaml')
    version, build_number = match.groups()
    (output / 'version.json').write_text(json.dumps({
        'app_name': 'aac_studio', 'version': version,
        'build_number': build_number, 'package_name': 'aac_studio',
    }), encoding='utf-8')
    shutil.copyfile(ROOT / 'web/app_bridge.js', output / 'app_bridge.js')
    for pattern in ['main.*.dart.js', 'app_bridge.*.js', 'flutter_bootstrap.*.js', 'picture_cache.*.js']:
        for generated in output.glob(pattern): generated.unlink()
    index = (output / 'index.html').read_text(encoding='utf-8')
    index = re.sub(r'(app_bridge|flutter_bootstrap|picture_cache)\.[a-f0-9]{20}\.js', r'\1.js', index)
    (output / 'index.html').write_text(index, encoding='utf-8')
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
        # The v11 word library (thousands of pictures) is not part of the
        # first install: its pictures download when a page is opened, or
        # all together with "Save all pictures offline".
        if str(item.get('id', '')).startswith('v11_'):
            continue
        folder, key = item.get('symbolPack'), item.get('symbolKey')
        if folder and key:
            folder = {'modern3d': 'modernflat', 'twemoji_svg': 'twemoji'}.get(folder, folder)
            starter.add(f'assets/assets/symbols/mulberry/{key}.svg' if folder == 'mulberry'
                        else f'assets/assets/flat_symbols/{folder}/{key}.webp')
    symbols = sorted(p.relative_to(output).as_posix()
                     for parent in ['assets/assets/flat_symbols', 'assets/assets/symbols/mulberry']
                     for p in (output / parent).rglob('*') if p.is_file() and p.suffix in {'.webp', '.svg'})
    hashes = {path: hashlib.sha256((output / path).read_bytes()).hexdigest() for path in symbols}
    picture_script = (ROOT / 'web/picture_cache.js').read_text(encoding='utf-8')
    (output / 'picture_cache.js').write_text(picture_script.replace('__PICTURE_HASHES__', json.dumps(hashes)), encoding='utf-8')
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
    digest.update((ROOT / 'web/aac-sw.js').read_bytes())
    for path in core:
        digest.update(path.encode())
        digest.update((output / path).read_bytes())
    build_id = digest.hexdigest()[:20]
    # Unique script URLs prevent an older worker/browser cache serving old UI
    # inside a new HTML shell. Aliases remain available for older clients.
    helper_id = hashlib.sha256((output / 'picture_cache.js').read_bytes()).hexdigest()[:20]
    names = {
        'main.dart.js': f'main.{build_id}.dart.js',
        'app_bridge.js': f'app_bridge.{build_id}.js',
        'flutter_bootstrap.js': f'flutter_bootstrap.{build_id}.js',
        'picture_cache.js': f'picture_cache.{helper_id}.js',
    }
    for original, generated in names.items():
        content = (output / original).read_text(encoding='utf-8')
        if original == 'app_bridge.js': content = content.replace('__BUILD_ID__', build_id)
        if original == 'flutter_bootstrap.js': content = content.replace('main.dart.js', names['main.dart.js'])
        (output / generated).write_text(content, encoding='utf-8')
    for original, generated in names.items(): index = index.replace(original, generated)
    (output / 'index.html').write_text(index, encoding='utf-8')
    core = [names.get(path, path) for path in core]
    bridge = (output / 'app_bridge.js').read_text(encoding='utf-8').replace('__BUILD_ID__', build_id)
    (output / 'app_bridge.js').write_text(bridge, encoding='utf-8')
    worker = (ROOT / 'web/aac-sw.js').read_text(encoding='utf-8')
    worker = worker.replace('__CORE_FILES__', json.dumps(core)).replace('__BUILD_ID__', build_id).replace("importScripts('picture_cache.js')", f"importScripts('{names['picture_cache.js']}')")
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
    target = archive_target or ROOT / f'dist/v{version}/AACStudio-{version}-web.zip'
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
    parser.add_argument('--output', type=Path, default=OUTPUT,
                        help='Generated web directory inside studio/build')
    parser.add_argument('--archive', type=Path,
                        help='Optional destination ZIP for this invocation')
    args = parser.parse_args()
    output = args.output.resolve()
    build_root = (ROOT / 'build').resolve()
    if output == build_root or not output.is_relative_to(build_root):
        raise ValueError('Web output must be a subdirectory of studio/build')
    if not args.finalize_only:
        # This is generated output only. Verify the exact absolute target first.
        if output.exists(): shutil.rmtree(output)
        subprocess.run([args.flutter, 'build', 'web', '--release',
                        '--no-web-resources-cdn', '--no-wasm-dry-run',
                        '--base-href', args.base_href, '--output', str(output)], cwd=ROOT, check=True)
    finalize(output, args.archive)
