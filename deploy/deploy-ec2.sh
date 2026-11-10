#!/usr/bin/env bash
# Deploy / update the Senior Meal Preview Rust API gateway on an Ubuntu/Debian EC2 instance.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/opt/senior-meal-preview"
ETC_DIR="/etc/senior-meal-preview"

echo "[1/4] Building release Rust binary..."
cargo build --release --locked --manifest-path "$ROOT/backend/Cargo.toml"

echo "[2/4] Ensuring system user and directories..."
if ! id -u mealpreview >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin mealpreview
fi
sudo mkdir -p "$INSTALL_DIR/bin" "$ETC_DIR"
sudo install -m 0755 "$ROOT/backend/target/release/senior-meal-preview" "$INSTALL_DIR/bin/senior-meal-preview"

if [[ ! -f "$ETC_DIR/backend.env" ]]; then
  sudo install -m 0640 -o root -g mealpreview "$ROOT/deploy/env/backend.env.example" "$ETC_DIR/backend.env"
  echo "Created $ETC_DIR/backend.env from template. Edit tokens and MODEL_WORKER_URL before starting."
fi

echo "[3/4] Installing systemd unit..."
sudo install -m 0644 "$ROOT/deploy/systemd/senior-meal-preview-backend.service" \
  /etc/systemd/system/senior-meal-preview-backend.service
sudo systemctl daemon-reload
sudo systemctl enable senior-meal-preview-backend.service

echo "[4/4] Verifying Tailscale reachability (if tailscale CLI is installed)..."
if command -v tailscale >/dev/null 2>&1; then
  tailscale status || true
fi

echo "Done. Start or restart with: sudo systemctl restart senior-meal-preview-backend"
