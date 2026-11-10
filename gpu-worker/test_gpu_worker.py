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


def _research_deps_available() -> bool:
    try:
        import numpy  # noqa: F401
        import PIL  # noqa: F401
        import scipy  # noqa: F401
        import torch  # noqa: F401
    except Exception:
        return False
    return gpu_worker.sgedit_root() is not None


def _chk(edit: float = 2.0, preserve: float = 2.0, realism: float = 5.0, extra: float = 0.0) -> dict:
    return {
        "edit": {"score": edit},
        "preserve": {"score": preserve},
        "realism": {"score": realism},
        "extra": {"score": extra},
        "model": "fake-checker",
    }


EDIT_FAIL = _chk(edit=0.2)
REALISM_FAIL = _chk(realism=1.5)


class FakeEditor:
    """Stands in for sgedit.editor.Editor: same edit(image, mask, spec) -> (image, meta) contract."""

    def __init__(self) -> None:
        self.specs: list = []
        self.delay = 0.0

    def edit(self, image, mask, spec):
        from dataclasses import asdict

        import numpy as np
        from PIL import Image

        assert image.size == mask.shape[::-1] and mask.dtype == bool
        if self.delay:
            import time

            time.sleep(self.delay)
        self.specs.append(spec)
        arr = np.asarray(image).copy()
        arr[mask] = (120 + 10 * len(self.specs), 90, 50)
        return Image.fromarray(arr), {**asdict(spec), "crop_box": None, "seconds": 0.0}


@unittest.skipUnless(_research_deps_available(), "needs numpy, scipy, torch, PIL and the repo's sgedit package")
class BuiltinSgeditAdapterTests(unittest.TestCase):
    """Runs the worker's built-in path through the real sgedit.loop code with a fake editor and checker."""

    @classmethod
    def setUpClass(cls) -> None:
        import tempfile

        cls._tmp = tempfile.TemporaryDirectory()
        base = os.path.join(cls._tmp.name, "baseline")
        os.makedirs(os.path.join(base, "experiment", "config"))
        with open(os.path.join(base, "experiment", "config", "generation_prompts.json"), "w") as fh:
            json.dump({k: f"stub baseline prompt {k}" for k in ("T1-B_rice", "T1-B_noodles", "T2_rice")}, fh)
        cls._env = mock.patch.dict(os.environ, {"SGEDIT_BASELINE": base})
        cls._env.start()
        cls.research = gpu_worker.load_research()

    @classmethod
    def tearDownClass(cls) -> None:
        cls._env.stop()
        cls._tmp.cleanup()

    def setUp(self) -> None:
        import tempfile
        from http.server import BaseHTTPRequestHandler

        from PIL import Image

        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.fixtures = os.path.join(self.tmp.name, "fixtures")
        for dish in ("chicken_rice", "tofu_rice"):
            os.makedirs(os.path.join(self.fixtures, dish))
            Image.new("RGB", (1024, 1024), (200, 180, 160)).save(os.path.join(self.fixtures, dish, "input.png"))
            mask = Image.new("L", (1024, 1024), 0)
            mask.paste(255, (300, 400, 700, 800))
            mask.save(os.path.join(self.fixtures, dish, "mask_rice.png"))

        self.editor = FakeEditor()
        patcher = mock.patch.object(gpu_worker, "_EDITOR", self.editor)
        patcher.start()
        self.addCleanup(patcher.stop)

        test = self
        self.script: list[dict] = []
        self.checker_requests: list[dict] = []

        class FakeChecker(BaseHTTPRequestHandler):
            def log_message(self, *a: object) -> None:
                pass

            def do_POST(self) -> None:  # noqa: N802
                req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                req["edited_exists"] = os.path.isfile(req["edited"])
                test.checker_requests.append(req)
                body = json.dumps(test.script.pop(0) if test.script else _chk()).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.checker = ThreadingHTTPServer(("127.0.0.1", 0), FakeChecker)
        threading.Thread(target=self.checker.serve_forever, daemon=True).start()
        self.addCleanup(self.checker.server_close)
        self.addCleanup(self.checker.shutdown)
        env = mock.patch.dict(
            os.environ,
            {
                "WORKER_FIXTURE_DIR": self.fixtures,
                "WORKER_CHECKER_URL": f"http://127.0.0.1:{self.checker.server_address[1]}",
                "WORKER_GPU_CMD": "",
                "WORKER_RUN_DIR": "",
                "WORKER_MAX_ATTEMPTS": "4",
                "WORKER_TIME_BUDGET_SECS": "0",
            },
        )
        env.start()
        self.addCleanup(env.stop)

    def run_edit(self, dish: str = "chicken_rice", changes: tuple[str, ...] = ("brown_rice",)) -> dict:
        return gpu_worker.run_gpu_pipeline(dish, list(changes), "any", "any", "ignored", 0)

    def test_first_attempt_pass_returns_gateway_artifact_schema(self) -> None:
        import base64
        import io

        from PIL import Image

        art = self.run_edit()
        # Exactly the fields of the Rust GpuArtifact (serde deny_unknown_fields).
        self.assertEqual(
            set(art),
            {"provider", "model", "prompt_id", "seed", "attempts", "checker_passed", "image_data_url", "generated_label"},
        )
        self.assertEqual(art["provider"], "tailscale-gpu-worker")
        self.assertEqual(art["attempts"], 1)
        self.assertTrue(art["checker_passed"])
        self.assertEqual(art["seed"], self.research.loop.POLICY["seeds"][0])
        self.assertEqual(art["prompt_id"], f"sgedit-{self.research.loop.POLICY['version']}:tuned:T2/rice:ladder0:g7.5")
        self.assertIn("not", art["generated_label"].lower())
        png = base64.b64decode(art["image_data_url"].split(",", 1)[1])
        self.assertEqual(Image.open(io.BytesIO(png)).size, (768, 768))
        self.assertLess(len(art["image_data_url"]), 4 * 1024 * 1024)

    def test_checker_receives_research_request_contract(self) -> None:
        self.run_edit("tofu_rice", ("extra_vegetables",))
        (req,) = self.checker_requests
        self.assertEqual(req["task"], "T1-B")
        self.assertEqual(req["source"], "rice")
        self.assertEqual(req["original"], os.path.realpath(os.path.join(self.fixtures, "tofu_rice", "input.png")))
        self.assertTrue(req["edited_exists"])
        self.assertEqual(len(req["crop_box"]), 4)
        self.assertEqual(self.editor.specs[0].prompt, "stub baseline prompt T1-B_rice")

    def test_base_spec_is_the_locked_policy(self) -> None:
        self.run_edit()
        loop, spec = self.research.loop, self.editor.specs[0]
        prompt, negative = loop.ladder("T2", "rice", "tuned")[0]
        self.assertEqual((spec.prompt, spec.negative_prompt), (prompt, negative))
        self.assertEqual((spec.steps, spec.guidance, spec.mode), (20, 7.5, "crop"))

    def test_edit_failures_walk_ladder_then_raise_guidance(self) -> None:
        self.script[:] = [EDIT_FAIL] * 4
        art = self.run_edit()
        loop = self.research.loop
        steps = loop.ladder("T2", "rice", "tuned")
        specs = self.editor.specs
        self.assertEqual([s.prompt for s in specs], [steps[0][0], steps[1][0], steps[2][0], steps[2][0]])
        self.assertEqual([s.guidance for s in specs], [7.5, 7.5, 7.5, 10.0])
        self.assertEqual([s.seed for s in specs], loop.POLICY["seeds"][:4])
        self.assertEqual(art["attempts"], 4)
        self.assertFalse(art["checker_passed"])

    def test_stops_at_first_pass_and_selects_it(self) -> None:
        self.script[:] = [EDIT_FAIL, _chk()]
        art = self.run_edit()
        self.assertEqual(art["attempts"], 2)
        self.assertTrue(art["checker_passed"])
        self.assertEqual(art["seed"], self.research.loop.POLICY["seeds"][1])
        self.assertIn(":ladder1:", art["prompt_id"])

    def test_realism_failure_reseeds_with_same_prompt(self) -> None:
        self.script[:] = [REALISM_FAIL, _chk()]
        self.run_edit()
        first, second = self.editor.specs
        self.assertEqual(first.prompt, second.prompt)
        self.assertNotEqual(first.seed, second.seed)

    def test_selection_is_best_score_not_last_attempt(self) -> None:
        self.script[:] = [_chk(edit=1.4), _chk(edit=0.1), _chk(edit=0.1), _chk(edit=0.1)]
        art = self.run_edit()
        self.assertEqual(art["attempts"], 4)
        self.assertEqual(art["seed"], self.research.loop.POLICY["seeds"][0])
        self.assertFalse(art["checker_passed"])

    def test_max_attempts_setting_bounds_generations(self) -> None:
        self.script[:] = [EDIT_FAIL] * 8
        with mock.patch.dict(os.environ, {"WORKER_MAX_ATTEMPTS": "2"}):
            art = self.run_edit()
        self.assertEqual(art["attempts"], 2)
        self.assertEqual(len(self.editor.specs), 2)

    def test_time_budget_stops_retries_and_returns_best_so_far(self) -> None:
        self.script[:] = [EDIT_FAIL] * 4
        self.editor.delay = 0.4
        run_dir = os.path.join(self.tmp.name, "runs")
        with mock.patch.dict(os.environ, {"WORKER_TIME_BUDGET_SECS": "0.6", "WORKER_RUN_DIR": run_dir}):
            art = self.run_edit()
        self.assertEqual(art["attempts"], 1)
        self.assertFalse(art["checker_passed"])
        (run,) = os.listdir(run_dir)
        with open(os.path.join(run_dir, run, "run.json")) as fh:
            record = json.load(fh)
        self.assertTrue(record["stopped_for_time"])
        self.assertIn("brushnet_sdxl_seg", record["models"]["brushnet"])

    def test_unsupported_requests_are_refused_before_any_generation(self) -> None:
        for dish, changes in (
            ("chicken_rice", ("brown_rice", "extra_vegetables")),
            ("chicken_rice", ("sauce_on_side",)),
            ("fish_soup", ("extra_vegetables",)),
        ):
            with self.assertRaises(gpu_worker.GpuRequestUnsupportedError):
                self.run_edit(dish, changes)
        self.assertEqual(self.editor.specs, [])

    def test_bad_fixtures_fail_closed(self) -> None:
        from PIL import Image

        mask = os.path.join(self.fixtures, "chicken_rice", "mask_rice.png")
        Image.new("L", (512, 512), 255).save(mask)
        with self.assertRaisesRegex(gpu_worker.GpuPipelineUnreadyError, "1024x1024"):
            self.run_edit()
        Image.new("L", (1024, 1024), 0).save(mask)
        with self.assertRaisesRegex(gpu_worker.GpuPipelineUnreadyError, "no editable pixels"):
            self.run_edit()
        os.remove(mask)
        with self.assertRaisesRegex(gpu_worker.GpuPipelineUnreadyError, "Missing dish fixture"):
            self.run_edit()
        self.assertFalse(gpu_worker.is_gpu_pipeline_ready())
        self.assertEqual(self.editor.specs, [])

    def test_checker_errors_fail_closed(self) -> None:
        self.script[:] = [{"error": "FloatingPointError: non-finite checker logits"}]
        with self.assertRaisesRegex(gpu_worker.GpuPipelineUnreadyError, "non-finite"):
            self.run_edit()
        with mock.patch.dict(os.environ, {"WORKER_CHECKER_URL": "http://127.0.0.1:9"}):
            with self.assertRaises(gpu_worker.GpuPipelineUnreadyError):
                self.run_edit()

    def test_run_dir_keeps_attempts_and_hashed_record(self) -> None:
        import hashlib

        run_dir = os.path.join(self.tmp.name, "runs")
        self.script[:] = [EDIT_FAIL, _chk()]
        with mock.patch.dict(os.environ, {"WORKER_RUN_DIR": run_dir}):
            self.run_edit()
        (run,) = os.listdir(run_dir)
        with open(os.path.join(run_dir, run, "run.json")) as fh:
            record = json.load(fh)
        with open(os.path.join(self.fixtures, "chicken_rice", "input.png"), "rb") as fh:
            self.assertEqual(record["input"]["sha256"], hashlib.sha256(fh.read()).hexdigest())
        self.assertEqual(record["task"], "T2")
        self.assertEqual(record["policy_version"], self.research.loop.POLICY["version"])
        self.assertEqual([a["tag"] for a in record["attempts"]], ["retry0", "retry1"])
        self.assertEqual(record["selected"], "retry1")
        job = os.path.join(run_dir, run, self.research.loop.job_key("chicken_rice", "T2"))
        self.assertEqual(sorted(os.listdir(job)), ["retry0.json", "retry0.png", "retry1.json", "retry1.png"])

    def test_http_statuses_for_builtin_path(self) -> None:
        class Handler(gpu_worker.WorkerHandler):
            expected_token = None
            mode = "gpu"

            def log_message(self, fmt: str, *args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        base = f"http://127.0.0.1:{server.server_address[1]}"

        def post(body: dict) -> tuple[int, dict]:
            req = urllib.request.Request(
                f"{base}/v1/generate", data=json.dumps(body).encode(), method="POST"
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    return resp.status, json.loads(resp.read())
            except urllib.error.HTTPError as err:
                with err:
                    return err.code, json.loads(err.read())

        with urllib.request.urlopen(f"{base}/healthz", timeout=3) as resp:
            self.assertTrue(json.loads(resp.read())["gpu_ready"])
        status, body = post({"dish_id": "chicken_rice", "change_ids": ["brown_rice"]})
        self.assertEqual((status, body["provider"]), (200, "tailscale-gpu-worker"))
        status, body = post({"dish_id": "chicken_rice", "change_ids": ["sauce_on_side"]})
        self.assertEqual((status, body["error"]), (422, "unsupported_by_validated_model"))
        with mock.patch.dict(os.environ, {"WORKER_CHECKER_URL": "http://127.0.0.1:9"}):
            status, body = post({"dish_id": "chicken_rice", "change_ids": ["brown_rice"]})
        self.assertEqual((status, body["error"]), (503, "gpu_pipeline_unready"))

    def test_fake_editor_matches_real_editor_signature(self) -> None:
        import inspect

        real = inspect.signature(self.research.editor.Editor.edit)
        self.assertEqual(list(real.parameters), ["self", "image", "mask", "spec"])
        self.assertEqual(list(inspect.signature(FakeEditor.edit).parameters), list(real.parameters))
        check = inspect.signature(self.research.loop.CheckerClient.check)
        self.assertEqual(
            list(check.parameters), ["self", "original_path", "edited_path", "task", "source", "crop_box"]
        )


if __name__ == "__main__":
    unittest.main()
