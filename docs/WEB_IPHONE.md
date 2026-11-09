# AAC Studio on iPhone through Safari

The web version is built from the same Flutter boards and symbol library as
the native app. It needs no Apple Developer membership or Apple Account
password.

**[Open AAC Studio](https://uranrog-01.github.io/aac-studio/)**:
`https://uranrog-01.github.io/aac-studio/`

Published on GitHub Pages (free, HTTPS) on November 8, 2026 from the
`gh-pages` branch of `uranrog-01/aac-studio`. The link is public: anyone
who has it can open the app. Only the built app is published; boards,
settings and learned words stay on each phone. Checked in a Chromium
phone-size window: the board loads, taps build a message and the offline
starter files install. Not yet checked on a physical iPhone.

To publish a new version after changing the app, run from `studio`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\publish_pages.ps1
```

It rebuilds the web app for the `/aac-studio/` address and replaces the
`gh-pages` branch; GitHub Pages updates within a few minutes. An installed
iPhone app picks it up the next time it is opened online and shows a
Reload app banner.

The earlier private copy (`https://aac-studio-iphone.silverstone14.chatgpt.site`,
from the `sites/aac-studio-iphone` checkout, needs ChatGPT sign-in) is from
November 2 and does not include later fixes.

## Install on iPhone

1. Open the published HTTPS link in **Safari** (Apple's steps below are
   for Safari).
2. Tap Share > Add to Home Screen. Enable **Open as Web App**, then tap Add.
3. Open AAC Studio from its Home Screen icon while connected to the internet
   the first time. Wait for Settings > iPhone & offline to report that the
   starter boards are ready offline.
4. Use **Save all pictures offline** to download the complete picture library.
   Keep the app open until it finishes. A failed download resumes when retried.
5. Try a few words in airplane mode to check speech on your own iPhone.

[Apple's instructions](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/27/ios/27)

## Saved boards, pictures and speech

- Boards, settings and learned words are stored locally in IndexedDB. They
  are not sent to the hosting service. Clearing Safari website data removes
  them. Use **Save backup** to keep a JSON copy in Files; **Restore backup**
  validates a selected backup before asking to replace current data.
- A custom service worker saves the runtime, starter board pictures and
  typing-screen picture words. Other pictures are saved when opened, or
  together with the full-library download. Browser storage can be evicted;
  keep backups and check offline readiness before depending on it.
- Web speech uses Safari's available device voices. Native Piper is not
  included in the web download. Speech begins directly from a tap handler;
  internet requirements depend on the selected voice. Desktop browser tests
  do not establish audible speech or installation on a physical iPhone.
- Picture entries are checked by content hash. Matching downloaded pictures
  survive app-code updates; revised pictures are downloaded when needed.
  Reopen the app online after an update. If a Reload app banner appears,
  finish your current message before tapping it. Board storage uses a
  separate database and survives app updates.

## Build and validate

From the `studio` directory:

```powershell
python tools/build_web.py
C:/tools/flutter/bin/flutter.bat analyze --no-pub
C:/tools/flutter/bin/flutter.bat test --no-pub
python -m http.server 8878 --bind 127.0.0.1 --directory build/web-pwa
```

`build/web-pwa` is the static deployment directory. The build script excludes
native voice model/engine assets, uses a local CanvasKit renderer, generates
the offline manifests and packages a versioned ZIP under `dist`. It verifies
its generated output target before clearing it on a rebuild.

The browser test is `tools/test_web.cjs`. Set `AAC_PLAYWRIGHT_MODULE` to an
installed Playwright module, then run it against the local server. Set
`AAC_TEST_ENGINES=webkit` to run only the Safari-engine checks. Results and
phone/landscape screenshots are written under `docs`. Test speech is
intercepted; audible iPhone speech remains a device check.

A plain LAN HTTP address is useful for online development preview but does
not establish secure-context service-worker support on an iPhone. Use HTTPS
for the installed app. Do not add the unsigned native IPA to this process.

The 1.8.1 keyboard changes and review are documented in [the app audit](APP_AUDIT_1.8.1.md).
