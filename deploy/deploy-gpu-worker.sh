#!/usr/bin/env bash
# Deploy / update the private Tailscale GPU worker on the GPU server.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/opt/senior-meal-preview/gpu-worker"
ETC_DIR="/etc/senior-meal-preview"

echo "[1/3] Checking Tailscale IPv4 address..."
if command -v tailscale >/dev/null 2>&1; then
  TS_IP="$(tailscale ip -4 | head -n 1 || true)"
  echo "Detected Tailscale IPv4: ${TS_IP:-none}"
fi

echo "[2/3] Installing GPU worker service files..."
if ! id -u mealworker >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin mealworker
fi
sudo mkdir -p "$INSTALL_DIR" "$ETC_DIR"
sudo install -m 0755 "$ROOT/gpu-worker/gpu_worker.py" "$INSTALL_DIR/gpu_worker.py"

if [[ ! -f "$ETC_DIR/gpu-worker.env" ]]; then
  sudo install -m 0640 -o root -g mealworker "$ROOT/deploy/env/gpu-worker.env.example" "$ETC_DIR/gpu-worker.env"
  echo "Created $ETC_DIR/gpu-worker.env from template. Set MODEL_WORKER_TOKEN before starting."
fi

echo "[3/3] Installing systemd unit..."
sudo install -m 0644 "$ROOT/deploy/systemd/senior-meal-preview-gpu-worker.service" \
  /etc/systemd/system/senior-meal-preview-gpu-worker.service
sudo systemctl daemon-reload
sudo systemctl enable senior-meal-preview-gpu-worker.service

echo "Done. Start or restart with: sudo systemctl restart senior-meal-preview-gpu-worker"
