# A little change · Flutter client

Accessible meal-change preview client for Android, iOS, and Web, isolated from the CE7454 coursework submission.

## Run locally

For fresh-clone instructions and verified native build status, read [the mobile build guide](../docs/MOBILE_BUILD.md).

Start the Rust API from the repository root with `cargo run --locked --manifest-path backend/Cargo.toml`, then from this `mobile/` directory:

```sh
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

For an Android emulator, the host computer is `10.0.2.2`:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

For an EC2 HTTPS deployment with Bearer authentication:

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://mealpreview.example.com \
  --dart-define=API_AUTH_TOKEN=<client-bearer-token>
```

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8787 --no-web-resources-cdn
```

Static analysis enforces `strict-casts`, `strict-inference`, `strict-raw-types`, and `comment_references` via [`analysis_options.yaml`](analysis_options.yaml). The web build bundles its Flutter renderer and licensed `Roboto` fonts locally (`assets/fonts/`) rather than depending on runtime CDNs.

## Architecture and UI modules

- [`lib/theme.dart`](lib/theme.dart): `AppColors`, `AppRadius`, `AppLayout`, `AppTypography`, and `buildAppTheme()`.
- [`lib/widgets.dart`](lib/widgets.dart): `NoticeCard`, `StepProgress`, `StepHeading`, `SectionHeading`, `MealCard`, `ChangeOption`, `PreferenceGroup`, `RequestSummary`, `PlateCard`, and `GpuPreviewCard`.
- [`lib/plate.dart`](lib/plate.dart): `PlateIllustration` custom painter with distinct ceramic rims, broth/rice wells, and protein/vegetable shapes.
- [`lib/models.dart`](lib/models.dart): Immutable domain models (`Dish`, `MealChange`, `SelectionRules`, `CatalogCapabilities`, `Catalog`, `MealPreferences`, `EditTarget`, `GpuArtifact`, `MealPreview`) using Dart 3 pattern matching for strict JSON validation.
- [`lib/api.dart`](lib/api.dart): `MealApi` interface and `HttpMealApi` implementation supporting `API_BASE_URL`, `API_AUTH_TOKEN`, and `renderMode`.
- [`lib/main.dart`](lib/main.dart): `MealPreviewApp` and 3-step `MealFlow` state machine with request-version guards and programmatic focus transitions.

## Real API smoke check

With the Rust service running:

```sh
dart run tool/smoke_api.dart http://127.0.0.1:8787
# Or with Tailscale GPU worker enabled:
dart run tool/smoke_api.dart http://127.0.0.1:8787 --expect-gpu
```

Roboto is bundled from the installed Flutter SDK material-font artifacts under Apache 2.0 (`assets/fonts/Roboto_LICENSE.txt`).
