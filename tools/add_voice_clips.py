"""Records a few new Albanian phrases into the shipped clip sets without
re-recording everything (same voice, pace, trimming and MP3 settings as
tools/build_voice_clips.py). Run with the Piper virtualenv's Python:

    <piper-venv>/python tools/add_voice_clips.py <model.onnx> <sq|sq-f> "phrase" ...
"""
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

from piper import PiperVoice, SynthesisConfig

ROOT = Path(__file__).resolve().parents[1]
TRIM = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,'
        'areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse')


def normalize(text):
    text = re.sub(r'\s+', ' ', text.strip().lower())
    return re.sub(r'^[\s.,!?;:]+|[\s.,!?;:]+$', '', text)


def main():
    model, folder, phrases = sys.argv[1], sys.argv[2], sys.argv[3:]
    out = ROOT / 'assets/voices/clips' / folder
    manifest = out / 'index.json'
    index = json.loads(manifest.read_text(encoding='utf8'))
    voice = PiperVoice.load(model)
    config = SynthesisConfig(length_scale=1.25)
    with tempfile.TemporaryDirectory() as tmp:
        for text in phrases:
            key = normalize(text)
            name = hashlib.sha1(key.encode('utf8')).hexdigest()[:12] + '.mp3'
            spoken = text.strip() if re.search(r'[.!?…]$', text.strip()) else text.strip() + '.'
            wav = Path(tmp) / 'clip.wav'
            with wave.open(str(wav), 'wb') as w:
                voice.synthesize_wav(spoken, w, syn_config=config)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-af', TRIM, '-ac', '1',
                            '-ar', '22050', '-c:a', 'libmp3lame', '-b:a', '32k', str(out / name)],
                           check=True)
            if (out / name).stat().st_size < 500:
                raise SystemExit(f'Recording is silent or too short: {text}')
            index[key] = name
            print(folder, key, '->', name)
    manifest.write_text(json.dumps(index, ensure_ascii=False, sort_keys=True, separators=(',', ':')),
                        encoding='utf8')


if __name__ == '__main__':
    main()
