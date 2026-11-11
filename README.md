# A little change — Android debug APKs (0.1.0)

Built on 2026-11-11 from source commit `cf2a9c2` with Flutter 3.44.8 / Dart 3.12.2
(`flutter build apk --debug --split-per-abi` with `API_BASE_URL` and `API_AUTH_TOKEN` defines).

| File | For |
| --- | --- |
| `a-little-change-0.1.0-debug-arm64-v8a.apk` | arm64 phones and arm64 emulators |
| `a-little-change-0.1.0-debug-x86_64.apk` | x86_64 emulators |

Checksums are in `SHA256SUMS`.

## Backend this build talks to

`https://drum-likes-inside-rugby.trycloudflare.com` — a temporary Cloudflare quick tunnel to a demo backend on Spark02
(symbolic previews only, no GPU worker). The address is compiled into the APK.

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
