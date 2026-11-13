"""Builds assets/voices/clips/<code>/ from Piper recordings of every board
word, category name and sentence form in the language.

    python tools/build_voice_clips.py texts   sq <work-dir>   # list to record
    python tools/render_voice_clips_piper.py <model.onnx> <work-dir>/texts.json <work-dir>/wav
    python tools/build_voice_clips.py encode  sq <work-dir>          # MP3 + index (male)
    python tools/build_voice_clips.py encode  sq <arta-work-dir> female  # WAVs from Arta

Each clip is MP3, mono, 32 kbit/s, with silence trimmed at both ends. The
app plays them where the device has no voice for the language
(lib/engine/voice_clips.dart). Needs ffmpeg on PATH.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Foreign names the Albanian voice would spell out: how to say them.
SAY = {
    'sq': {
        'iphone': 'ajfon', 'ipod': 'ajpod', 'playstation': 'plejstejshën',
        'walkman': 'uokmen', 'wii': 'ui', 'halloween': 'hallouin', 'guy': 'gaj',
        'fawkes': 'foks', 'mx': 'miks', 'claus': 'klaus', 't-rex': 'ti reks',
        'marshmallow': 'marshmellou', 'smoothie': 'smuthi', 'trackball': 'trekboll',
        'milkshake': 'milkshejk', 'marmite': 'marmajt', 'puzzle': 'pazëll',
        'nuggets': 'nagets', 'email': 'imejl', 'bbc': 'bi bi si', 'lego': 'lego',
        'ç': 'çë',
    },
}

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
    if code == 'sq':
        found.update(('ë', 'ç'))
    keys = {}
    for text in sorted(found):
        key = normalize(text)
        if key and key not in keys:
            keys[key] = text.strip()
    phrases = sorted(keys.values(), key=normalize)
    work.mkdir(parents=True, exist_ok=True)
    (work / 'texts.json').write_text(json.dumps(phrases, ensure_ascii=False), encoding='utf8')
    say = SAY.get(code, {})
    spoken = [' '.join(say.get(word.lower(), word) for word in phrase.split()) for phrase in phrases]
    (work / 'say.json').write_text(json.dumps(spoken, ensure_ascii=False), encoding='utf8')
    print(f'{len(phrases)} phrases to record -> {work / "texts.json"}')


def encode(code, work, variant=''):
    phrases = json.loads((work / 'texts.json').read_text(encoding='utf8'))
    out = ROOT / f'assets/voices/clips/{code}{"-f" if variant == "female" else ""}'
    trim = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,'
            'areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse')
    wavs = [work / 'wav' / f'{i}.wav' for i in range(len(phrases))]
    missing = [phrase for phrase, wav in zip(phrases, wavs) if not wav.is_file()]
    if missing:
        raise SystemExit(f'{len(missing)} recordings missing: {missing[:20]}')
    keys = [normalize(text) for text in phrases]
    index = {key: hashlib.sha1(key.encode('utf8')).hexdigest()[:12] + '.mp3'
             for key in keys}
    with tempfile.TemporaryDirectory(prefix='encoded-', dir=work) as directory:
        staging = Path(directory)

        def encode_clip(pair):
            key, wav = pair
            target = staging / index[key]
            subprocess.run(['ffmpeg', '-v', 'error', '-filter_threads', '1', '-y',
                            '-i', str(wav), '-af', trim, '-ac', '1', '-ar', '22050',
                            '-c:a', 'libmp3lame', '-b:a', '32k', str(target)], check=True)
            if target.stat().st_size < 500:
                raise ValueError(f'Recording is silent or too short: {key}')

        with ThreadPoolExecutor(max_workers=6) as pool:
            for _ in pool.map(encode_clip, zip(keys, wavs)):
                pass
        out.mkdir(parents=True, exist_ok=True)
        manifest = out / 'index.json'
        previous = json.loads(manifest.read_text(encoding='utf8')) if manifest.exists() else {}
        for name in index.values():
            shutil.copyfile(staging / name, out / name)
        manifest.write_text(json.dumps(index, ensure_ascii=False, sort_keys=True,
                                       separators=(',', ':')), encoding='utf8')
        for name in set(previous.values()) - set(index.values()):
            if re.fullmatch(r'[0-9a-f]{12}\.mp3', name):
                (out / name).unlink(missing_ok=True)
    size = sum(p.stat().st_size for p in out.iterdir())
    print(f'{len(index)} clips, {size / 1048576:.1f} MB in {out}')


if __name__ == '__main__':
    command, code, work = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    if command == 'texts':
        texts(code, work)
    else:
        encode(code, work, *sys.argv[4:5])
