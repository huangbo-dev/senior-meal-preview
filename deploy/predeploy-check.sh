#!/usr/bin/env bash
# Pre-deployment readiness check for the EC2 Rust API Gateway + Tailscale GPU Worker rollout.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> [1/5] Validating deployment manifests, systemd units, and Tailscale ACLs..."
REQUIRED_FILES=(
  "deploy/Dockerfile.backend"
  "deploy/Caddyfile"
  "deploy/docker-compose.ec2.yml"
  "deploy/tailscale-acl.hujson"
  "deploy/deploy-ec2.sh"
  "deploy/deploy-gpu-worker.sh"
  "deploy/env/backend.env.example"
  "deploy/env/gpu-worker.env.example"
  "deploy/systemd/senior-meal-preview-backend.service"
  "deploy/systemd/senior-meal-preview-gpu-worker.service"
  "gpu-worker/gpu_worker.py"
  "gpu-worker/test_gpu_worker.py"
  "docs/DEPLOYMENT.md"
  "AGENT_HANDOFF.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing required deployment file: $f" >&2
    exit 1
  fi
done

grep -q "tailscaled.service" deploy/systemd/senior-meal-preview-backend.service
grep -q "tailscaled.service" deploy/systemd/senior-meal-preview-gpu-worker.service
grep -q "tag:ec2-meal-gateway" deploy/tailscale-acl.hujson
grep -q "tag:gpu-meal-worker" deploy/tailscale-acl.hujson
grep -q "reverse_proxy" deploy/Caddyfile

echo "==> [2/5] Running full verification suite (./scripts/check.sh)..."
./scripts/check.sh

echo "==> [3/5] Building production release Rust binary (--release --locked)..."
cargo build --release --locked --manifest-path backend/Cargo.toml

echo "==> [4/5] Running dual-mode end-to-end smoke test (python3 scripts/smoke.py)..."
python3 scripts/smoke.py

echo "==> [5/5] Checking git diff hygiene..."
git diff --check

echo "==> Local verification PASSED. Server, DNS, TLS, access controls and real GPU readiness still require deployment validation."
