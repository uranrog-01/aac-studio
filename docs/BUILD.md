# Build APK, IPA and website from Windows

Double-click `build.bat` in the main Proloquo2Go folder or in `studio`.
It builds the signed Android APK and website locally, builds a fresh unsigned
iOS IPA on a GitHub Actions Mac runner, and downloads the IPA automatically.
It does not upload your website or publish a release.

## One-time setup

This PC already has Flutter, Python, the Android SDK, and the Android update
signing keys. Keep `android/key.properties`, the keystore, and the existing
signing lineage backed up. The build refuses to silently replace missing
release signing configuration with a different signing key.

GitHub CLI is installed. If you have not signed in yet, open PowerShell and run:

```powershell
gh auth login --hostname github.com --git-protocol https --scopes workflow
gh auth setup-git
```

When a desktop vault redirects application-data folders, the helper also
checks the normal Windows profile for your existing GitHub CLI login. It
reuses that configuration without copying credentials.

Log in with an account that can push to the project's `origin` repository
(`uranrog-01/aac-studio`). Enable GitHub Actions in that repository. The account
or token needs repository write access and permission to update workflows.
The Mac runner uses that repository's Actions allowance/billing.

## Each build

1. Save your changes in the editor.
2. Double-click `build.bat`. Keep its window open until it finishes.
3. Find the files in `studio/dist/builds/<version+build>/<timestamp-id>/`.
   The exact folder appears in the build window.

Files:

- `AACStudio-android.apk`: signed Android download, with the project's
  existing signing-key rotation preserved.
- `AACStudio-unsigned.ipa`: newly built iOS app, **requires signing**.
- `AACStudio-web.zip`: extract and upload the **contents** to an HTTPS
  website root to run the app in a browser, including iPhone Safari.
- `SHA256SUMS.txt`: package checksums.
- `build.log` and `build.json`: results, source commit, and GitHub run URL.

Every invocation uses a new output folder. Failed builds exit with an error;
partial outputs remain with `status: failed` in `build.json`. An old IPA is
never copied into a new build folder. If GitHub login is missing, the local
APK and web package are still built, followed by a clear incomplete message.

For a device update, increase the build number in `pubspec.yaml` before
running, for example `1.8.1+5006` to `1.8.2+5007`. Keep it higher than any
previously installed version. The script uses the version you set.

## How current changes reach GitHub

The script creates a separate build snapshot using a temporary Git index.
It includes saved files from `lib`, `assets`, `ios`, the pubspec and lockfile,
Flutter metadata, license notices, and `.github/workflows/local-ios.yml`.
Uncommitted app changes and new app assets are included unless Git-ignored.
It sends the snapshot to a unique `build/aac-*` branch on `origin`; the push
automatically starts the workflow, so no manual workflow deployment is needed.
Your working branch, staged changes, and working files stay in place.

The runner uses the same Flutter release as your local build. It checks out
that exact snapshot, builds iOS, and uploads an artifact. The script waits
for that particular run and downloads only its artifact. Build branches remain
for traceability; their names are recorded in `build.json` and you can delete
old `build/aac-*` branches later. Source uploaded to a public repository is
public. Android signing keys and local generated output are outside the
snapshot's inputs.

## Options

Run these in PowerShell from the main project folder:

```powershell
.\build.bat -SkipIos                 # APK + website, no GitHub needed
.\build.bat -SkipWeb                 # APK + IPA
.\build.bat -SkipIos -SkipWeb        # APK only
.\build.bat -SkipIos -NoPause        # do not wait for Enter at the end
.\build.bat -Simulator               # also build the iPhone Simulator app
.\build.bat -SkipAndroid -SkipWeb -Simulator   # only the GitHub Mac builds
```

You can pass `-Flutter "C:\path\to\flutter\bin\flutter.bat"` if Flutter
is elsewhere. Otherwise the script checks `FLUTTER_ROOT`, PATH, then
`C:\tools\flutter`. Downloads and first builds may take several minutes.

## See the app on an iPhone Simulator (no Mac needed)

`-Simulator` adds a second job to the same GitHub Mac run. It builds the
app for Apple's iPhone Simulator, starts it on a Simulator on the runner,
and checks it is still running after three minutes. These files are added
to the build folder:

- `AACStudio-simulator.zip`: the Simulator app (`Runner.app`, zipped).
- `simulator-after-30s.png` … `simulator-after-180s.png`: what the iPhone
  screen showed 30 seconds, 1, 2 and 3 minutes after starting.
- `simulator-log.txt`: the app's own messages and errors from that time.

To tap through the app yourself, upload `AACStudio-simulator.zip` to a
browser iPhone simulator service such as Appetize.io (its free plan has a
monthly time limit). Choose an iPhone and iOS version on its page. The
run's summary page lists the app's processor type (`arm64` and/or
`x86_64`); pick a service that accepts it.

What this does not show:

- It is a **debug** build (Flutter cannot make release builds for the
  Simulator). It starts and scrolls slower than the real app.
- The Simulator's voices and sound are not those of a real iPhone, and
  most browser simulators stream no audio or only limited audio. Check
  speech on a real iPhone.
- It cannot be installed on a real iPhone. Use the IPA for that.

The job runs only with `-Simulator` (branch `build/aac-sim-*`) or when the
workflow is started by hand with **Also build the iPhone Simulator app**
ticked, so normal builds do not use extra Mac minutes.

## iPhone installation

The current workflow creates an **unsigned IPA**, matching the project's
existing iOS workflow. Hosting this file on a website does not make it
installable. Sign it using your chosen sideloading setup, or configure Apple
distribution signing separately for TestFlight/App Store or eligible direct
distribution. No Apple signing credentials are configured by this helper.
Use the website package for the existing Safari/Home Screen installation
route. See [IOS_SIGNING.md](IOS_SIGNING.md) and [WEB_IPHONE.md](WEB_IPHONE.md).

References: [Flutter iOS builds](https://docs.flutter.dev/deployment/ios),
[GitHub artifact downloads](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).
