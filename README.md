# SG Food Edit — Android debug APKs (0.1.0)

Built on 2026-11-12 from source commit `474f465` with Flutter 3.44.8 / Dart 3.12.2
(`flutter build apk --debug --split-per-abi` with `API_BASE_URL` and `API_AUTH_TOKEN` defines).

| File | For |
| --- | --- |
| `sg-food-edit-0.1.0-debug-arm64-v8a.apk` | arm64 phones and arm64 emulators |
| `sg-food-edit-0.1.0-debug-x86_64.apk` | x86_64 emulators |

Checksums are in `SHA256SUMS`.

## What's in this build

- **Use my own meal photo** (on the Meals screen): take or choose a photo of a rice meal, pick
  "brown rice" or "add broccoli", paint over the rice, and get the edited photo back beside the
  original (about 15–60 s). For the project team only. Results are experimental AI edits that
  no person has reviewed. In testing, the rice was sometimes replaced with a decorated bowl.
  The photo is cropped and stripped of location data on the phone. The server deletes it after the edit.

- App name "SG Food Edit" on the home screen, and a new icon: a plate with one small leaf.
- The three meal reference photos (Wikimedia Commons, see the in-app credits) are now bundled.
  Before this, every meal card read "Photo unavailable".
- If the meal list doesn't load, the home screen offers **Try again** after 8 seconds and shows an error after 15,
  instead of staying on "Getting the meal choices…".

## Backend this build talks to

`https://drum-likes-inside-rugby.trycloudflare.com` — a temporary Cloudflare quick tunnel to a demo backend on Spark02
(symbolic previews, plus photo edits by the BrushNet-SDXL + Qwen2.5-VL worker on Spark02). The address is compiled into the APK.

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
