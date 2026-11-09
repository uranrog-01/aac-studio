# Installing AAC Studio on iPhone

Checked November 2, 2026. The requested setup is **Windows only, no paid
Apple Developer membership, and no Apple Account password entered into any
third-party app**. The device is an iPhone Air; its installed iOS version
has not been supplied.

## Route that fits these requirements: a home-screen web app

An HTTPS web version can be opened in Safari and added using Share → Add
to Home Screen → Open as Web App → Add. This does not require an Apple
Developer membership or signing credentials.

[Apple's home-screen web app instructions](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/27/ios/27)

The home-screen web version is now prepared. It uses browser IndexedDB for
saved boards, browser/device speech, and a custom offline cache. Chromium
and WebKit checks cover persistence, backup export/restore, offline reopening
and the typing screen. Audible speech and Home Screen installation still
need testing on the physical iPhone.

See [the web installation and build guide](WEB_IPHONE.md) for the published
link, installation steps, backups and validation limits.

## Native installation and free Apple signing

Apple's official free route uses a Personal Team in **Xcode on a Mac**.
The Apple Account is entered in Apple's own software. Profiles expire
after seven days, requiring the app to be rebuilt and reinstalled. This
does not provide a Windows-only solution.

[Apple's Personal Team rules](https://developer.apple.com/help/account/basics/about-your-developer-account)

Windows sideloaders that ask for an Apple Account password do not satisfy
the stated requirement, even if they say they send it only to Apple.
An app-specific password is not a free-account workaround for Sideloadly:
its official FAQ restricts that mode to a paid developer account with
anisette disabled.

[Sideloadly's official FAQ](https://sideloadly.io/faq)

A TestFlight release from a publisher with the required developer
membership would let the user install through Apple's TestFlight app.
No such release or publisher membership has been established for this
project.

## Current local IPA and helpers

Inspection of `dist/AACStudio-unsigned.ipa` found version **1.0.0 (1)** and
no embedded provisioning profile. It is not the current app and is
not an installable signed release. Downloading or transferring it does
not supply Apple-trusted signing.

`tools/sign_and_install.ps1` is intended to combine local signing and USB
installation. It still requires a valid Apple-issued signing certificate,
its corresponding private key and a matching provisioning profile that
permits the target device and app. None were found in `tools/certs` during
this check. The certificate-file passphrase is separate from an Apple
Account password. Certificates and profiles expire or can be revoked;
having them once does not confer permanent signing access.

The earlier test using a self-generated certificate established only
local signing/repackaging mechanics. It did **not** establish successful
installation or launch on a real iPhone. A self-generated certificate is
not a substitute for Apple-trusted provisioning.

`tools/install_ipa_windows.ps1` transfers an **already validly signed** IPA
over USB. It does not obtain signing credentials or bypass iOS signature
validation. Do not use the unsigned IPA as an example of an installable
input.

The existing Codemagic workflow builds an unsigned iOS artifact on macOS;
that build step does not solve distribution signing.

## TrollStore compatibility

The official TrollStore project lists supported older iOS builds through
17.0, not the iOS 26 generation introduced with iPhone Air. It is not an
installation route for this device.

[Official TrollStore compatibility](https://github.com/opa334/TrollStore)
[Apple's iPhone Air announcement](https://www.apple.com/newsroom/2025/09/introducing-iphone-air-a-powerful-new-iphone-with-a-breakthrough-design/)
