#!/usr/bin/env python3
"""Private Tailscale GPU model-worker bridge for Senior Meal Preview.

This service runs on the GPU machine joined to the same Tailscale tailnet as the
EC2 Rust API server. It binds strictly to a Tailscale CGNAT IPv4 address
(100.64.0.0/10), Tailscale IPv6 (fd7a:115c:a1e0::/48), or loopback (127.0.0.1),
never 0.0.0.0 or a public interface.

Modes:
- `dry-run`: Returns a deterministic, dependency-free PNG fixture labelled
  `provider="tailscale-gpu-dry-run"` and `model="dry_run_fixture"` for Tailscale
  connectivity and smoke tests.
- `gpu`: Invokes either an external GPU runner (`WORKER_GPU_CMD`) or the repo's
  `sgedit` BrushNet + Qwen2.5-VL check-and-retry pipeline against dish fixtures
  in `WORKER_FIXTURE_DIR`. Fails closed with HTTP 503 if GPU fixtures or weights
  are unavailable (never silently falls back to a synthetic dry-run image).

The built-in `sgedit` path uses the research code's own contracts
(`sgedit.editor.Editor`, `sgedit.loop.Runner.candidate`, `base_spec`,
`next_spec`, `CheckerClient`, `POLICY`) and only the two research tasks, one
edit per request:
  brown_rice        -> T2    (replace white rice with brown rice)
  extra_vegetables  -> T1-B  (add cooked broccoli, staple stays visible)
for dishes with a rice fixture (`<dish>/input.png` + `<dish>/mask_rice.png`,
both 1024x1024). Anything else returns HTTP 422 `unsupported_by_validated_model`.
`checker_passed` is the selector's verdict on the selected candidate; it is not
an independent evaluation.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import io
import ipaddress
import json
import os
import shlex
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace

ALLOWED_DISHES = {"chicken_rice", "fish_soup", "tofu_rice"}
ALLOWED_CHANGES = {"extra_vegetables", "brown_rice", "sauce_on_side"}
ALLOWED_TEXTURES = {"any", "soft"}
ALLOWED_FLAVOURS = {"any", "mild"}

# Built-in sgedit path: research task per change, and the staple ("source") each dish fixture carries.
BUILTIN_TASKS = {"brown_rice": "T2", "extra_vegetables": "T1-B"}
BUILTIN_SOURCES = {"chicken_rice": "rice", "tofu_rice": "rice"}
FIXTURE_SIDE = 1024
PROMPT_SET = "tuned"
DEFAULT_CHECKER_URL = "http://127.0.0.1:8781"
# The Rust gateway rejects worker responses over 4 MiB; keep the preview well inside that.
MAX_IMAGE_DATA_URL_BYTES = 3 * 1024 * 1024

DISH_RGB = {
    "chicken_rice": (202, 129, 74),
    "fish_soup": (141, 188, 195),
    "tofu_rice": (167, 186, 133),
}

GENERATED_DISCLOSURE = (
    "AI-generated preview via private Tailscale GPU worker · "
    "Not a real meal or clinical verification"
)


class GpuPipelineUnreadyError(RuntimeError):
    """Raised when `--mode gpu` is active but GPU fixtures or weights are unavailable."""


class GpuRequestUnsupportedError(RuntimeError):
    """Raised when the built-in sgedit path has no validated task for the request."""


_GPU_LOCK = threading.Lock()  # one generation at a time on the single editor
_EDITOR = None


def sgedit_root() -> Path | None:
    """Directory containing the `sgedit` package: WORKER_SGEDIT_ROOT, else this repository's root."""
    configured = os.environ.get("WORKER_SGEDIT_ROOT", "").strip()
    if configured:
        return Path(configured)
    parents = Path(__file__).resolve().parents
    if len(parents) > 3 and (parents[3] / "sgedit").is_dir():
        return parents[3]
    return None


def load_research() -> SimpleNamespace:
    """Import the research modules (needs numpy/torch/scipy/PIL and SGEDIT_BASELINE prompts)."""
    root = sgedit_root()
    if root is None or not (root / "sgedit").is_dir():
        raise GpuPipelineUnreadyError(
            "Cannot locate the sgedit package; set WORKER_SGEDIT_ROOT to the research checkout."
        )
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    try:
        import numpy as np
        from PIL import Image
        from sgedit import editor, loop
    except Exception as exc:
        raise GpuPipelineUnreadyError(
            f"Cannot import sgedit GPU pipeline dependencies: {type(exc).__name__}: {exc}"
        ) from exc
    return SimpleNamespace(np=np, Image=Image, editor=editor, loop=loop, root=root)


def get_editor(research: SimpleNamespace):
    """Load BrushNet-SDXL once per process (slow); call with _GPU_LOCK held or at startup."""
    global _EDITOR
    if _EDITOR is None:
        _EDITOR = research.editor.Editor()
    return _EDITOR


def builtin_fixture_paths(base: Path, dish_id: str) -> tuple[Path, Path]:
    source = BUILTIN_SOURCES[dish_id]
    return base / dish_id / "input.png", base / dish_id / f"mask_{source}.png"


def _model_identity() -> dict[str, str]:
    """Checkpoint locations the editor loads (the SDXL path ends in its snapshot revision)."""
    try:
        from sgedit import paths

        return {"brushnet": str(paths.BRUSHNET_CKPT), "sdxl": str(paths.SDXL)}
    except Exception:
        return {}


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_allowed_bind_ip(addr: str) -> bool:
    if addr == "localhost":
        return True
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return False
    tailscale_v4 = ipaddress.ip_network("100.64.0.0/10")
    tailscale_v6 = ipaddress.ip_network("fd7a:115c:a1e0::/48")
    return ip.is_loopback or ip in tailscale_v4 or ip in tailscale_v6


def detect_tailscale_ipv4() -> str:
    result = subprocess.run(
        ["tailscale", "ip", "-4"],
        capture_output=True,
        text=True,
        check=True,
        timeout=5,
    )
    for line in result.stdout.splitlines():
        candidate = line.strip()
        if candidate and is_allowed_bind_ip(candidate):
            return candidate
    raise RuntimeError("No valid Tailscale IPv4 address returned by 'tailscale ip -4'.")


def make_solid_png_data_url(rgb: tuple[int, int, int], width: int = 96, height: int = 64) -> str:
    """Create a small, dependency-free PNG data URL for dry-run connectivity checks."""
    r, g, b = rgb
    raw_rows = b"".join(b"\x00" + bytes((r, g, b)) * width for _ in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw_rows, level=6))
        + chunk(b"IEND", b"")
    )
    return "data:image/png;base64," + base64.b64encode(png).decode("ascii")


def is_gpu_pipeline_ready() -> bool:
    """Return True if WORKER_GPU_CMD is set or every built-in dish fixture is present.

    This is a configuration check only; it does not prove the models load or run.
    """
    gpu_cmd = os.environ.get("WORKER_GPU_CMD", "").strip()
    if gpu_cmd:
        return True
    fixture_dir = os.environ.get("WORKER_FIXTURE_DIR", "").strip()
    if not fixture_dir:
        return False
    base = Path(fixture_dir)
    return base.is_dir() and all(
        path.is_file() for dish in BUILTIN_SOURCES for path in builtin_fixture_paths(base, dish)
    )


def build_dry_run_artifact(
    dish_id: str,
    change_ids: list[str],
    prompt_id: str,
    seed: int,
) -> dict[str, object]:
    base_r, base_g, base_b = DISH_RGB[dish_id]
    if "extra_vegetables" in change_ids:
        base_g = min(255, base_g + 35)
    if "brown_rice" in change_ids:
        base_r = max(80, base_r - 25)
    return {
        "provider": "tailscale-gpu-dry-run",
        "model": "dry_run_fixture",
        "prompt_id": f"dry_run:{prompt_id}",
        "seed": seed,
        "attempts": 1,
        "checker_passed": False,  # no checker runs in dry-run; never claim a pass
        "image_data_url": make_solid_png_data_url((base_r, base_g, base_b)),
        "generated_label": GENERATED_DISCLOSURE,
    }


def run_gpu_pipeline(
    dish_id: str,
    change_ids: list[str],
    texture: str,
    flavour: str,
    prompt_id: str,
    seed: int,
) -> dict[str, object]:
    """Execute the real GPU pipeline or fail closed with GpuPipelineUnreadyError."""
    gpu_cmd = os.environ.get("WORKER_GPU_CMD", "").strip()
    if gpu_cmd:
        req_payload = {
            "dish_id": dish_id,
            "change_ids": change_ids,
            "texture": texture,
            "flavour": flavour,
            "prompt_id": prompt_id,
            "seed": seed,
        }
        try:
            proc = subprocess.run(
                shlex.split(gpu_cmd),
                input=json.dumps(req_payload),
                capture_output=True,
                text=True,
                shell=False,
                check=True,
                timeout=int(os.environ.get("WORKER_GPU_TIMEOUT_SECS", "20")),
            )
            result = json.loads(proc.stdout)
        except Exception as exc:
            raise GpuPipelineUnreadyError(f"External WORKER_GPU_CMD failed: {exc}") from exc

        image_data_url = str(result.get("image_data_url", ""))
        if not image_data_url.startswith("data:image/png;base64,"):
            raise GpuPipelineUnreadyError(
                "WORKER_GPU_CMD did not return a valid 'data:image/png;base64,...' image_data_url."
            )
        return {
            "provider": str(result.get("provider", "tailscale-gpu-worker")),
            "model": str(result.get("model", "brushnet-sdxl+qwen2.5-vl-7b-4bit")),
            "prompt_id": str(result.get("prompt_id", prompt_id)),
            "seed": int(result.get("seed", seed)),
            "attempts": max(1, min(8, int(result.get("attempts", 1)))),
            "checker_passed": bool(result.get("checker_passed", False)),
            "image_data_url": image_data_url,
            "generated_label": str(result.get("generated_label", GENERATED_DISCLOSURE)),
        }

    return run_builtin_pipeline(dish_id, change_ids)


def run_builtin_pipeline(dish_id: str, change_ids: list[str]) -> dict[str, object]:
    """Check-and-retry with the research contracts; returns the selected candidate.

    Mirrors the retry arm of `sgedit.loop.Runner.run` (generate, check, stop at the
    first pass, otherwise `next_spec`, at most K generations, select by score) without
    generating the K same-settings seed candidates that only the comparison arms need.
    """
    if len(change_ids) != 1 or change_ids[0] not in BUILTIN_TASKS or dish_id not in BUILTIN_SOURCES:
        raise GpuRequestUnsupportedError(
            "The validated-model path supports exactly one of "
            f"{sorted(BUILTIN_TASKS)} on {sorted(BUILTIN_SOURCES)}."
        )
    task, source = BUILTIN_TASKS[change_ids[0]], BUILTIN_SOURCES[dish_id]

    fixture_dir = os.environ.get("WORKER_FIXTURE_DIR", "").strip()
    if not fixture_dir:
        raise GpuPipelineUnreadyError(
            "GPU mode requires WORKER_FIXTURE_DIR (pointing to dish input/mask PNGs) or WORKER_GPU_CMD. "
            "Refusing to return a synthetic dry-run fixture while in '--mode gpu'."
        )
    input_path, mask_path = builtin_fixture_paths(Path(fixture_dir), dish_id)
    for path in (input_path, mask_path):
        if not path.is_file():
            raise GpuPipelineUnreadyError(f"Missing dish fixture: {path}")

    research = load_research()
    np, Image, loop = research.np, research.Image, research.loop
    try:
        max_attempts = max(1, min(8, int(os.environ.get("WORKER_MAX_ATTEMPTS", "4"))))
        max_side = max(64, min(FIXTURE_SIDE, int(os.environ.get("WORKER_OUTPUT_MAX_SIDE", "768"))))
        # Seconds allowed for generate+check attempts (0 = no limit). Must stay under the gateway's
        # MODEL_WORKER_TIMEOUT_MS, or the gateway gives up while the worker is still retrying.
        time_budget = max(0.0, float(os.environ.get("WORKER_TIME_BUDGET_SECS", "20")))
    except ValueError as exc:
        raise GpuPipelineUnreadyError(f"Invalid worker numeric setting: {exc}") from exc
    checker_url = os.environ.get("WORKER_CHECKER_URL", "").strip() or DEFAULT_CHECKER_URL
    run_root = os.environ.get("WORKER_RUN_DIR", "").strip()

    try:
        image = Image.open(input_path).convert("RGB")
        mask = np.asarray(Image.open(mask_path).convert("L")) > 127
        expected = (FIXTURE_SIDE, FIXTURE_SIDE)
        if image.size != expected or mask.shape != expected:
            raise GpuPipelineUnreadyError(
                f"Fixtures must be {FIXTURE_SIDE}x{FIXTURE_SIDE}: {input_path.name} is {image.size}, "
                f"{mask_path.name} is {mask.shape[::-1]}."
            )
        if not mask.any():
            raise GpuPipelineUnreadyError(f"Mask has no editable pixels: {mask_path}")

        with _GPU_LOCK, tempfile.TemporaryDirectory(prefix="meal-worker-") as tmp:
            if run_root:  # keep every attempt and a run record; otherwise nothing is retained
                out_dir = Path(run_root) / f"{time.strftime('%Y%m%dT%H%M%S')}-{os.urandom(3).hex()}"
                out_dir.mkdir(parents=True)
            else:
                out_dir = Path(tmp)
            editor = get_editor(research)  # model load (if not warmed) is outside the time budget
            runner = loop.Runner(editor, loop.CheckerClient(url=checker_url), out_dir, prompt_set=PROMPT_SET)
            job = {
                "key": loop.job_key(dish_id, task),
                "image": image,
                "mask": mask,
                "original_path": str(input_path.resolve()),
                "task": task,
                "source": source,
            }
            seeds = loop.POLICY["seeds"]
            spec = loop.base_spec(task, source, seeds[0], PROMPT_SET)
            started = time.monotonic()
            specs, tried = [spec], [runner.candidate(job, spec, "retry0")]
            durations = [time.monotonic() - started]
            out_of_time = False
            while not tried[-1]["pass"] and len(tried) < max_attempts:
                elapsed = time.monotonic() - started
                if time_budget and elapsed + max(durations) > time_budget:
                    out_of_time = True  # another attempt would not fit; return the best so far
                    break
                spec = loop.next_spec(
                    spec, task, source, tried[-1]["failure"], len(tried), seeds, PROMPT_SET
                )
                specs.append(spec)
                tried.append(runner.candidate(job, spec, f"retry{len(tried)}"))
                durations.append(time.monotonic() - started - elapsed)

            # Same rule as sgedit.results.summarize_result: best score, first wins ties.
            pick = max(range(len(tried)), key=lambda i: tried[i]["score"])
            selected, sel_spec = tried[pick], specs[pick]
            steps = loop.ladder(task, source, PROMPT_SET)
            rung = next(
                (i for i, (p, n) in enumerate(steps) if (p, n) == (sel_spec.prompt, sel_spec.negative_prompt)),
                0,
            )
            policy_version = loop.POLICY["version"]
            prompt_id = f"sgedit-{policy_version}:{PROMPT_SET}:{task}/{source}:ladder{rung}:g{sel_spec.guidance:g}"
            checker_model = str(selected["check"].get("model", "qwen2.5-vl checker"))

            if run_root:
                record = {
                    "dish_id": dish_id,
                    "change_id": change_ids[0],
                    "task": task,
                    "source": source,
                    "input": {"path": str(input_path), "sha256": _sha256_file(input_path)},
                    "mask": {"path": str(mask_path), "sha256": _sha256_file(mask_path)},
                    "sgedit_root": str(research.root),
                    "policy_version": policy_version,
                    "prompt_set": PROMPT_SET,
                    "max_attempts": max_attempts,
                    "time_budget_secs": time_budget,
                    "stopped_for_time": out_of_time,
                    "attempt_seconds": [round(d, 2) for d in durations],
                    "models": _model_identity(),
                    "checker_url": checker_url,
                    "checker_model": checker_model,
                    "attempts": [
                        {
                            "tag": c["tag"],
                            "seed": sp.seed,
                            "guidance": sp.guidance,
                            "prompt": sp.prompt,
                            "negative_prompt": sp.negative_prompt,
                            "sha256": c["sha256"],
                            "score": c["score"],
                            "pass": c["pass"],
                            "failure": c["failure"],
                        }
                        for c, sp in zip(tried, specs)
                    ],
                    "selected": selected["tag"],
                    "selected_passed_checker": bool(selected["pass"]),
                    "note": "Checker verdicts select candidates; they are not an evaluation result.",
                }
                (out_dir / "run.json").write_text(json.dumps(record, indent=1))

            preview = Image.open(selected["path"]).convert("RGB")
            if max(preview.size) > max_side:
                preview.thumbnail((max_side, max_side), Image.LANCZOS)
            buf = io.BytesIO()
            preview.save(buf, format="PNG", optimize=True)

        image_data_url = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")
        if len(image_data_url) > MAX_IMAGE_DATA_URL_BYTES:
            raise GpuPipelineUnreadyError(
                "Preview PNG exceeds the gateway response limit; lower WORKER_OUTPUT_MAX_SIDE."
            )
        sys.stderr.write(
            f"[gpu-worker] {dish_id}/{task}: attempts={len(tried)} selected={selected['tag']} "
            f"checker_passed={bool(selected['pass'])} stopped_for_time={out_of_time}\n"
        )
        return {
            "provider": "tailscale-gpu-worker",
            "model": f"brushnet-sdxl+{checker_model}",
            "prompt_id": prompt_id,
            "seed": int(sel_spec.seed),
            "attempts": len(tried),
            "checker_passed": bool(selected["pass"]),
            "image_data_url": image_data_url,
            "generated_label": GENERATED_DISCLOSURE,
        }
    except GpuPipelineUnreadyError:
        raise
    except Exception as exc:
        raise GpuPipelineUnreadyError(
            f"sgedit GPU execution failed: {type(exc).__name__}: {exc}"
        ) from exc


class WorkerHandler(BaseHTTPRequestHandler):
    expected_token: str | None = None
    mode: str = "dry-run"

    def log_message(self, fmt: str, *args: object) -> None:
        # Redact request bodies and tokens; log only status and path.
        sys.stderr.write(f"[gpu-worker] {self.command} {self.path} -> {fmt % args}\n")

    def _send_json(self, status: HTTPStatus, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_auth(self) -> bool:
        if not self.expected_token:
            return True
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        provided = header[len("Bearer ") :].strip()
        return hmac.compare_digest(
            provided.encode("utf-8"), self.expected_token.encode("utf-8")
        )

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "worker_mode": self.mode,
                    "gpu_ready": True if self.mode == "dry-run" else is_gpu_pipeline_ready(),
                },
            )
            return
        self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/generate":
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        if not self._check_auth():
            self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_length"})
            return
        if length <= 0 or length > 16 * 1024:
            self._send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "body_size"})
            return

        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            self._send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": "invalid_json"})
            return

        dish_id = data.get("dish_id")
        change_ids = data.get("change_ids")
        texture = data.get("texture", "any")
        flavour = data.get("flavour", "any")
        if (
            dish_id not in ALLOWED_DISHES
            or not isinstance(change_ids, list)
            or not (1 <= len(change_ids) <= 2)
            or any(cid not in ALLOWED_CHANGES for cid in change_ids)
            or texture not in ALLOWED_TEXTURES
            or flavour not in ALLOWED_FLAVOURS
        ):
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_selection"})
            return

        # Request label only. No prompt is involved in dry-run; the built-in sgedit path replaces it
        # with the real policy version and prompt-ladder step.
        prompt_id = f"request:{dish_id}:{'+'.join(sorted(change_ids))}"
        seed_bytes = hashlib.sha256(f"{dish_id}:{','.join(change_ids)}".encode()).digest()[:4]
        seed = int.from_bytes(seed_bytes, "big")

        if self.mode == "dry-run":
            artifact = build_dry_run_artifact(dish_id, change_ids, prompt_id, seed)
            self._send_json(HTTPStatus.OK, artifact)
            return

        try:
            artifact = run_gpu_pipeline(
                dish_id=dish_id,
                change_ids=change_ids,
                texture=texture,
                flavour=flavour,
                prompt_id=prompt_id,
                seed=seed,
            )
        except GpuRequestUnsupportedError as exc:
            self._send_json(
                HTTPStatus.UNPROCESSABLE_ENTITY,
                {"error": "unsupported_by_validated_model", "message": str(exc)},
            )
            return
        except GpuPipelineUnreadyError as exc:
            self._send_json(
                HTTPStatus.SERVICE_UNAVAILABLE,
                {"error": "gpu_pipeline_unready", "message": str(exc)},
            )
            return

        self._send_json(HTTPStatus.OK, artifact)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bind",
        default=os.environ.get("WORKER_BIND_ADDR", ""),
        help="Tailscale IP (100.64.0.0/10) or 127.0.0.1. Auto-detects via 'tailscale ip -4' if omitted.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("WORKER_PORT", "8790")),
        help="TCP port (default: 8790).",
    )
    parser.add_argument(
        "--mode",
        choices=("dry-run", "gpu"),
        default=os.environ.get("WORKER_MODE", "dry-run"),
        help="Execution mode (default: dry-run).",
    )
    parser.add_argument(
        "--warm",
        action="store_true",
        default=os.environ.get("WORKER_WARM", "").strip().lower() in ("1", "true", "yes"),
        help="In gpu mode, load the sgedit editor before listening (exits if it cannot load).",
    )
    args = parser.parse_args()

    bind_addr = args.bind.strip() or detect_tailscale_ipv4()
    if not is_allowed_bind_ip(bind_addr):
        raise SystemExit(
            f"Refusing to bind GPU worker to non-Tailscale/non-loopback address '{bind_addr}'."
        )
    token = os.environ.get("MODEL_WORKER_TOKEN", "").strip() or None
    if not token and bind_addr not in ("127.0.0.1", "::1", "localhost"):
        raise SystemExit(
            "MODEL_WORKER_TOKEN is required when binding the GPU worker to a Tailscale interface."
        )

    if args.warm and args.mode == "gpu" and not os.environ.get("WORKER_GPU_CMD", "").strip():
        try:
            get_editor(load_research())
        except Exception as exc:
            raise SystemExit(f"--warm could not load the sgedit editor: {type(exc).__name__}: {exc}")
        print("sgedit editor loaded", flush=True)

    WorkerHandler.expected_token = token
    WorkerHandler.mode = args.mode
    server = ThreadingHTTPServer((bind_addr, args.port), WorkerHandler)
    print(
        f"Tailscale GPU worker listening on http://{bind_addr}:{args.port} (mode={args.mode})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
