# Agent Handover: Senior Meal Preview (Flutter + Rust EC2 + Tailscale GPU Bridge)

## 1. Quick Orientation & Read Order

1. [README.md](README.md): Scope, stack, local commands, and pre-deployment gate.
2. [DESIGN.md](DESIGN.md) & [docs/design-tokens.json](docs/design-tokens.json): Implemented P0/P1 accessible UI system, unified `AppTypography`, and layout tokens.
3. [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md): **EC2 Rust API gateway + private Tailscale GPU worker deployment architecture**, `systemd` units, Docker Compose, Caddyfile, Tailscale ACLs, and the **5-Phase Next-Week Rollout Schedule & Cutover Runbook**.
4. [docs/API.md](docs/API.md) & [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): API v1 contract, `illustrative_only` vs `gpu_assisted` modes, and SSRF/IMDS security boundaries.
5. [docs/MOBILE_BUILD.md](docs/MOBILE_BUILD.md), [docs/UI_ACCEPTANCE.md](docs/UI_ACCEPTANCE.md), and [docs/TESTING.md](docs/TESTING.md): Native Android/iOS build status and verification records.

## 2. Working Context & Non-Negotiable Boundaries

- **Repository**: this standalone app repository (split with history from the repository root on the coursework repo's `app/senior-meal-preview` branch on 2026-11-10). Branches: `main` (integration) and `production` (what is deployed).
- **Coursework isolation**: The CE7454 coursework repository is separate. Never modify it from here (`sgedit/`, `evaluate/`, `study/`, `report/`, `plan/`, `calib/`, `bench/`) and never merge this app into its `main`. The GPU worker only reads `sgedit` through `WORKER_SGEDIT_ROOT`.
- **Truthful evidence boundary**: Symbolic drawings must always be labelled as simulated (`"Simulated plate illustration"`), and GPU-assisted previews must carry their `GpuArtifact` provenance (`model`, `prompt_id`, `attempts`, `checker_passed` as a selector diagnostic only, and `generated_label` stating it is not a real meal or clinical verification). Never silently substitute a mock image when the GPU worker is offline or times out.

## 3. Current Implemented State (9 November 2026)

### Flutter Client (`mobile/`)
- **Files**: [`lib/main.dart`](mobile/lib/main.dart), [`lib/theme.dart`](mobile/lib/theme.dart), [`lib/widgets.dart`](mobile/lib/widgets.dart), [`lib/plate.dart`](mobile/lib/plate.dart), [`lib/models.dart`](mobile/lib/models.dart), [`lib/api.dart`](mobile/lib/api.dart), [`analysis_options.yaml`](mobile/analysis_options.yaml).
- **Completed UI Redesign & Code Quality Pass**:
  - **Unified Typography (`AppTypography` in [`lib/theme.dart`](mobile/lib/theme.dart))**: Explicit bundled `Roboto` font (`400`, `600`, `700`) across all `TextTheme` slots, buttons, chips, and cards so iOS, Android, and Web never mix platform fallback fonts (`SF Pro` vs `Roboto`) or unbundled italics.
  - **Single-Line Brand Header & Above-the-Fold Step 1 CTA**: Brand badge (`38px`) and `titleLarge` (`20sp`) keep `"A little change"` and `Start over` on one line at `390px` width (wrapping cleanly at `200%` text scale). All 3 `MealCard`s, `Choose my changes`, and the selection status line fit completely inside the `390×844` first viewport without scrolling.
  - **High-Contrast Symbolic Plates ([`lib/plate.dart`](mobile/lib/plate.dart))**: Ceramic rim, golden soup well + outlined fish slices for `Fish soup`, golden tofu squares with soft inner cores for `Tofu rice`, and distinct rice/vegetable/saucer shapes.
  - **Structured Step 2 Customization**: Selected-meal context banner (`40px` mini `PlateIllustration` + `"For your chicken rice"`), dish-specific instruction (`"Choose this change to see an idea"` for Fish soup), inline disabled explanation on the 3rd option when 2 changes are selected, and a unified bordered surface card grouping `Texture`, `Flavour`, and conditional `Preview engine` (`Symbolic drawing` vs `Tailscale GPU model`).
  - **Framed Step 3 Comparison**: Compact `RequestSummary` with neutral bullets followed by `Original idea` and `Requested idea` `PlateCard`s (with a crisp white inner plate stage and `2px` `#163D34` emphasis border on `Requested idea`, visible in the initial `390×844` viewport) plus `GpuPreviewCard` when `gpu_assisted` is used.
  - **Strict Dart 3 Code Hygiene**: Enabled `strict-casts`, `strict-inference`, `strict-raw-types`, and `comment_references` in [`analysis_options.yaml`](mobile/analysis_options.yaml); refactored JSON validation in [`lib/models.dart`](mobile/lib/models.dart) and [`lib/api.dart`](mobile/lib/api.dart) to use idiomatic Dart 3 map pattern matching and switch expressions; documented all public APIs following Effective Dart guidelines (`flutter analyze --fatal-infos` clean).

### Rust Backend (`backend/`)
- **Files**: [`src/lib.rs`](backend/src/lib.rs), [`src/worker.rs`](backend/src/worker.rs), [`src/main.rs`](backend/src/main.rs), [`tests/api.rs`](backend/tests/api.rs).
- **Completed Features**:
  - `GET /healthz`: reports `status`, `mode`, and `gpu_worker: {configured, transport}`.
  - `GET /api/v1/catalog`: publishes `selection: {min_changes: 1, max_changes: 2}` and `capabilities: {symbolic_preview: true, gpu_preview: <bool>}`.
  - `POST /api/v1/preview`: supports `render_mode: "illustrative_only"` (default) and `"gpu_assisted"`.
  - **Tailscale & SSRF Guard (`src/worker.rs`)**: `MODEL_WORKER_URL` only allows Tailscale CGNAT IPv4 (`100.64.0.0/10`), Tailscale IPv6 (`fd7a:115c:a1e0::/48`), MagicDNS (`*.ts.net`), or loopback (`127.0.0.1`/`localhost`). Blocks AWS EC2 IMDS (`169.254.169.254`), RFC1918 LAN IPs, and public hosts, and re-checks resolved IPs at TCP connect time.
  - **EC2 Hardening**: Optional `APP_API_TOKEN` (constant-time Bearer check on `/api/v1/*`), `APP_ALLOWED_ORIGINS` for EC2 HTTPS CORS, 10s/GPU-aware `TimeoutLayer` with structured `408` JSON errors, bounded GPU concurrency (`Semaphore`), and `SIGINT`/`SIGTERM` graceful shutdown.

### Private Tailscale GPU Worker (`gpu-worker/`) & Deployment (`deploy/`)
- [`gpu-worker/gpu_worker.py`](gpu-worker/gpu_worker.py) & [`gpu-worker/test_gpu_worker.py`](gpu-worker/test_gpu_worker.py):
  - Binds strictly to Tailscale (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`) or loopback (`127.0.0.1`), verifies `Authorization: Bearer <MODEL_WORKER_TOKEN>` in constant time, and validates dish/change IDs.
  - `--mode dry-run` returns a deterministic test PNG fixture (`provider: "tailscale-gpu-dry-run"`, `model: "dry_run_fixture"`).
  - `--mode gpu` executes either `WORKER_GPU_CMD` or the `sgedit` BrushNet + Qwen2.5-VL check-and-retry loop against dish fixtures in `WORKER_FIXTURE_DIR`, and **fails closed** with HTTP `503 gpu_pipeline_unready` if GPU fixtures/weights are missing. The built-in loop calls the research contracts (`Editor`, `Runner.candidate`, `base_spec`, `next_spec`, `CheckerClient`) for one edit per request (`brown_rice` or `extra_vegetables` on `chicken_rice`/`tofu_rice`); it is covered by model-free contract tests and has run on a GPU only in private loopback tests on Spark02, where output quality was rejected (see `docs/MODEL_INTEGRATION_PLAN.md`, "Spark02 real-model runs").
- [`deploy/`](deploy/): Contains `predeploy-check.sh`, `Dockerfile.backend`, `Caddyfile`, `docker-compose.ec2.yml`, `systemd/senior-meal-preview-backend.service`, `systemd/senior-meal-preview-gpu-worker.service`, `env/*.example`, `tailscale-acl.hujson`, `deploy-ec2.sh`, and `deploy-gpu-worker.sh`.

## 4. Verification Commands (Run First on Pickup)

From the repository root:

```sh
./deploy/predeploy-check.sh
```

Or run the individual suites:

```sh
./scripts/check.sh
python3 scripts/smoke.py
```

## 5. Next-Week Deployment Tasks for Operator / Follow-Up Agent

1. **Execute the 5-Phase Rollout in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md#4-next-week-rollout-schedule--cutover-runbook)**:
   - **Phase 0**: Run `./deploy/predeploy-check.sh`, generate `APP_API_TOKEN` and `MODEL_WORKER_TOKEN`, and apply `deploy/tailscale-acl.hujson`.
   - **Phase 1**: Bring up Tailscale (`tag:gpu-meal-worker` and `tag:ec2-meal-gateway`) and verify `WORKER_MODE=dry-run` across the `tailscale0` tunnel.
   - **Phase 2**: Populate `/opt/senior-meal-preview/fixtures/<dish_id>/{input.png,mask_rice.png}` on the GPU server (or set `WORKER_GPU_CMD`), switch to `WORKER_MODE=gpu`, and verify `/healthz` reports `"gpu_ready": true`.
   - **Phase 3**: Deploy the EC2 gateway + Caddy TLS (`./deploy/deploy-ec2.sh`) and run `dart run tool/smoke_api.dart https://<DOMAIN> --expect-gpu`.
   - **Phase 4**: Build and distribute the production Web/Android/iOS artifacts and run the 60-second GPU worker outage drill.
2. **Native assistive-technology validation (`A11` in `docs/UI_ACCEPTANCE.md`)**:
   - Complete interactive VoiceOver (`iPhone 17 Pro` simulator or physical iOS device) and TalkBack (`Pixel_10` AVD or Android device) walkthroughs and record findings in `docs/TESTING.md`.
