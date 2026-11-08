# Senior Meal Preview

**A separate, non-submission app extension.** This is a working local Rust API and Flutter client for rehearsing preference-led meal changes. It does not modify or run the CE7454 coursework, GPU experiment, BrushNet, Qwen checker, or targeted-retry pipeline.

The illustrations are deliberately simulated. A successful preview means the API validated the requested changes and returned a description, **not** that an AI model edited an image or that a meal is nutritionally appropriate.

## Technology choice

- **Rust + Axum + Tokio**: small typed, stateless HTTP API. The user requested Rust; it remains independent from the existing Python model pipeline.
- **Flutter + Dart**: one accessible UI for Android, iOS, and local web development. The available Mac has Flutter 3.44.8 / Dart 3.12.2 and Rust 1.98.1, so both components can actually be built and checked now.
- React Native is a reasonable choice when reusing an established React/TypeScript app. No such mobile codebase was verified for this project.
- Kotlin is appropriate for an Android-first product, but this prototype should not assume that iOS is out of scope.

Repository inspection confirmed that SgFood-Edit uses Python/PyTorch, BrushNet-SDXL, a Qwen checker, and a Python team-annotation site. It has no existing Flutter, React Native, or Kotlin mobile client. This extension therefore adds Flutter and Rust without replacing the existing research stack or connecting to its inference services.

## What works

1. Load the catalog from the local Rust API.
2. Select one of three illustrative meals.
3. Select one or two compatible changes, such as adding vegetables or trying brown rice.
4. Optionally select a mild-flavour or soft-texture preference.
5. View a clearly labelled simulated plate and the requested editing targets.
6. Change choices, retry failed requests, or start again without saving personal records.

This is an investigator/developer prototype, not a participant study, nutrition calculator, food-safety tool, or clinical recommendation system. The meal examples and changes are illustrative, not guideline-backed recommendations. No calories or health outcomes are invented. A soft-texture preference does not establish swallowing safety.

## Mobile build handoff

Use [docs/MOBILE_BUILD.md](docs/MOBILE_BUILD.md) for a fresh-clone setup, exact Android/iOS commands, toolchain versions and current blockers. The Android debug APK was built successfully on 8 November 2026. The iOS simulator build is currently blocked by missing CoreSimulator components in the local Xcode installation, not yet verified. No emulator/device UI run or release distribution is claimed.

## Start locally

Prerequisites: installed Rust/Cargo and Flutter (tested versions above), plus access to the standard Cargo and pub package registries for the first build.

Terminal 1, from this directory:

```sh
cargo run --locked --manifest-path backend/Cargo.toml
```

The API binds **only** to `127.0.0.1:8787`. To choose another local port, use `APP_PORT=8788 cargo run --locked --manifest-path backend/Cargo.toml`. There is deliberately no public or LAN bind option.

Terminal 2:

```sh
cd mobile
flutter pub get
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=5173 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

The client does not silently fall back to canned results when the API is offline. Start the API and use Retry if needed. The local development workflow is not a deployed website.

For an Android emulator on the same development machine, use `--dart-define=API_BASE_URL=http://10.0.2.2:8787`. For an iOS simulator use the default loopback URL. The backend is intentionally inaccessible to a physical phone over Wi-Fi. Do not expose this unauthenticated prototype to a public network. Native source projects are included, but an emulator/device build or run must be reported separately from Flutter's web build and widget tests.

## Checks

```sh
./scripts/check.sh
```

This runs Rust formatting, tests, Clippy, Flutter dependency resolution, formatting, static analysis, widget/unit tests, and the web build. It does not install system toolchains or start model/GPU work. For a real Rust-to-Dart contract check, run `python3 scripts/smoke.py`. It starts a temporary loopback API, exercises the production Dart client, and stops only its own API process. Full verification limits are in `docs/TESTING.md`.

## Repository layout

- `backend/`: API, typed catalog, strict request validation, and API tests.
- `mobile/`: Flutter Android/iOS/web client and client tests.
- `docs/API.md`: supported API contract and example requests.
- `docs/ARCHITECTURE.md`: separation from model inference, privacy limits, and future integration boundaries.
- `docs/TESTING.md`: verification results and remaining checks.
- `scripts/check.sh`: reproducible local checks.

This app lives only under `extensions/senior-meal-preview/` on a dedicated non-submission branch. Keep it out of the coursework submission bundle. No experiment, report, annotation-site, or inference files are changed. Do not copy generated builds, dependency caches, signing files, photos, experiment outputs, or credentials.

## UI design and takeover

Start with [DESIGN.md](DESIGN.md) for the visual system and prioritized next pass, [AGENT_HANDOFF.md](AGENT_HANDOFF.md) for implementation ownership and run instructions, [UI acceptance](docs/UI_ACCEPTANCE.md) for review scenarios, and [design tokens](docs/design-tokens.json) for baseline/proposed values. These distinguish implemented behavior from future proposals and do not claim native or user-study validation.

## Data handling

No accounts, telemetry, model calls, uploads, database, local preferences storage, or session histories. The client holds choices in memory. The API accepts only predefined meal/change IDs and two preference enums, and does not log request bodies. Requests are capped at 16 KiB. Unknown fields, including photo/health fields, are rejected. API responses use `Cache-Control: no-store`. Browser access is limited to exact HTTP `localhost` / `127.0.0.1` origins; CORS is not authentication.

Future remote deployment, participant use, personal images, persistent records, and actual AI editing need separate security, consent, privacy, evaluation, and model-contract work. They are not enabled here.
