# Verification and remaining limits

Verified locally on 8 November 2026, using macOS, Rust/Cargo 1.98.1, Flutter 3.44.8, and Dart 3.12.2. These checks concern this extension only; they do not validate CE7454 model experiments or nutritional outcomes.

## Passed

- Rust formatting, `cargo test --locked` (11 API test functions, including selection/shape/origin matrices), and Clippy for all targets with warnings denied.
- Flutter/Dart formatting, `flutter analyze` with no issues, and 20 unit/widget tests.
- Flutter release web build with locally bundled CanvasKit and Roboto, plus its license. Build artifacts are not committed.
- Android debug APK compilation: `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8787`. The generated `mobile/build/app/outputs/flutter-apk/app-debug.apk` is ignored, not committed. Compilation is not an emulator/device run.
- Real loopback HTTP smoke: health/catalog, valid preview, invalid selection, and no-store response headers.
- Production Dart HTTP client against the real Rust server: catalog decoding, two-change preview/preferences, unknown-dish rejection, and incompatible-change rejection. Negative checks require the expected validation messages, not just any exception.
- Chrome local browser check: desktop meal selection, two-change limit, optional preference, live preview/disclosures; fresh 390 × 844 viewport meal selection, compatible-only changes, preview, Back/edit retaining choices, and Start over clearing choices.
- Browser console had no warnings/errors during the inspected successful preview. The web CSP restricts requests to local assets and loopback endpoints. Renderer/font URLs are explicitly local.
- Independent static review of the Rust/Dart contract, response integrity, stale-response guards, privacy boundaries, and documentation. Duplicate returned targets were identified, fixed, and regression-tested.

Widget coverage includes catalog failure/retry, malformed or wrong-mode API responses, failed submission/retry, 1–2-change validation, compatibility filtering, duplicate submissions, reset/back while requests are pending, wrong-dish/duplicate-target responses, narrow-screen 200% text scaling, semantic labels, and minimum touch targets.

## Reproduce

From this extension directory:

```sh
./scripts/check.sh
python3 scripts/smoke.py
```

The first resolves normal package dependencies and runs format/test/static/build checks. The second builds and starts a temporary Rust server on loopback, runs `mobile/tool/smoke_api.dart`, and terminates only that child process.

For visual testing, start the API and Flutter Chrome target using the README. A release build can be served with:

```sh
python3 -m http.server 5173 --bind 127.0.0.1 --directory mobile/build/web
```

Use a fresh load after switching emulated device pixel ratio. In this test browser, switching an already-rendered desktop Flutter canvas to a different emulated pixel ratio temporarily clipped the canvas; reloading at the target viewport produced the correct responsive layout. This does not establish native orientation behavior.

## Latest native build follow-up, 8 November 2026

The full `scripts/check.sh` suite and live `scripts/smoke.py` contract check were rerun successfully before the native build checks. The earlier Chrome visual results above were not rerun in this follow-up.

Android debug compilation passed using Flutter 3.44.8 / Dart 3.12.2, Android API 36, build-tools 36.0.0, NDK 28.2.13676358, Gradle 9.1.0, Android Gradle Plugin 9.0.1, Kotlin plugin 2.3.20 and Android Studio's OpenJDK 25.0.2. Gradle emitted a native-access warning; the build completed successfully. A separate fresh clone of remote commit `ad37479db80b433d96cfa4dd956cc40accaab829` also built the debug APK successfully and retained a clean Git status. This used the same installed SDK/dependency caches, not a newly provisioned machine; it verifies no untracked app-source files were needed. The following handoff commit changes only documentation and a cache ignore rule, not executable source.

The iOS command `flutter build ios --simulator --debug --dart-define=API_BASE_URL=http://127.0.0.1:8787` was attempted and failed before native compilation. Xcode 27.2 could not load `IDESimulatorFoundation` because `/Library/Developer/PrivateFrameworks/CoreSimulator.framework` is missing. Its diagnostic recommends completing Xcode first-launch setup. No Xcode installation or license changes were made. `flutter doctor` marked Xcode available, so that check alone does not establish build readiness.

`flutter doctor` also reports that some Android SDK licenses are not accepted, although the existing installed components were sufficient for this debug APK. No additional licenses were accepted. The exact platform setup and follow-up commands are in [MOBILE_BUILD.md](MOBILE_BUILD.md).

## Not verified / not implemented

- Native Android emulator/device UI runs, iOS simulator/device builds, signing, app-store packages, or physical-device networking.
- Real VoiceOver/TalkBack sessions, older-adult usability testing, or accessibility certification.
- Full network interception/audit, adversarial security review, remote deployment, authentication, or multi-user operation.
- Actual photo editing, model execution, GPU integration, checker/retry results, nutrition calculation, or clinical/dietary suitability.
- Repository-wide Python/GPU tests: no existing pipeline files were changed, and these checks do not start the project's model services.

These limitations are deliberate prototype boundaries, not successful tests. The app is not a coursework submission or a participant-data collection tool.
