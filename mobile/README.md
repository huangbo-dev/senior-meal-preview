# A little change · Flutter client

Local-only meal-change preview prototype, isolated from coursework submission.

## Run

Start the Rust API from the repository root (see the root README), then:

```sh
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

For an Android emulator, the host computer is `10.0.2.2`:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

The default base URL is `http://127.0.0.1:8787`. An iOS simulator can use that loopback address. Native Android/iOS targets are scaffolded, but require a configured Android SDK or Xcode before a device build. Physical devices cannot use the computer's loopback address; authenticated TLS deployment and deliberate server network configuration are outside this prototype.

Android cleartext HTTP is enabled only in debug/profile manifests to reach the local development API. Release builds require HTTPS. The iOS plist permits local networking and explains the local-server purpose. No broad arbitrary-load exception is configured. Native builds and device permission flows must be validated before distributing this app.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8787 --no-web-resources-cdn
```

The web build bundles its Flutter renderer and licensed Roboto fonts rather than depending on runtime CDNs. The custom bootstrap keeps renderer/fallback-font URLs local. A development Content Security Policy restricts network connections to the app origin and loopback, with WebAssembly and dev-loader allowances. The English demo does not bundle extra-language fallback fonts; adding languages requires bundling the relevant fonts rather than enabling a remote CDN. Serve the build locally on an API-allowed origin (for example `http://localhost:5173` or `http://127.0.0.1:5173`). Do not open index.html directly from the filesystem. There is no offline data fallback or registered service worker.

## Behavior and scope

- Fetches the dish/change catalog from `GET /api/v1/catalog`.
- Lets the user select one dish and one or two compatible serving changes.
- Sends only IDs and optional texture/flavour requests to `POST /api/v1/preview`.
- Shows symbolic original/requested plate drawings, explicit simulated labels and text targets.
- Keeps choices only in memory. No login, telemetry, photos, camera, image upload, cloud service, dietary profile or persistence.
- Does not generate model images, calculate nutrition, verify allergens/texture or establish clinical safety. Soft/mild preferences remain requests only.
- Prevents repeated submits; late responses after Back or Start over are ignored. Errors retain choices and offer retry rather than pretending the server succeeded.
- Large controls, high-contrast text, screen-reader labels and scrollable layouts support 200% text scaling. Automated accessibility checks are not a substitute for testing with older adults and assistive technologies.

Tests use an injected fake API and HTTP mock client; they do not contact a cloud service or model. The backend contract is versioned and unknown modes are rejected.

## Real API smoke check

With the Rust service already running:

```sh
dart run tool/smoke_api.dart
# Optional: API_BASE_URL=http://127.0.0.1:8787 dart run tool/smoke_api.dart
```

This uses the production Dart API client for catalog, preview/preferences, unknown-dish rejection and incompatible-change rejection. It does not start or stop the server.

Roboto is bundled from the installed Flutter SDK material-font artifacts under Apache 2.0. Its license is included at `assets/fonts/Roboto_LICENSE.txt` and in the built app assets.
