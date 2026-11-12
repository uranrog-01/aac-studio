"""Records phrases with the official Piper program (pip install piper-tts),
the reference implementation for Piper voices. It says single words more
completely than the app's on-device engine, so the shipped recordings use it.

    python tools/render_voice_clips_piper.py <model.onnx> <texts.json> <wav-dir> [length_scale]

Each phrase gets a full stop when it has no ending punctuation (Piper cuts
the last sound otherwise). length_scale 1.25 = a calm 80% pace.
Then: python tools/build_voice_clips.py encode <code> <work-dir>
"""
import json
import re
import sys
import wave
from pathlib import Path

from piper import PiperVoice, SynthesisConfig

model, texts, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
scale = float(sys.argv[4]) if len(sys.argv) > 4 else 1.25
voice = PiperVoice.load(model)
config = SynthesisConfig(length_scale=scale)
out.mkdir(parents=True, exist_ok=True)
phrases = json.loads(texts.read_text(encoding='utf8'))
for i, text in enumerate(phrases):
    spoken = text.strip() if re.search(r'[.!?…]$', text.strip()) else text.strip() + '.'
    with wave.open(str(out / f'{i}.wav'), 'wb') as w:
        voice.synthesize_wav(spoken, w, syn_config=config)
    if i % 500 == 0:
        print(f'{i} / {len(phrases)}', flush=True)
print(f'done: {len(phrases)} recorded')
