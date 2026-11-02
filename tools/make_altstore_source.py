"""Write the AltStore Classic source (altstore/source.json) for a released IPA.

AltStore refuses an app whose source does not list exactly the IPA's
entitlements and privacy ("UsageDescription") keys, so both are read from the
IPA itself. The new version is placed first (AltStore treats the first entry as
latest); earlier versions stay listed. Format: https://faq.altstore.io/developers/make-a-source

Usage: python tools/make_altstore_source.py dist/v1.8.0/AACStudio-unsigned.ipa v1.8.0 "What's new"
"""
import json
import plistlib
import re
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'altstore/source.json'
REPO = 'uranrog-01/aac-studio'
RAW = f'https://raw.githubusercontent.com/{REPO}/main'


def ipa_facts(path):
    with zipfile.ZipFile(path) as z:
        info = plistlib.loads(z.read('Payload/Runner.app/Info.plist'))
        privacy = {k: v for k, v in info.items() if k.endswith('UsageDescription')}
        entitlements = set()
        for name in z.namelist():
            if name.endswith('.xcent') or name.endswith('.entitlements'):
                entitlements.update(plistlib.loads(z.read(name)))
            elif name.endswith('.appex/Info.plist'):
                ext = plistlib.loads(z.read(name))
                privacy.update({k: v for k, v in ext.items() if k.endswith('UsageDescription')})
    # Always granted by signing; AltStore says not to list them.
    entitlements -= {'application-identifier', 'com.apple.developer.team-identifier'}
    return info, privacy, sorted(entitlements)


def main():
    ipa, tag, notes = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    info, privacy, entitlements = ipa_facts(ipa)
    source = json.loads(SOURCE.read_text(encoding='utf8')) if SOURCE.exists() else None
    version = {
        'version': info['CFBundleShortVersionString'],
        'buildVersion': info['CFBundleVersion'],
        'date': date.today().isoformat(),
        'localizedDescription': notes,
        'downloadURL': f'https://github.com/{REPO}/releases/download/{tag}/{ipa.name}',
        'size': ipa.stat().st_size,
        'minOSVersion': info.get('MinimumOSVersion', '15.0'),
    }
    if source is None:
        source = {
            'name': 'AAC Studio',
            'subtitle': 'Picture-based communication for non-verbal children',
            'description': 'Open-source AAC (Augmentative and Alternative Communication) app: '
                           'tap pictures to build sentences and speak them aloud. Modern flat '
                           'pictures, offline voice, daily routines, skin tone choice.',
            'iconURL': f'{RAW}/assets/app_icon.png',
            'website': f'https://github.com/{REPO}',
            'tintColor': '#FF6E40',
            'nsfw': False,
            'featuredApps': [info['CFBundleIdentifier']],
            'apps': [{
                'name': info.get('CFBundleDisplayName', 'AAC Studio'),
                'bundleIdentifier': info['CFBundleIdentifier'],
                'developerName': 'AAC Studio',
                'subtitle': 'Tap pictures, build sentences, speak them aloud.',
                'localizedDescription':
                    'AAC Studio helps children who cannot speak, or speak little, to communicate. '
                    'Tap picture buttons to build a message and the app speaks it. Includes core '
                    'words (I, want, help, yes, no, wait), categories, Daily routines, a calm-down '
                    'page, a typing keyboard with word prediction and an offline voice. Caregivers '
                    'can edit buttons and lock settings with a code.',
                'iconURL': f'{RAW}/assets/app_icon.png',
                'tintColor': '#FF6E40',
                'category': 'lifestyle',
                'screenshots': [
                    f'{RAW}/docs/web-webkit-phone.png',
                    {'imageURL': f'{RAW}/docs/flat-symbol-preview.png', 'width': 1200, 'height': 900},
                ],
                'versions': [],
                'appPermissions': {},
            }],
            'news': [],
        }
    app = source['apps'][0]
    assert app['bundleIdentifier'] == info['CFBundleIdentifier'], 'Bundle identifier changed'
    app['versions'] = [v for v in app['versions'] if v['buildVersion'] != version['buildVersion']]
    app['versions'].insert(0, version)
    app['appPermissions'] = {'entitlements': entitlements, 'privacy': privacy}
    news_id = 'release-' + re.sub(r'[^a-z0-9]+', '-', tag.lower()).strip('-')
    if not any(n['identifier'] == news_id for n in source['news']):
        source['news'].append({'title': f'AAC Studio {version["version"]}', 'identifier': news_id,
                               'caption': notes, 'date': version['date'], 'tintColor': '#FF6E40',
                               'notify': True, 'appID': info['CFBundleIdentifier']})
    SOURCE.parent.mkdir(exist_ok=True)
    SOURCE.write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(f'{SOURCE.relative_to(ROOT)}: {app["name"]} {version["version"]} ({version["buildVersion"]}), '
          f'{len(entitlements)} entitlements, {len(privacy)} privacy keys, '
          f'{len(app["versions"])} version(s)')
    print(f'Add this URL in AltStore: {RAW}/altstore/source.json')


if __name__ == '__main__':
    main()
