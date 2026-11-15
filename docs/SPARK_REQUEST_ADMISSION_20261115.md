# Spark photo-worker reliability update — 15 November 2026

Based on the live Spark checkout commit `d818a1e755ec657602f43f5cace722a2035f2c01`,
backed up in `sync/spark-photo-worker-20261115`. This patch preserves the uploaded-photo
route and the existing retention/validation behaviour; it is not a model-quality change.

## Behaviour

Both `/v1/generate` and `/v1/generate-photo` now share nonblocking request admission.
After authentication and bounded request parsing, an overlapping inference request gets
HTTP 429 `gpu_busy` rather than waiting for an earlier request to finish. The Rust gateway
maps it to the existing HTTP 503 `gpu_busy` application response. The guard releases on
success and failure, and stays held while the inference is actually running even if an
upstream caller times out. Health remains responsive. No automatic resubmission is added.

Malformed catalogue JSON values (including arrays or objects where strings are expected)
now return structured 400 responses. Timing logs contain elapsed seconds and route only,
not tokens or uploaded images.

## Verification

- 16 Python CPU/HTTP tests passed; 21 existing research-adapter tests were skipped because
  the Mac test environment does not have the full Torch/SciPy research dependencies.
- New HTTP tests exercise concurrent requests across both routes, authentication while
  busy, responsive health, admission release after failures and malformed values.
- All 27 Rust API integration tests passed, including catalogue and photo busy responses.
- Rust format, Clippy with warnings denied, and `git diff --check` passed.
- No Flutter files changed; no fresh mobile build or device test is claimed.

## Deployment status and remaining work

This branch is tested locally and is **not deployed**. Do not replace the Spark worker with
the old coursework extension. Deploy from this standalone app lineage in a maintenance
window, after rerunning the research-adapter tests in the existing Spark environment.
A running request must finish before any worker restart. Verify both routes and the Flutter
busy/retry UI with an actual uploaded photo after deployment.

The live `/healthz` reported `status=ok`, `gpu_ready=false`, `photo_ready=true` after the
separate 48-output pilot completed. `gpu_ready` is a catalogue-fixture completeness test;
the tofu fixture is missing. `photo_ready` is configuration readiness, not an end-to-end
inference guarantee. Do not hide either state or claim all catalogue dishes work.

For longer inference, a job API with job ID, status and result retrieval remains preferable.
The current HTTP timeout does not cancel the underlying inference. This guard bounds
accepted concurrent work, but does not make generation asynchronous or prove production
readiness. UI assets required by `scripts/check.sh` must also be supplied before a full build.
