# SG Food Edit — Android debug APKs (0.6.0)

Built on 2026-11-15 from source commit `3ee0e52` (branch `main` and `feat/auto-mask-20261115`, pushed) with Flutter 3.44.8 / Dart 3.12.2
(`flutter build apk --debug --split-per-abi` with `API_BASE_URL` and `API_AUTH_TOKEN` defines).
Spark02 is aarch64 and Gradle's aapt2 is x86_64, so the build also passes
`--android-project-arg=android.aapt2FromMavenOverride=$HOME/toolchains/qemu/aapt2` (runs it under QEMU).

| File | For |
| --- | --- |
| `sg-food-edit-0.6.0-debug-arm64-v8a.apk` | arm64 phones and arm64 emulators |
| `sg-food-edit-0.6.0-debug-x86_64.apk` | x86_64 emulators |

Checksums are in `SHA256SUMS`. Earlier APKs are in this branch's history. Do not use 0.3.0 (built without the meal photos) or 0.4.0 (published briefly without the tab bar).

## What's in this build

Version **0.6.0** (Android versionCode 2008 on arm64, 4008 on x86_64; shown in the app under **About**). Full history is in [CHANGELOG.md](CHANGELOG.md).

- **New in 0.6.0:** a before/after slider; Meals pictures are saved on the phone and shown
  again at once ("Make a new picture" asks again); a progress bar on Meals; tofu rice has a
  photo with rice; darker brown rice. See CHANGELOG.md.
- **From 0.5.0:** no more painting. Choose a change and a photo and the app finds the rice by
  itself. A third choice does both changes at once (brown rice with broccoli). On **Meals**,
  choosing brown rice or added vegetables now shows the meal's photo with that change made,
  instead of "No picture generated". If the rice cannot be found you are asked to paint it.
  The rice finder was set up by eye on five photos; it is a best guess and can be wrong.
- **From 0.4.1:** the app opens on **My photo**, the first tab; the sample meals are the
  second tab. The back button on Meals or About returns to My photo.
- **From 0.3.2:** a bottom tab bar (My photo · Meals · About) with each screen's main button
  pinned above it; About is now a tab. Plainer error messages, which no longer suggest
  "Summary only" on the photo screen. The recoloured brown-rice result no longer carries an
  "Experimental AI edit" notice next to its "Not AI-generated" label.
- **My photo** (the first tab): take or choose a photo of a rice meal, pick
  "brown rice", "add broccoli" or both, and get the edited photo back beside the original.
  For the project team only.
  - *Brown rice* recolours all the rice in the photo (no AI image model), about 4 s.
  - Drag across the result to compare before and after.
  - *Add broccoli* places broccoli on one patch of the rice with an AI image model, about 11 s
    per attempt, up to a minute for a hard one.
  - The waiting screen shows a progress bar and the seconds so far. The bar is an estimate.
  - These two methods were chosen by eye on one public photo. They are not the CE7454 research
    method and are not evaluated. Results are not reviewed by a person.
  - The photo is cropped and stripped of location data on the phone. The server deletes it after the edit.
- Everything from 0.2.0: the three bundled meal reference photos, the app name and icon, and
  **Try again** when the meal list does not load.

## Backend this build talks to

`https://drum-likes-inside-rugby.trycloudflare.com` — a temporary Cloudflare quick tunnel to a demo backend on Spark02
(symbolic previews, plus own-photo edits by the worker on Spark02, checked by Qwen2.5-VL). The address is compiled into the APK.

- The tunnel address is random. If the tunnel or Spark02 restarts, the address changes and
  these APKs stop loading meal choices until they are rebuilt against the new one.
- The APK embeds a shared demo API token. Anyone holding the APK can extract it; it is not
  user authentication.

## Limits

- **Debug build, signed with the Android debug key.** Not a release and not distribution-ready.
- The app has no offline fallback.
- Compiled and signature-verified, and the API was checked through the tunnel; the APK itself
  was not run on an emulator or device by the builder.
- Meal previews are simulated illustrations, not real meals, nutrition advice or clinical verification.

This branch holds build outputs only and shares no history with the source branches.
