# Verification and remaining limits

Verified locally on 8 November 2026, using macOS, Rust/Cargo 1.98.1, Flutter 3.44.8, Dart 3.12.2, and Xcode 27.2. These checks concern this extension only; they do not validate CE7454 model experiments or nutritional outcomes.

## Passed

- Rust formatting (`cargo fmt --check`), `cargo test --locked` (19 API test functions, including selection rules, catalog consistency, duplicate-before-unknown precedence, stalled-request timeout handling, Tailscale IP/MagicDNS SSRF and AWS IMDS blocking, authenticated Tailscale GPU worker bridging, and EC2 Bearer token / CORS origin enforcement), and Clippy for all targets with warnings denied.
- Flutter/Dart formatting (`dart format --output=none --set-exit-if-changed lib test tool`), `flutter analyze` with no issues, and 26 unit/widget tests (`test/api_test.dart` and `test/widget_test.dart`, including Tailscale GPU preview capability and `GpuPreviewCard` provenance rendering).
- Flutter release web build with locally bundled CanvasKit and Roboto, plus its license. Build artifacts are not committed.
- Android debug APK compilation: `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8787`. The generated `mobile/build/app/outputs/flutter-apk/app-debug.apk` is ignored, not committed. Compilation is not an emulator/device run.
- iOS simulator debug build (`flutter build ios --simulator --debug --dart-define=API_BASE_URL=http://127.0.0.1:8787`) after updating `IPHONEOS_DEPLOYMENT_TARGET` from `13.0` to `15.0` for Xcode 27.2 compatibility, plus live launch on `iPhone 17 Pro` simulator (iOS 26.5) connected to the local Rust API.
- Real loopback HTTP smoke (`python3 scripts/smoke.py`): health/catalog, selection rules, valid preview, invalid selection, and graceful `SIGTERM` shutdown.
- Production Dart HTTP client against the real Rust server: catalog and selection-rule decoding, two-change preview/preferences, unknown-dish rejection, and incompatible-change rejection. Negative checks require the expected validation messages, not just any exception.
- Visual acceptance captures (15 widget-rendered states across `390×844` at 100% text, `360×800` at 200% text, and `800×900` wide layout, plus 1 native iOS Simulator screenshot on `iPhone 17 Pro`), stored outside Git. Visual inspection caught and fixed a `ChipThemeData` `labelStyle` font/color inheritance issue and a header wrap issue on narrow viewports.
- Chrome local browser check: desktop meal selection, two-change limit, optional preference, live preview/disclosures; fresh 390 × 844 viewport meal selection, compatible-only changes, preview, Back/edit retaining choices, and Start over clearing choices.
- Independent static review of the Rust/Dart contract, response integrity, stale-response guards, privacy boundaries, and documentation.

Widget and unit coverage includes catalog failure/retry, malformed or wrong-mode API responses, non-JSON error status handling (408/502), catalog `selection` rules and legacy fallback, failed submission/retry, 1–2-change validation, one-choice Fish soup copy, compatibility filtering, inline disabled reason when two changes are selected, duplicate submissions, reset/back while requests are pending, wrong-dish/duplicate-target responses, compact-to-stacked meal card switching at 200% text scale, preview request summary ordering before plates with neutral bullets, system back (`PopScope`) across steps, semantic labels, and minimum touch targets.

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

## Latest P0/P1 UI & native build pass, 8 November 2026

The full `scripts/check.sh` suite (15 Rust tests, 25 Flutter tests, analyzer, formatters, release web build) and live `scripts/smoke.py` contract check passed after extracting `mobile/lib/theme.dart` and `mobile/lib/widgets.dart` and adding catalog `selection` rules and request timeouts to `backend/src/lib.rs`.

Android debug compilation passed using Flutter 3.44.8 / Dart 3.12.2, Android API 36, build-tools 36.0.0, NDK 28.2.13676358, Gradle 9.1.0, Android Gradle Plugin 9.0.1, Kotlin plugin 2.3.20 and Android Studio's OpenJDK 25.0.2.

iOS simulator debug compilation (`flutter build ios --simulator --debug --dart-define=API_BASE_URL=http://127.0.0.1:8787`) passed with Xcode 27.2 after raising `IPHONEOS_DEPLOYMENT_TARGET` from `13.0` to `15.0` in `mobile/ios/Runner.xcodeproj/project.pbxproj`. The built `Runner.app` was installed and launched on the local `iPhone 17 Pro` simulator (iOS 26.5) against the live Rust server on `127.0.0.1:8787` and verified to load and render the catalog screen.

## Not verified / not implemented

- Interactive Android emulator or physical-device UI runs, physical iOS device builds, signing, app-store packages, or physical-device networking.
- Real VoiceOver/TalkBack sessions, older-adult usability testing, or accessibility certification.
- Full network interception/audit, adversarial security review, remote deployment, authentication, or multi-user operation.
- Actual photo editing, model execution, GPU integration, checker/retry results, nutrition calculation, or clinical/dietary suitability.
- Repository-wide Python/GPU tests: no existing pipeline files were changed, and these checks do not start the project's model services.

These limitations are deliberate prototype boundaries, not successful tests. The app is not a coursework submission or a participant-data collection tool.

## 2026-11-10: Deferred server/domain readiness

On hb-mac, branch `app/senior-meal-preview`, ran `./deploy/predeploy-check.sh` after the API base URL changes: PASS (exit 0). Rust formatting, 19 integration tests, Clippy, 3 Python worker tests, Dart formatting, Flutter analysis, all 42 Flutter tests, web release build, Rust release build and live Rust/Dart dual-mode smoke checks passed. The worker used dry-run fixtures, not real inference. Added two regression tests for same-origin web resolution, route/query removal, explicit override and native loopback fallback.

`git diff --check`, shell syntax checks and ignored-secret-path checks passed. Compose configuration parsed with the checked-in example env file substituted in memory and DOMAIN set; missing DOMAIN correctly fails interpolation. Actual host configuration remains absent by design. Caddy runtime/TLS, production networking and physical-device/browser walkthroughs were not tested in this pass. Web build emitted a non-fatal Cupertino font-family warning; build succeeded.

No deployment, DNS change, domain registration, credentials generation, commit or push performed. See `HOSTING_READINESS.md` for open launch decisions.
