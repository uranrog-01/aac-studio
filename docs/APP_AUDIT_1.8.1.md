# App review and keyboard fixes — 1.8.1

Reviewed November 2, 2026. Scope: the communication grid, typing, prediction,
button editing/deletion, picture search, backup restore and web updates.

| Finding | Change | Verification |
| --- | --- | --- |
| Type had pictures and digits but no letters | QWERTY A–Z, 0–9, one-shot Shift, punctuation, Space and Delete; removed picture shortcuts | Typing tests on small portrait, landscape and tablet sizes; Chromium and WebKit |
| Tapping the editor spoke instead of just positioning its cursor | Separate Speak button; editor supports cursor placement and selection | Cursor insertion, whole-word completion, selected deletion and emoji backspace tests |
| My words occupied the main toolbar | Removed its toolbar button; retained existing saved favorite data | Widget and browser checks |
| Prediction results remained cached after learning/restoring and ignored a changed limit | Invalidate on lexicon changes and include the limit in the cache key | Prediction regression test |
| An earlier online search could overwrite the current query or reappear after clearing | Cancel pending debounce and ignore superseded responses | Delayed-response widget test |
| Deletions were not recorded for later factory-pack upgrades | Save deletion IDs and remove the deleted button from every view and recent words | Save/reload/upgrade test |
| Editing a shared button could leave conflicting copies in other views | Update all matching references and serialize one button per ID | Shared-button save/reload test |
| Hidden/dimmed cell state and custom folder image paths were omitted from saved packs | Preserve those fields during round trips | Cell-state round-trip test; source review for folder paths |
| Whole-message Speak ignored clear-after-speaking and return-home settings | Apply the same behavior flags to the message panel, toolbar and typing Speak | Communication widget test |
| Backup restore left old settings controls and learned predictions on screen | Reload learned words immediately and close the old settings sheet | Source review; atomic restore and persistence browser checks |
| A small app update discarded every offline picture | Use a persistent, content-hashed picture cache; migrate matching legacy pictures | Upgrade test preserves cached pictures without downloading them again |
| Cached scripts could keep the previous keyboard visible after an update | Use distinct versioned script URLs and offer Reload app when a new worker takes control | Upgrade from the published 1.8.0 export to 1.8.1 |
| Offline readiness could describe the wrong worker or an unfinished activation | Check the active build and its completed-cache marker | Cold-start and upgrade browser checks |
| Unrelated failed promises could be reported as failed saves | Display the save warning only for an actual storage write failure | Source review |
| Installation instructions contained damaged punctuation | Replace damaged instructions with plain text | Source review |

Validation artifacts: `web-verification.json`,
`web-upgrade-verification.json`, browser screenshots, and the Flutter test
output. The application test suite contains 40 passing tests and static
analysis reports no issues.

Remaining checks and limits:

- Audible speech, Home Screen installation, VoiceOver and physical switch
  access still need checking on the actual iPhone. Windows WebKit has no
  speech API; its passing checks cover UI, storage and offline behavior.
- Browser storage may be evicted or cleared. Keep a backup in Files. The
  web app uses device/browser voices; some voices require internet access.
- Earlier app versions did not store deletion markers. New deletions now
  retain them; markers already lost from older saves cannot be recovered
  automatically.
- The private hosted app requires ChatGPT sign-in. Automated browser checks
  use the local export; the authenticated production session was not tested.

The review does not establish that every app feature or device combination
is free of defects. No generated artwork was added in this release.
