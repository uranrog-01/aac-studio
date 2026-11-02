# AAC Studio on iPhone through Safari

The web version is built from the same Flutter boards and symbol library as
the native app. It needs no Apple Developer membership or Apple Account
password. Publishing uses the separate private static Site checkout at
`sites/aac-studio-iphone`; its `.openai/hosting.json` retains the Site ID.

## Install on iPhone

1. Open the published HTTPS link in **Safari**. A private Site may ask you to
   sign in to your ChatGPT account, which is separate from your Apple Account.
2. Tap Share → Add to Home Screen. Enable **Open as Web App**, then tap Add.
3. Open AAC Studio from its Home Screen icon while connected to the internet
   the first time. Wait for Settings → iPhone & offline to report that the
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
- Picture caches are versioned so revised artwork replaces older cached
  artwork. After an update, reopen the app online and save the full library
  again if you need every picture offline. Board storage uses a separate
  database and survives app updates.

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
