# Installing AAC Studio (or any IPA) on an iPhone — no paid developer account

## The passwordless local pipeline (built, tested)

`tools\sign_and_install.ps1` signs and installs any IPA **entirely locally and
open source** — zsign (compiled from source in WSL) + pymobiledevice3. The
only credential it ever touches is the passphrase of **your own certificate
file**. No Apple ID, no account password, no third-party service, ever.

```
tools\certs\cert.p12              <- your signing certificate (one-time mint)
tools\certs\cert.mobileprovision  <- matching provisioning profile
        |
        v
tools\sign_and_install.ps1  =  zsign (WSL)  ->  pymobiledevice3 (USB install)
```

The pipeline is mechanically verified end-to-end on this machine (signed the
112 MB `AACStudio-unsigned.ipa` with a locally generated test CA chain in
under 2 seconds). An iOS device would reject the *test* certificate — that is
expected; what it proves is that every mechanical step (p12 parsing, CMS
signature, Mach-O re-signing, repack) works.

### The one unavoidable step

Minting a certificate requires **one** Apple ID authentication — Apple's
servers issue certificates only to authenticated accounts, and iOS installs
nothing without a certificate. This is true for every tool that has ever
existed on stock iOS (TrollStore excepted, and it needs iOS ≤ 17.0; your
iPhone Air runs 26.7.2). What you can control is *where* that one
authentication happens and *how long* the credential lives:

| Mint route | Credential exposure | After the mint |
|---|---|---|
| **Paid Apple Developer** ($99/yr) — create cert in the Apple portal in a browser, download `.p12` + `.mobileprovision` | Apple ID used in Apple's own website only | **Zero credentials forever.** Drop both files in `tools\certs\`, run `tools\sign_and_install.ps1`. Profiles last months, not 7 days. |
| **Free Apple ID via open-source clients** (AltServer / SideStore — source-auditable, credentials go directly to Apple) | Typed once into an open-source tool | 7-day certs; re-mint weekly (or use SideStore's on-device refresh). |
| **Free Apple ID via Sideloadly** with an **app-specific password** | A revocable, signing-only password (not your account password) — delete it any time at account.apple.com → App-Specific Passwords | 7-day certs. |

If you export/obtain the `.p12` + `.mobileprovision` pair by any of these
routes, everything after that is passwordless:

```powershell
tools\sign_and_install.ps1                     # signs dist\AACStudio-unsigned.ipa and installs
tools\sign_and_install.ps1 -IpaPath C:\any.ipa # works for ANY ipa, same certs
```

---

# Background: why unsigned files "do nothing"

iOS refuses to install any IPA that is not code-signed with a certificate
Apple trusts. Unsigned files are silently ignored by the installer — a QR
scan or Safari download of one "does nothing" by design. So every route
below is about getting a valid signature, from cheapest to most flexible.

## Decision tree

```
What iOS version is the iPhone on?
│
├─ iOS 14.0 – 16.6.1, 16.7 RC, or 17.0
│    → TrollStore: permanent installs, NO Apple ID, no 7-day limits.
│      (https://github.com/opa334/TrollStore — check your exact build
│       against its compatibility table.)
│
└─ iOS 16.7+ / 17.1+ / 18.x / 26.x  (TrollStore not available)
     → Sideloadly with a FREE Apple ID (one-time per week):
         1. Get dist/AACStudio-unsigned.ipa from the Codemagic
            "iOS (unsigned IPA)" workflow (or the studio QR transfer).
         2. Install Sideloadly (https://sideloadly.io), plug the iPhone
            in via USB, drop the IPA in, enter your Apple ID, Start.
         3. On the phone: Settings → General → VPN & Device Management →
            trust your Apple ID profile. Enable Developer Mode if asked
            (iOS 16+).
         4. `tools\install_ipa_windows.ps1 <any-signed.ipa>` can then
            re-install signed IPAs over USB without Sideloadly.
     → After that first bootstrap you can move signing on-device:
         - SideStore (https://sidestore.io) — refreshes your own apps
           wirelessly without the PC.
         - ESign / Feather — on-device signer; import the free
           certificate you generated with Sideloadly and sign further
           IPAs on the phone.
```

## Limits of a free Apple ID (personal team)

| Limit | Value |
|---|---|
| Signature validity | 7 days, then re-sign |
| Active signed apps per device | 3 |
| New App IDs per week | 10 |

These are Apple's server-side rules for free accounts — no sideloading tool
changes them. Signing with the same Apple ID on the phone (SideStore/ESign)
obeys the same limits.

## Security notes — read before using "no-PC" repos

- Repos named like "ESign iOS 26" that contain no source code and route you
  to a download site are SEO bait. **iOS26Tools/Esign-iOS** is one: it has no
  buildable code and instructs you to install a DNS content-filter profile
  and trust an unknown enterprise certificate. Both are real risks (traffic
  interception, arbitrary app trust). Do not install such profiles.
- "Community" / shared certificates used by many people get revoked within
  hours and are a supply-chain risk. Only use certificates generated from
  **your own** Apple ID.
- Prefer open-source, reviewed tools: TrollStore, Sideloadly, AltStore,
  SideStore, Feather.

## Windows USB helper

`tools\install_ipa_windows.ps1` installs a **signed** IPA over USB with
open-source tooling (pymobiledevice3) — handy for the weekly re-sign cycle:

```powershell
# first run (one time): sets up its own venv
tools\install_ipa_windows.ps1 dist\AACStudio-unsigned.ipa
```

If the IPA is unsigned the install fails with a provisioning error — sign it
with Sideloadly first, then re-run this script for subsequent installs.
