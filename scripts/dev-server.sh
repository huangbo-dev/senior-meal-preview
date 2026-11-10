#!/usr/bin/env bash
# Start/stop a loopback-only test stack: GPU worker + Rust API gateway.
#   scripts/dev-server.sh start [dry-run|gpu]   (default dry-run: placeholder image, no model)
#   scripts/dev-server.sh stop | status
# Ports: DEV_API_PORT (default 8787), DEV_WORKER_PORT (default 8791). Both bind 127.0.0.1 only.
# gpu mode additionally needs WORKER_FIXTURE_DIR, SGEDIT_BASELINE, a running checker and
# WORKER_PYTHON pointing at the BrushNet environment (see deploy/env/gpu-worker.env.example).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${DEV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/senior-meal-preview-dev}"
API_PORT="${DEV_API_PORT:-8787}"
WORKER_PORT="${DEV_WORKER_PORT:-8791}"
[[ -d "$HOME/.cargo/bin" ]] && PATH="$HOME/.cargo/bin:$PATH"

running() { [[ -f "$STATE/$1.pid" ]] && kill -0 "$(cat "$STATE/$1.pid")" 2>/dev/null; }

stop() {
  for name in api worker; do
    if running "$name"; then kill "$(cat "$STATE/$name.pid")" && echo "stopped $name"; fi
    rm -f "$STATE/$name.pid"
  done
}

wait_for() {  # url, name
  for _ in $(seq 100); do
    curl -fs -m 1 "$1" >/dev/null 2>&1 && return 0
    running "$2" || { echo "$2 exited; see $STATE/$2.log" >&2; tail -n 5 "$STATE/$2.log" >&2; return 1; }
    sleep 0.2
  done
  echo "$2 did not answer at $1" >&2; return 1
}

case "${1:-status}" in
  start)
    mode="${2:-dry-run}"
    mkdir -p "$STATE"
    if running api || running worker; then echo "already running; use: $0 stop" >&2; exit 1; fi
    for port in "$API_PORT" "$WORKER_PORT"; do
      if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        echo "port $port is already in use; set DEV_API_PORT / DEV_WORKER_PORT" >&2; exit 1
      fi
    done
    cargo build --release --locked --manifest-path "$ROOT/backend/Cargo.toml"
    [[ -f "$STATE/worker.token" ]] || (umask 077; python3 -c "import secrets; print(secrets.token_hex(24))" >"$STATE/worker.token")
    token="$(cat "$STATE/worker.token")"
    MODEL_WORKER_TOKEN="$token" setsid nohup "${WORKER_PYTHON:-python3}" "$ROOT/gpu-worker/gpu_worker.py" \
      --bind 127.0.0.1 --port "$WORKER_PORT" --mode "$mode" >"$STATE/worker.log" 2>&1 &
    echo $! >"$STATE/worker.pid"
    wait_for "http://127.0.0.1:$WORKER_PORT/healthz" worker || { stop; exit 1; }
    APP_PORT="$API_PORT" MODEL_WORKER_URL="http://127.0.0.1:$WORKER_PORT" MODEL_WORKER_TOKEN="$token" \
      MODEL_WORKER_MAX_CONCURRENT=1 setsid nohup "$ROOT/backend/target/release/senior-meal-preview" \
      >"$STATE/api.log" 2>&1 &
    echo $! >"$STATE/api.pid"
    wait_for "http://127.0.0.1:$API_PORT/healthz" api || { stop; exit 1; }
    echo "API    http://127.0.0.1:$API_PORT   (worker mode: $mode, http://127.0.0.1:$WORKER_PORT)"
    echo "logs   $STATE/{api,worker}.log"
    ;;
  stop) stop ;;
  status)
    for name in api worker; do running "$name" && echo "$name running (pid $(cat "$STATE/$name.pid"))" || echo "$name not running"; done
    ;;
  *) echo "usage: $0 start [dry-run|gpu] | stop | status" >&2; exit 2 ;;
esac
