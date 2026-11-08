#!/usr/bin/env python3
"""Build/start our loopback API, exercise production Dart client, stop our child."""
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
subprocess.run(["cargo", "build", "--locked", "--manifest-path", str(ROOT / "backend/Cargo.toml")], check=True)
with socket.socket() as socket_probe:
    socket_probe.bind(("127.0.0.1", 0))
    port = socket_probe.getsockname()[1]
base_url = f"http://127.0.0.1:{port}"
binary = ROOT / "backend/target/debug" / ("senior-meal-preview.exe" if os.name == "nt" else "senior-meal-preview")
process = subprocess.Popen([str(binary)], env={**os.environ, "APP_PORT": str(port)})
try:
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError("The app's temporary API process exited before the smoke test.")
        try:
            with urllib.request.urlopen(base_url + "/healthz", timeout=1) as response:
                assert json.load(response)["mode"] == "illustrative_only"
            break
        except urllib.error.URLError:
            time.sleep(0.1)
    else:
        raise RuntimeError("The temporary local API did not start in time.")
    subprocess.run(["dart", "run", "tool/smoke_api.dart"], cwd=ROOT / "mobile", env={**os.environ, "API_BASE_URL": base_url}, check=True)
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
