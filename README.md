# SG Food Edit — Android debug APKs (0.3.1)

Built on 2026-11-13 from source commit `219a725` with Flutter 3.44.8 / Dart 3.12.2
(`flutter build apk --debug --split-per-abi` with `API_BASE_URL` and `API_AUTH_TOKEN` defines).

| File | For |
| --- | --- |
| `sg-food-edit-0.3.1-debug-arm64-v8a.apk` | arm64 phones and arm64 emulators |
| `sg-food-edit-0.3.1-debug-x86_64.apk` | x86_64 emulators |

Checksums are in `SHA256SUMS`. Earlier APKs are in this branch's history. Do not use 0.3.0: it was built without the meal photos.

## What's in this build

Version **0.3.1** (Android versionCode 2004; shown in the app under **About**). Full history is in [CHANGELOG.md](CHANGELOG.md).

- **Use my own meal photo** (on the Meals screen): take or choose a photo of a rice meal, pick
  "brown rice" or "add broccoli", paint the area, and get the edited photo back beside the original.
  For the project team only.
  - *Brown rice* recolours your own rice (no AI image model), about 3 s. Paint the rice only:
    a white plate under the brush is tinted too.
  - *Add broccoli* places broccoli on one small painted patch with an AI image model, about 11 s
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
