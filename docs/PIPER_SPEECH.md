# Piper offline speech — 1.3.0 (build 8)

## Behavior

- Bundles one Piper medium voice: `en_US-ljspeech-medium`, US English female,
  22,050 Hz. The upstream model card describes training from scratch on the
  public-domain LJ Speech dataset. No extracted Proloquo2Go assets are used.
- Enabled by default, including when loading older settings. Turning it off
  persists the device-voice preference.
- Preparing the model and synthesizing speech run in a persistent isolate.
  Device speech remains available while the offline voice prepares.
- If model initialization, generation or playback fails, the same message is
  attempted with native text-to-speech; both failing still produces the app's
  existing visible speech error. Settings offers a retry action and status.
- New requests supersede queued/in-flight results. Stop prevents late-generated
  audio from starting. A native inference already running can finish in the
  background; stale output is discarded.
- Rate maps from the existing default 0.45 to Piper's normal speed 1.0, bounded
  to 0.5–2.0. Volume is preserved. Non-default pitch uses device speech because
  this Piper model does not expose an independent pitch control.
- Up to 32 generated WAVs / 16 MiB are cached per session (a single longer
  message and files still held by a player may exceed that limit). Cache keys include text and speed. No text
  or audio is sent over the network. WAVs are temporary local files and are
  removed on orderly worker disposal; OS cleanup handles abandoned temp files.

## Dependencies and packaging

Pinned speech components: `sherpa_onnx 2.0.1`, `piper_phonemize 1.5.9`,
`audioplayers 6.8.1`, `archive 4.6.0`.

Sherpa 2 removed its built-in eSpeak dependency, so the app explicitly
phonemizes text with `piper_phonemize` and passes phoneme codepoints into the
VITS model. This also handles words outside a fixed pronunciation lexicon.

On Windows the worker preloads the matching bundled ONNX runtime. Otherwise
Windows can find its older System32 runtime, which is incompatible with the
newer sherpa native library. No system DLLs are changed.

The archive is an unmodified upstream release, bundled as a Flutter asset.
Its SHA-256 is recorded in [NOTICE](../assets/voices/NOTICE.txt). Verify or
restore it with `powershell -File tools/fetch_piper.ps1`. The ONNX model alone
is 63,531,507 bytes; the compressed model/pronunciation archive is about 64 MiB.
Runtime libraries and bundled phonemizer data require additional space.

First use streams archive extraction to app support storage on the worker.
Paths and links are checked before writing, archive checksums are verified,
and a completion marker is written only after required files are present.
Missing or truncated installed files trigger preparation again. Subsequent
launches reuse the installed model.

## Verification

Run from `studio`:

```text
flutter analyze --no-pub
flutter test --no-pub --no-test-assets
dart run tools/piper_smoke.dart
flutter build windows --release
flutter build apk --release
```

The eight dedicated speech tests exercise successful Piper routing, rate and
volume overrides, immediate native speech during setup, fallback for the same
utterance, retry, missing voice data, stop, superseding messages, pitch fallback,
and saved preference migration. These tests mock playback and native speech.

The smoke tool performs real CPU inference through the native libraries,
validates nonempty/nonzero 22,050-Hz PCM WAVs and cache hits, and saves samples
under `dist/piper-smoke`. One Windows run after model installation measured
89 ms for “Help”, 320 ms for a short message, and 503 ms for a numbers example;
cache hits were below the tool's millisecond resolution. These are desktop
generation measurements, not tap-to-speaker latency or tablet benchmarks.

Android/iOS listening, silent switch, volume, Bluetooth, background interruptions,
first-use preparation on low-memory tablets, and sustained repeated use need
physical-device verification. iOS builds require macOS. No claim is made that
Piper is faster than another model on the user's tablet.

Some Windows Java installations need a short Unix-domain socket path for Gradle:
set `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/tmp` (use an existing local
directory). Set `ANDROID_HOME` and `JAVA_HOME` for the installed SDK/JDK.

The local Android test installers use the previous installation's signing key,
recovered from the user's saved development environment. Its SHA-256 certificate
fingerprint is `e33e2ef2dfd25dd8ad67dd86d47ff9bfdbcaed441c8316b7b6eb67ea43eef0b3`.
The key is stored only in ignored local files (`android/app/local-update.keystore`
and `android/key.properties`). The Gradle release configuration honors that
optional properties file; neither key material nor passwords belong in Git.
An existing installation signed with a different key still cannot be updated
with these installers. Split APK version codes retain Flutter's ABI offsets.

## Notices and source

Voice/model provenance and GPL text are bundled under `assets/voices` and
available through **Voice and software licenses** in speech settings.

- [Original voice model card](https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/ljspeech/medium/MODEL_CARD)
- [LJ Speech dataset](https://keithito.com/LJ-Speech-Dataset/)
- [Sherpa source, Apache-2.0](https://github.com/k2-fsa/sherpa-onnx/tree/v2.0.1)
- [Phonemizer source/build scripts, GPL](https://github.com/csukuangfj/piper-phonemize/tree/v1.5.9)
- [eSpeak NG source](https://github.com/espeak-ng/espeak-ng)

Original AAC Studio code retains MIT licensing. Combined distributions include
GPL-licensed phonemizer code and pronunciation data. Public binary releases
need the matching corresponding source/build materials under those terms;
linking an upstream repository alone does not supply that source package.
