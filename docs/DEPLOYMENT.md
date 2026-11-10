# EC2 + Tailscale GPU Worker Deployment Guide

This guide explains how to deploy the **Senior Meal Preview** Rust API gateway on an **AWS EC2** instance while routing optional GPU model requests over a private **Tailscale** mesh network (`tailscale0`) to a separate GPU machine.

> Hosting and domain are not selected. See [HOSTING_READINESS.md](HOSTING_READINESS.md) first. This is an optional EC2 recipe, not authorization to deploy or a committed calendar. Shared client tokens in compiled apps are extractable; use a proper access gateway/session design before public GPU access. Never embed MODEL_WORKER_TOKEN in a client.

## 1. Topology and Security Boundary

```text
[Flutter Mobile / Web Client]
        │  HTTPS (TLS 1.3 via Caddy / ALB, optional Bearer APP_API_TOKEN)
        ▼
[AWS EC2: Caddy Reverse Proxy :443]
        │  Loopback HTTP (127.0.0.1:8787)
        ▼
[AWS EC2: Rust API Gateway (senior-meal-preview)]
        ├── symbolic mode ("illustrative_only"): answered locally in <1 ms
        │
        └── gpu_assisted mode: validated IDs + Bearer MODEL_WORKER_TOKEN
                │  Encrypted WireGuard tunnel over tailscale0 (100.64.0.0/10 or *.ts.net:8790)
                ▼
        [Private GPU Server: gpu-worker/gpu_worker.py]
```

### Enforced safety controls

- **SSRF and IMDS protection (`backend/src/worker.rs`)**: `MODEL_WORKER_URL` only accepts `http://` targets in the Tailscale CGNAT IPv4 range (`100.64.0.0/10`), Tailscale IPv6 ULA (`fd7a:115c:a1e0::/48`), Tailscale MagicDNS (`*.ts.net`), or loopback (`127.0.0.1` / `localhost`). It explicitly blocks AWS EC2 Instance Metadata Service (`169.254.169.254`), RFC1918 LAN ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), and public hosts, and re-verifies resolved IPs at connect time to prevent DNS rebinding.
- **No arbitrary prompt or path injection**: The EC2 gateway validates `dish_id`, `change_ids`, and `preferences` against the static catalog before contacting the worker, and sends only those structured IDs (`WorkerGenerateRequest`).
- **Truthful failure modes (`--mode gpu` fail-closed)**:
  - In `--mode dry-run`, the worker returns a deterministic test fixture labelled `provider: "tailscale-gpu-dry-run"` and `model: "dry_run_fixture"`.
  - In `--mode gpu`, the worker executes either `WORKER_GPU_CMD` or the `sgedit` BrushNet + Qwen2.5-VL check-and-retry loop against dish fixtures in `WORKER_FIXTURE_DIR`. If neither is ready, it **fails closed** with HTTP `503 gpu_pipeline_unready` (never returning a synthetic dry-run image disguised as a real GPU output).
  - If the GPU worker is unconfigured (`503 gpu_unavailable`), busy (`503 gpu_busy`), times out (`504 gpu_timeout`), or unreachable (`502 gpu_unreachable`), the EC2 API never substitutes a silent fallback image.
- **Least-privilege Tailscale ACLs ([deploy/tailscale-acl.hujson](../deploy/tailscale-acl.hujson))**: `tag:ec2-meal-gateway` is permitted to connect only to `tag:gpu-meal-worker:8790`.

---

## 2. Pre-Flight Gate (Run Before Touching Production Hosts)

From `extensions/senior-meal-preview/`:

```sh
./deploy/predeploy-check.sh
```

This script verifies all deployment manifests, runs Rust formatting/Clippy/19 integration tests, runs the Python GPU worker unit test suite (`gpu-worker/test_gpu_worker.py`), runs Flutter analysis/26 widget tests/web release build, compiles the `--release --locked` Rust binary, and executes the dual-mode end-to-end smoke test (`scripts/smoke.py`).

---

## 3. Step-by-Step Setup

### Step A: Provision Tailscale on both hosts

1. In the Tailscale Admin Console, apply the ACL tags and rule from `deploy/tailscale-acl.hujson`.
2. On the **GPU server**:
   ```sh
   sudo tailscale up --advertise-tags=tag:gpu-meal-worker
   tailscale ip -4   # Note this 100.x.y.z address
   ```
3. On the **EC2 instance**:
   ```sh
   sudo tailscale up --advertise-tags=tag:ec2-meal-gateway
   ```

### Step B: Start the Private GPU Worker

On the GPU machine, from `extensions/senior-meal-preview/`:

```sh
./deploy/deploy-gpu-worker.sh
sudo nano /etc/senior-meal-preview/gpu-worker.env
# Set:
#   MODEL_WORKER_TOKEN=<shared-32-byte-hex-secret>
#   WORKER_MODE=dry-run   # Start with dry-run for tunnel verification, then switch to gpu
#   WORKER_FIXTURE_DIR=/opt/senior-meal-preview/fixtures
#   WORKER_CHECKER_URL=http://127.0.0.1:8000/v1
sudo systemctl restart senior-meal-preview-gpu-worker
sudo systemctl status senior-meal-preview-gpu-worker
```

The worker binds strictly to the GPU server's `100.x.y.z` Tailscale IP (or `127.0.0.1` in local dry-run tests) and refuses `0.0.0.0`.

### Step C: Deploy the Rust API Gateway on EC2

#### Option 1: Bare-metal `systemd` + Caddy (recommended on a small t4g/t3 EC2 instance)

From `extensions/senior-meal-preview/` on the EC2 instance:

```sh
./deploy/deploy-ec2.sh
sudo nano /etc/senior-meal-preview/backend.env
# Set:
#   APP_BIND_ADDR=127.0.0.1
#   APP_PORT=8787
#   APP_ALLOWED_ORIGINS=https://mealpreview.example.com
#   APP_API_TOKEN=<client-bearer-token>
#   MODEL_WORKER_URL=http://100.x.y.z:8790
#   MODEL_WORKER_TOKEN=<shared-32-byte-hex-secret>
sudo systemctl restart senior-meal-preview-backend
curl -s http://127.0.0.1:8787/healthz
```

Install Caddy and copy `deploy/Caddyfile` to `/etc/caddy/Caddyfile` (setting `DOMAIN=mealpreview.example.com`), then `sudo systemctl reload caddy`.

#### Option 2: Docker Compose on EC2

```sh
cp deploy/env/backend.env.example deploy/env/backend.env
# Edit deploy/env/backend.env with your tokens and Tailscale IP
DOMAIN=mealpreview.example.com docker compose -f deploy/docker-compose.ec2.yml up -d --build
```

### Step D: Build Flutter Mobile / Web Clients for EC2

From `extensions/senior-meal-preview/mobile/`:

```sh
# Web bundle served by Caddy on EC2
flutter build web --release --no-web-resources-cdn
# Defaults to the serving origin. For a private shared-token demo only,
# add API_AUTH_TOKEN matching the backend (extractable from the bundle).

# Android APK pointing to EC2 HTTPS endpoint
flutter build apk --release \
  --dart-define=API_BASE_URL=https://mealpreview.example.com \
  --dart-define=API_AUTH_TOKEN=<client-bearer-token>

# iOS Simulator pointing to EC2 HTTPS endpoint
flutter build ios --simulator --debug \
  --dart-define=API_BASE_URL=https://mealpreview.example.com \
  --dart-define=API_AUTH_TOKEN=<client-bearer-token>
```

> **Note:** When Caddy serves both the Flutter web bundle (`root * /srv/web`) and `/api/v1/*` on the same HTTPS domain (`deploy/Caddyfile`), `connect-src 'self'` in `mobile/web/index.html` already permits same-origin API calls. Only add an explicit domain to `connect-src` if the web bundle and API are hosted on different origins.

---

## 4. Next-Week Rollout Schedule & Cutover Runbook

| Phase | Target Window | Owner / Host | Actions & Verification Gates |
| --- | --- | --- | --- |
| **Phase 0: Pre-Flight & Secrets** | Day 1 | Dev workstation | 1. Run `./deploy/predeploy-check.sh` (must exit `0`).<br>2. Generate two independent 32-byte hex tokens (`openssl rand -hex 32`): one for `APP_API_TOKEN` (Client -> EC2) and one for `MODEL_WORKER_TOKEN` (EC2 -> GPU Worker).<br>3. Apply `deploy/tailscale-acl.hujson` in Tailscale Admin Console. |
| **Phase 1: Tailscale Tunnel & Dry-Run Smoke** | Day 2 | GPU Server + EC2 | 1. Join GPU server (`--advertise-tags=tag:gpu-meal-worker`) and EC2 (`--advertise-tags=tag:ec2-meal-gateway`) to Tailscale.<br>2. Run `./deploy/deploy-gpu-worker.sh` on GPU server with `WORKER_MODE=dry-run`.<br>3. From EC2, verify `curl -s http://100.x.y.z:8790/healthz` returns `{"status":"ok","worker_mode":"dry-run","gpu_ready":true}`.<br>4. Verify reverse path is blocked by ACL (`curl` from GPU server to EC2 must time out). |
| **Phase 2: GPU Pipeline Cutover (`--mode gpu`)** | Day 3 | GPU Server | 1. Stage dish base images and masks under `/opt/senior-meal-preview/fixtures/<dish_id>/{input.png,mask_<change_id>.png}` and start the local Qwen2.5-VL checker on `127.0.0.1:8000` (or set `WORKER_GPU_CMD`).<br>2. Set `WORKER_MODE=gpu` in `/etc/senior-meal-preview/gpu-worker.env` and restart `senior-meal-preview-gpu-worker`.<br>3. Verify `GET /healthz` returns `"gpu_ready": true` and a signed `POST /v1/generate` returns `"provider": "tailscale-gpu-worker"`. |
| **Phase 3: EC2 Gateway & Caddy TLS Cutover** | Day 4 | EC2 Instance | 1. Run `./deploy/deploy-ec2.sh` and configure `/etc/senior-meal-preview/backend.env`.<br>2. Verify `curl -s https://<DOMAIN>/healthz` returns `{"status":"ok","mode":"illustrative_only","gpu_worker":{"configured":true,"transport":"tailscale"}}`.<br>3. Run `dart run tool/smoke_api.dart https://<DOMAIN> --expect-gpu` (with `API_AUTH_TOKEN` if enabled). |
| **Phase 4: Client Distribution & Rollback Drill** | Day 5 | Client / Ops | 1. Publish Web bundle to `/opt/senior-meal-preview/web` and distribute Android APK / iOS build.<br>2. **Rollback drill**: Stop `senior-meal-preview-gpu-worker` for 60 seconds; verify the app returns `502 gpu_unreachable` on `gpu_assisted` with a clear prompt to switch to `Symbolic drawing`, while `illustrative_only` continues serving in `<1 ms`. Restart worker. |
