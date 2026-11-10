# Build the meal-preview app on another machine

This is the independent **non-submission** app, kept in its own repository, not the CE7454 research pipeline. Work on `main`; `production` is what is deployed. Do not move the app into the coursework repository's `main` or into the coursework bundle.

## Verified status

On 8 November 2026:

- Rust format, 15 API tests and Clippy passed.
- Dart format, static analysis, 25 unit/widget tests and release web build passed.
- Production Dart client against the live Rust API passed.
- **Android debug APK compiled successfully**, including from a separate fresh GitHub clone using the installed SDK/dependency caches. No interactive Android emulator/device UI run was performed.
- **iOS simulator debug app compiled and launched** on `iPhone 17 Pro` (iOS 26.5, Xcode 27.2) after updating `IPHONEOS_DEPLOYMENT_TARGET` to `15.0`.
- No signing, store submission, remote deployment or physical-phone networking is configured or validated.

Full evidence and limits: [TESTING.md](TESTING.md).

## Stack and toolchain

- Mobile/UI: Flutter **3.44.8**, Dart **3.12.2**, Material widgets, package `http`.
- Backend: Rust/Cargo **1.98.1**, Axum **0.8**, Tokio **1**, Serde **1**, tower-http **0.6** (`cors`, `timeout`). Stateless JSON HTTP on loopback; no database.
- Android: Gradle **9.1.0**, Android Gradle Plugin **9.0.1**, Kotlin plugin **2.3.20**. With the tested Flutter SDK: compile/target API **36**, minimum API **24**, build-tools **36.0.0**, NDK **28.2.13676358**. The successful build used Android Studio's bundled OpenJDK **25.0.2**. Java/Kotlin bytecode target is 17; that is not the same as the JDK running Gradle.
- iOS: Swift host project with Xcode **27.2** (`IPHONEOS_DEPLOYMENT_TARGET = 15.0`), verified on the iOS 26.5 simulator runtime.
- Dependency resolution is recorded in `backend/Cargo.lock` and `mobile/pubspec.lock`. Use the tested Flutter release first. New SDK versions need their own verification.

The separate research code remains Python/PyTorch with BrushNet-SDXL and a Qwen checker. The app does not invoke those models. Meal previews are explicitly simulated, not AI-edited photos or nutrition advice.

## 1. Get the correct source

The repository is private (no remote is configured yet on the machine where it was created). Authenticate with an account that already has access; never put tokens into these commands or commit credentials.

```sh
git clone --branch main <this repository's URL> senior-meal-preview
cd senior-meal-preview
git status --short --branch
```

If using an existing checkout, inspect its branch and local changes before switching or pulling. Do not overwrite another developer's work.

Install the standard Rust and Flutter toolchains using their official instructions. For Android, install/configure Android Studio and the SDK components above. On macOS, complete Xcode setup for iOS. First builds need access to Cargo, pub, Gradle and Android dependency repositories.

```sh
rustc --version
cargo --version
flutter --version
flutter doctor -v
```

Inspect any SDK license prompts yourself. The checked Mac reports some unaccepted Android licenses, but its currently installed components were sufficient for the debug APK. Do not blindly pipe acceptance into a license command. This guide does not install toolchains or accept terms for you.

## 2. Start the backend

Terminal A, from the repository root:

```sh
cargo run --locked --manifest-path backend/Cargo.toml
```

The API listens at `http://127.0.0.1:8787`. It intentionally cannot bind to a LAN/public address. Leave this terminal running while using the client. It needs no API key, model weights, GPU, photographs or database.

## 3. Android debug build and emulator

Terminal B, from `mobile/`:

```sh
flutter pub get
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. The installed Flutter SDK regenerates machine-local Android wrapper/local-properties files during its build workflow; these are intentionally not committed. Run builds through Flutter rather than calling a missing `android/gradlew` immediately after cloning.

To run interactively, start an Android emulator through Android Studio, then:

```sh
flutter devices
flutter run -d <android-device-id> \
  --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

Replace `<android-device-id>` with an actual ID from `flutter devices`. `10.0.2.2` addresses the host machine from the standard Android emulator. It is not the backend address for a physical phone. Debug/profile manifests allow local HTTP. Release builds require HTTPS, and their scaffold signing uses the debug key; they are **not distribution-ready**.

## 4. iOS simulator

macOS and a working full Xcode installation with an iOS simulator runtime are required. Recheck the toolchain:

```sh
xcodebuild -version
xcrun simctl list devices available
flutter doctor -v
```

Then, from `mobile/`:

```sh
flutter pub get
flutter build ios --simulator --debug \
  --dart-define=API_BASE_URL=http://127.0.0.1:8787
open -a Simulator
flutter devices
flutter run -d <ios-simulator-id> \
  --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

Replace `<ios-simulator-id>` with the actual simulator ID. Simulator builds do not need App Store signing. Physical-device/archive builds require deliberate signing and networking setup and are outside this handoff.

## 5. Regression checks

From the repository root:

```sh
./scripts/check.sh
python3 scripts/smoke.py
git diff --check
git status --short
```

`check.sh` covers Rust, Dart/Flutter tests and the web build. It does **not** build either native platform. Use the Android/iOS commands above separately and record passed, failed and untested stages honestly. There is no repository CI workflow for this branch at this handoff; these are local results.

Keep generated APKs/apps, dependency caches, signing material, credentials, photos and experiment outputs out of Git. See [AGENT_HANDOFF.md](../AGENT_HANDOFF.md) for UI ownership and [UI_ACCEPTANCE.md](UI_ACCEPTANCE.md) for behavior checks.
