# Senior Meal Preview

**A separate, non-submission app.** This is a working Rust API and Flutter client for rehearsing preference-led meal changes. It lives in its own repository and does not modify any CE7454 coursework files (`sgedit/`, `evaluate/`, `study/`, `report/`, `plan/`, `calib/`, `bench/`); the optional GPU worker only reads the coursework `sgedit` package from the checkout named by `WORKER_SGEDIT_ROOT`.

## Branches

- `main`: integration branch; all work lands here.
- `production`: what is deployed. Move it forward only by fast-forward from `main` (`git switch production && git merge --ff-only main`) after `./deploy/predeploy-check.sh` passes on the commit being promoted.

No other long-lived branches. Nothing is pushed or deployed automatically.

By default, previews are deterministic symbolic plate drawings (`render_mode: "illustrative_only"`). When deployed on an **AWS EC2 instance** connected over a private **Tailscale** mesh network (`tailscale0`) to a GPU machine running `gpu-worker/gpu_worker.py`, the app also supports an optional `gpu_assisted` preview mode with full model/prompt/attempt provenance (`GpuArtifact`) and strict fail-closed error handling.

## Technology choice

- **Rust + Axum + Tokio (`backend/`)**: small typed, stateless HTTP API gateway with SSRF/IMDS boundary guards (`src/worker.rs`), optional constant-time Bearer authentication (`APP_API_TOKEN`), bounded GPU concurrency, and structured timeout/error responses.
- **Flutter + Dart (`mobile/`)**: one accessible UI for Android, iOS, and Web (`Flutter 3.44.8` / `Dart 3.12.2` and `Rust 1.98.1`), featuring unified bundled `Roboto` typography (`AppTypography`), high-contrast `#718476` card boundaries, 3-step keyboard/screen-reader focus transitions, and responsive layouts from `360×800` @ 200% text scale up to `800×900` wide screens.
- **Private Tailscale GPU Worker (`gpu-worker/`)**: Python service that binds strictly to Tailscale CGNAT IPv4 (`100.64.0.0/10`), Tailscale IPv6 (`fd7a:115c:a1e0::/48`), or loopback (`127.0.0.1`), verifies `MODEL_WORKER_TOKEN`, and either serves a deterministic test fixture (`--mode dry-run`) or invokes the GPU pipeline (`--mode gpu`, failing closed with HTTP `503` if GPU fixtures/weights are absent).

## What works

1. Load the meal and change catalog from the Rust API (`GET /api/v1/catalog`), including enforced selection bounds (`1–2` changes) and server capabilities (`symbolic_preview`, `gpu_preview`).
2. Select one of three familiar meals (`Chicken rice`, `Fish soup`, `Tofu rice`) on a single-screen layout where the primary CTA (`Choose my changes`) sits above the fold on a `390×844` phone screen.
3. Select one or two compatible changes (`Add vegetables`, `Try brown rice`, `Sauce on the side`) with dish-specific copy (`"Choose this change to see an idea"` for Fish soup) and an inline explanation when the 2-change limit is reached.
4. Optionally select `Texture` (`No preference` / `Soft`), `Flavour` (`No preference` / `Mild`), and—when the server advertises a Tailscale GPU worker—`Preview engine` (`Symbolic drawing` / `Tailscale GPU model`).
5. View the requested changes (`What you requested` with neutral bullets) followed by framed `Original idea` and `Requested idea` plates (and `GpuPreviewCard` provenance when `gpu_assisted` is used).
6. Change choices, retry failed requests, or start over without saving personal records.

This is an investigator/developer prototype, not a participant study, nutrition calculator, food-safety tool, or clinical recommendation system. A soft-texture preference does not establish swallowing safety.

## Quick verification & pre-deployment gate

From the repository root:

```sh
./deploy/predeploy-check.sh
```

Or run the individual checks:

```sh
./scripts/check.sh
python3 scripts/smoke.py
```

- `check.sh` runs `cargo fmt --check`, `cargo test --locked` (19 Rust integration tests), `cargo clippy -- -D warnings`, `python3 -m unittest discover -s gpu-worker -p "test_*.py"` (3 GPU worker unit/HTTP test suites), `flutter pub get`, `dart format`, `flutter analyze --fatal-infos` (with `strict-casts`, `strict-inference`, `strict-raw-types`, and `comment_references`), `flutter test` (26 Flutter unit/widget tests), and `flutter build web --release --no-web-resources-cdn`.
- `smoke.py` boots both the Python Tailscale GPU worker (`gpu_worker.py --mode dry-run`) and the Rust API gateway, runs the production Dart client (`mobile/tool/smoke_api.dart`) across both `illustrative_only` and `gpu_assisted` modes plus negative validation checks, and stops both processes cleanly.

## Start locally

Terminal 1 (Rust API on `127.0.0.1:8787`):

```sh
cargo run --locked --manifest-path backend/Cargo.toml
```

Terminal 2 (Flutter client):

```sh
cd mobile
flutter pub get
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=5173 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

For an Android emulator on the same development machine, use `--dart-define=API_BASE_URL=http://10.0.2.2:8787`. For an iOS simulator, use the default loopback URL (`http://127.0.0.1:8787`). See [docs/MOBILE_BUILD.md](docs/MOBILE_BUILD.md) for verified Android APK and iOS Simulator (`iPhone 17 Pro`, iOS 26.5) build instructions.

## Choose hosting and domain later

See [docs/HOSTING_READINESS.md](docs/HOSTING_READINESS.md) for the provider-neutral configuration contract and remaining launch decisions. Web builds default to the serving origin; native builds use the configured API URL. The existing EC2 kit is an option, not a selected server.

## EC2 + Tailscale GPU deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the complete architecture, SSRF/IMDS security controls, `systemd` services, Docker Compose + Caddy TLS setup, Tailscale ACL policy (`deploy/tailscale-acl.hujson`), and the 5-phase **Next-Week Rollout Schedule & Cutover Runbook**.

## Repository layout

- [AGENT_HANDOFF.md](AGENT_HANDOFF.md): orientation, architecture summary, verification commands, and next-week rollout tasks.
- [DESIGN.md](DESIGN.md) & [docs/design-tokens.json](docs/design-tokens.json): visual system, typography, color contrast, and P0/P1/P2 status.
- `backend/`: Rust Axum API gateway (`src/lib.rs`, `src/worker.rs`, `src/main.rs`) and 19 integration tests (`tests/api.rs`).
- `mobile/`: Flutter Android/iOS/Web client (`lib/main.dart`, `lib/theme.dart`, `lib/widgets.dart`, `lib/plate.dart`, `lib/models.dart`, `lib/api.dart`) and 26 unit/widget tests (`test/`).
- `gpu-worker/`: Tailscale GPU model-worker bridge (`gpu_worker.py`) and unit tests (`test_gpu_worker.py`).
- `deploy/`: EC2 + Tailscale deployment manifests (`Dockerfile.backend`, `Caddyfile`, `docker-compose.ec2.yml`, `systemd/*.service`, `env/*.example`, `tailscale-acl.hujson`, `deploy-ec2.sh`, `deploy-gpu-worker.sh`, `predeploy-check.sh`).
- `docs/`: [API.md](docs/API.md), [ARCHITECTURE.md](docs/ARCHITECTURE.md), [DEPLOYMENT.md](docs/DEPLOYMENT.md), [MOBILE_BUILD.md](docs/MOBILE_BUILD.md), [TESTING.md](docs/TESTING.md), and [UI_ACCEPTANCE.md](docs/UI_ACCEPTANCE.md).
