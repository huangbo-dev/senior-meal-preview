#!/usr/bin/env python3
"""Start a temporary local GPU worker and Rust API, run the production Dart smoke client, and stop both."""
from pathlib import Path
import json
import os
import shutil
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
    # The API being up does not mean the worker is listening yet; a request sent now would be
    # reported as gpu_unreachable.
    for _ in range(50):
        try:
            with urllib.request.urlopen(worker_url + "/healthz", timeout=1) as response:
                assert json.load(response)["worker_mode"] == "dry-run"
            break
        except urllib.error.URLError:
            time.sleep(0.1)
    else:
        raise RuntimeError("The temporary GPU worker did not start in time.")
    if shutil.which("dart"):
        subprocess.run(
            ["dart", "run", "tool/smoke_api.dart"],
            cwd=ROOT / "mobile",
            env={**os.environ, "API_BASE_URL": base_url},
            check=True,
        )
    else:
        # No Dart SDK on this machine: exercise the same HTTP contract from Python instead.
        # This does not test the Dart client itself.
        def post(body: dict) -> tuple[int, dict]:
            req = urllib.request.Request(
                base_url + "/api/v1/preview",
                data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=30) as response:
                    return response.status, json.load(response)
            except urllib.error.HTTPError as error:
                with error:
                    return error.code, json.load(error)

        with urllib.request.urlopen(base_url + "/api/v1/catalog", timeout=5) as response:
            catalog = json.load(response)
        assert catalog["capabilities"] == {"symbolic_preview": True, "gpu_preview": False}, catalog
        selection = {"dish_id": "chicken_rice", "change_ids": ["brown_rice"]}
        status, body = post(selection)
        assert status == 200 and "gpu_artifact" not in body, (status, body)
        status, body = post({**selection, "render_mode": "gpu_assisted"})
        assert status == 200, (status, body)
        artifact = body["gpu_artifact"]
        assert artifact["provider"] == "tailscale-gpu-dry-run", artifact
        assert artifact["image_data_url"].startswith("data:image/png;base64,")
        status, body = post({"dish_id": "fish_soup", "change_ids": ["brown_rice"]})
        assert (status, body["error"]["code"]) == (400, "incompatible_change"), (status, body)
        print("Python HTTP smoke passed (dart not installed; Dart client not exercised).")
finally:
    for proc in (api_process, worker_process):
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
