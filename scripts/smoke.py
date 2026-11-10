#!/usr/bin/env python3
"""Start a temporary local GPU worker and Rust API, run the production Dart smoke client, and stop both."""
from pathlib import Path
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


api_port = free_port()
worker_port = free_port()
base_url = f"http://127.0.0.1:{api_port}"
worker_url = f"http://127.0.0.1:{worker_port}"
worker_token = "smoke-tailscale-shared-token"

subprocess.run(
    ["cargo", "build", "--locked", "--manifest-path", str(ROOT / "backend/Cargo.toml")],
    check=True,
)
binary = ROOT / "backend/target/debug/senior-meal-preview"
worker_script = ROOT / "gpu-worker/gpu_worker.py"

worker_process = subprocess.Popen(
    [sys.executable, str(worker_script), "--bind", "127.0.0.1", "--port", str(worker_port), "--mode", "dry-run"],
    cwd=ROOT,
    env={**os.environ, "MODEL_WORKER_TOKEN": worker_token},
)
api_process = subprocess.Popen(
    [str(binary)],
    cwd=ROOT,
    env={
        **os.environ,
        "APP_PORT": str(api_port),
        "MODEL_WORKER_URL": worker_url,
        "MODEL_WORKER_TOKEN": worker_token,
    },
)
try:
    for _ in range(50):
        if api_process.poll() is not None:
            raise RuntimeError("The app's temporary API process exited before the smoke test.")
        if worker_process.poll() is not None:
            raise RuntimeError("The app's temporary GPU worker exited before the smoke test.")
        try:
            with urllib.request.urlopen(base_url + "/healthz", timeout=1) as response:
                health = json.load(response)
                assert health["mode"] == "illustrative_only"
                assert health["gpu_worker"]["configured"] is True
            break
        except urllib.error.URLError:
            time.sleep(0.1)
    else:
        raise RuntimeError("The temporary local API did not start in time.")
    subprocess.run(
        ["dart", "run", "tool/smoke_api.dart"],
        cwd=ROOT / "mobile",
        env={**os.environ, "API_BASE_URL": base_url},
        check=True,
    )
finally:
    for proc in (api_process, worker_process):
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
