#!/usr/bin/env python3
"""Unit and HTTP integration tests for the private Tailscale GPU worker bridge."""

from __future__ import annotations

import json
import os
import shlex
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

import gpu_worker


class TailscaleGpuWorkerTests(unittest.TestCase):
    def test_allowed_bind_ip_enforces_tailscale_or_loopback(self) -> None:
        for allowed in (
            "127.0.0.1",
            "localhost",
            "::1",
            "100.64.0.1",
            "100.101.202.30",
            "100.127.255.254",
            "fd7a:115c:a1e0::1",
        ):
            self.assertTrue(
                gpu_worker.is_allowed_bind_ip(allowed),
                f"Expected {allowed} to be allowed",
            )

        for forbidden in (
            "0.0.0.0",
            "::",
            "169.254.169.254",  # AWS EC2 IMDS
            "10.0.0.5",
            "172.16.0.1",
            "192.168.1.20",
            "100.63.255.255",
            "100.128.0.1",
            "8.8.8.8",
            "example.com",
        ):
            self.assertFalse(
                gpu_worker.is_allowed_bind_ip(forbidden),
                f"Expected {forbidden} to be rejected",
            )

    def _start_server(self, mode: str, token: str | None) -> tuple[ThreadingHTTPServer, str]:
        class IsolatedHandler(gpu_worker.WorkerHandler):
            expected_token = token
            def log_message(self, fmt: str, *args: object) -> None:
                pass

        IsolatedHandler.mode = mode
        server = ThreadingHTTPServer(("127.0.0.1", 0), IsolatedHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        host, port = server.server_address[:2]
        return server, f"http://{host}:{port}"

    def test_dry_run_auth_validation_and_artifact_schema(self) -> None:
        server, base_url = self._start_server(mode="dry-run", token="tailscale-secret-token")
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        # 1. Healthz is open and reports dry-run mode
        with urllib.request.urlopen(f"{base_url}/healthz", timeout=3) as resp:
            self.assertEqual(resp.status, 200)
            health = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(health["status"], "ok")
            self.assertEqual(health["worker_mode"], "dry-run")
            self.assertTrue(health["gpu_ready"])

        payload = json.dumps(
            {
                "schema_version": 1,
                "dish_id": "chicken_rice",
                "change_ids": ["brown_rice", "extra_vegetables"],
                "texture": "soft",
                "flavour": "mild",
            }
        ).encode("utf-8")

        # 2. Missing Bearer token -> 401
        req_unauth = urllib.request.Request(
            f"{base_url}/v1/generate",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req_unauth, timeout=3)
        self.assertEqual(ctx.exception.code, 401)
        ctx.exception.close()

        # 3. Invalid dish_id -> 400
        bad_payload = json.dumps(
            {
                "dish_id": "laksa",
                "change_ids": ["brown_rice"],
                "texture": "any",
                "flavour": "any",
            }
        ).encode("utf-8")
        req_bad = urllib.request.Request(
            f"{base_url}/v1/generate",
            data=bad_payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer tailscale-secret-token",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req_bad, timeout=3)
        self.assertEqual(ctx.exception.code, 400)
        ctx.exception.close()

        # 4. Valid request -> 200 GpuArtifact
        req_ok = urllib.request.Request(
            f"{base_url}/v1/generate",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer tailscale-secret-token",
            },
            method="POST",
        )
        with urllib.request.urlopen(req_ok, timeout=3) as resp:
            self.assertEqual(resp.status, 200)
            artifact = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(artifact["provider"], "tailscale-gpu-dry-run")
            self.assertEqual(artifact["model"], "dry_run_fixture")
            self.assertEqual(artifact["prompt_id"], "t2_r1_hawker_plus_t1b_broccoli")
            self.assertEqual(artifact["attempts"], 1)
            self.assertTrue(artifact["checker_passed"])
            self.assertTrue(artifact["image_data_url"].startswith("data:image/png;base64,"))
            self.assertIn("not a real meal", artifact["generated_label"].lower())

    def test_gpu_mode_fails_closed_when_unconfigured_and_runs_cmd_when_configured(self) -> None:
        server, base_url = self._start_server(mode="gpu", token="gpu-token")
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        payload = json.dumps(
            {
                "dish_id": "tofu_rice",
                "change_ids": ["brown_rice"],
                "texture": "any",
                "flavour": "any",
            }
        ).encode("utf-8")

        # 1. With no WORKER_FIXTURE_DIR or WORKER_GPU_CMD, --mode gpu MUST fail closed (503)
        with mock.patch.dict(os.environ, {"WORKER_FIXTURE_DIR": "", "WORKER_GPU_CMD": ""}, clear=False):
            with urllib.request.urlopen(f"{base_url}/healthz", timeout=3) as resp:
                health = json.loads(resp.read().decode("utf-8"))
                self.assertEqual(health["worker_mode"], "gpu")
                self.assertFalse(health["gpu_ready"])

            req = urllib.request.Request(
                f"{base_url}/v1/generate",
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": "Bearer gpu-token",
                },
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req, timeout=3)
            self.assertEqual(ctx.exception.code, 503)
            err_body = json.loads(ctx.exception.read().decode("utf-8"))
            self.assertEqual(err_body["error"], "gpu_pipeline_unready")
            ctx.exception.close()

        # 2. With WORKER_GPU_CMD configured, --mode gpu returns the real worker artifact
        fake_png = gpu_worker.make_solid_png_data_url((120, 160, 100))
        py_script = (
            "import json, sys; req=json.load(sys.stdin); "
            "print(json.dumps({"
            "'provider': 'tailscale-gpu-worker', "
            "'model': 'brushnet-sdxl+qwen2.5-vl-7b-4bit', "
            "'prompt_id': req['prompt_id'], "
            "'seed': req['seed'], "
            "'attempts': 2, "
            "'checker_passed': True, "
            f"'image_data_url': {fake_png!r}"
            "}))"
        )
        cmd = shlex.join([sys.executable, "-c", py_script])
        with mock.patch.dict(os.environ, {"WORKER_GPU_CMD": cmd}, clear=False):
            req = urllib.request.Request(
                f"{base_url}/v1/generate",
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": "Bearer gpu-token",
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                self.assertEqual(resp.status, 200)
                artifact = json.loads(resp.read().decode("utf-8"))
                self.assertEqual(artifact["provider"], "tailscale-gpu-worker")
                self.assertEqual(artifact["model"], "brushnet-sdxl+qwen2.5-vl-7b-4bit")
                self.assertEqual(artifact["attempts"], 2)
                self.assertTrue(artifact["checker_passed"])


if __name__ == "__main__":
    unittest.main()
