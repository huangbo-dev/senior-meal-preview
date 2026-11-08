# Verification and remaining limits

Verified locally on 8 November 2026, using macOS, Rust/Cargo 1.98.1, Flutter 3.44.8, and Dart 3.12.2. These checks concern this extension only; they do not validate CE7454 model experiments or nutritional outcomes.

## Passed

- Rust formatting, `cargo test --locked` (11 API test functions, including selection/shape/origin matrices), and Clippy for all targets with warnings denied.
- Flutter/Dart formatting, `flutter analyze` with no issues, and 20 unit/widget tests.
- Flutter release web build with locally bundled CanvasKit and Roboto, plus its license. Build artifacts are not committed.
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

## Not verified / not implemented

- Native Android APK, iOS simulator/device builds, signing, app-store packages, or physical-device networking.
- Real VoiceOver/TalkBack sessions, older-adult usability testing, or accessibility certification.
- Full network interception/audit, adversarial security review, remote deployment, authentication, or multi-user operation.
- Actual photo editing, model execution, GPU integration, checker/retry results, nutrition calculation, or clinical/dietary suitability.
- Repository-wide Python/GPU tests: no existing pipeline files were changed, and these checks do not start the project's model services.

These limitations are deliberate prototype boundaries, not successful tests. The app is not a coursework submission or a participant-data collection tool.
