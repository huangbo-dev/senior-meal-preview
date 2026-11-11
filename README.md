# A little change — Android debug APKs (0.1.0)

Built on 2026-11-11 from source commit `7e069d1` with Flutter 3.44.8 / Dart 3.12.2
(`flutter build apk --debug --split-per-abi --dart-define=API_BASE_URL=http://10.0.2.2:8787`).

| File | For |
| --- | --- |
| `a-little-change-0.1.0-debug-arm64-v8a.apk` | arm64 phones and arm64 emulators |
| `a-little-change-0.1.0-debug-x86_64.apk` | x86_64 emulators |

Checksums are in `SHA256SUMS`.

## Limits

- **Debug build, signed with the Android debug key.** Not a release and not distribution-ready.
- The API address is fixed to `http://10.0.2.2:8787`, the host machine as seen from the
  standard Android emulator. The app has no offline fallback: it installs and opens on a
  physical phone but cannot load meal choices there until a hosted HTTPS backend exists
  and the app is rebuilt against it.
- Compiled and signature-verified only; not run on an emulator or device.
- Meal previews are simulated illustrations, not real meals, nutrition advice or clinical verification.

This branch holds build outputs only and shares no history with the source branches.
