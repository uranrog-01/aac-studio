"""Builds assets/voices/clips/<code>/ from recordings made by
tool/render_voice_clips.dart: every board word, category name and sentence
form of a language, spoken by that language's own voice.

    python tools/build_voice_clips.py texts   sq <work-dir>   # list to record
    dart run tool/render_voice_clips.dart sq <work-dir> <work-dir>/cache <work-dir>/texts.json <work-dir>/wav
    python tools/build_voice_clips.py encode  sq <work-dir>   # MP3 + index

Each clip is MP3, mono, 32 kbit/s, with silence trimmed at both ends. The
app plays them where the device has no voice for the language
(lib/engine/voice_clips.dart). Needs ffmpeg on PATH.
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def normalize(text):
    text = re.sub(r'\s+', ' ', text.strip().lower())
    return re.sub(r'^[\s.,!?;:]+|[\s.,!?;:]+$', '', text)


def texts(code, work):
    data = json.loads((ROOT / f'assets/i18n/{code}.json').read_text(encoding='utf8'))
    pack = json.loads((ROOT / 'assets/sample_pack.json').read_text(encoding='utf8'))
    found = set()
    for section in ('words', 'words_f', 'forms', 'forms_f'):
        found.update(data.get(section, {}).values())
    for button in pack['buttons']:
        if button.get('class') in ('letter', 'number'):
            label = button['label']
            found.add(label.lower() if len(label) == 1 else label)
    keys = {}
    for text in sorted(found):
        key = normalize(text)
        if key and key not in keys:
            keys[key] = text.strip()
    phrases = sorted(keys.values(), key=normalize)
    work.mkdir(parents=True, exist_ok=True)
    (work / 'texts.json').write_text(json.dumps(phrases, ensure_ascii=False), encoding='utf8')
    print(f'{len(phrases)} phrases to record -> {work / "texts.json"}')


def encode(code, work):
    phrases = json.loads((work / 'texts.json').read_text(encoding='utf8'))
    out = ROOT / f'assets/voices/clips/{code}'
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    trim = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,'
            'areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse')
    index, missing = {}, []
    for i, text in enumerate(phrases):
        wav = work / 'wav' / f'{i}.wav'
        if not wav.exists():
            missing.append(text)
            continue
        key = normalize(text)
        name = hashlib.sha1(key.encode('utf8')).hexdigest()[:12] + '.mp3'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-af', trim, '-ac', '1',
                        '-ar', '22050', '-c:a', 'libmp3lame', '-b:a', '32k', str(out / name)],
                       check=True)
        index[key] = name
    (out / 'index.json').write_text(json.dumps(index, ensure_ascii=False, sort_keys=True,
                                               separators=(',', ':')), encoding='utf8')
    size = sum(p.stat().st_size for p in out.iterdir())
    print(f'{len(index)} clips, {size / 1048576:.1f} MB in {out}; {len(missing)} not recorded')
    if missing:
        print('  not recorded:', missing[:20])


if __name__ == '__main__':
    command, code, work = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    {'texts': texts, 'encode': encode}[command](code, work)
