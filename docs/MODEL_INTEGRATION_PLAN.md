# Connect the app to the research goal

## Goal and evidence boundary

The product goal is a requested visual meal modification that succeeds while leaving other food and the scene unchanged. The current app selects a meal, one or two changes, optional texture/flavour preferences, and then shows a request summary or GPU artifact. These preferences are not evidence that the requested modification occurred. A plausible image cannot establish nutrition, calories, sodium, allergens, chewing/swallowing safety, actual ingredients or clinical benefit.

## Verified integration gaps (2026-11-10)

Source inspection of `gpu-worker/gpu_worker.py` against this checkout's `sgedit/` found the built-in GPU path incompatible: it imports `BrushNetEditor` but the repository defines `Editor`; `CheckerClient` accepts `url`, not `base_url`, and exposes `check`, not `Check`; the calls to `ladder`, `base_spec` and `next_spec` use different signatures. The dry-run HTTP smoke test does not execute this path. The built-in path currently fails closed, not a demonstrated live model connection. A separately implemented WORKER_GPU_CMD may work but has not been verified here.

Texture/flavour values are passed into the worker interface but not used by the built-in editing loop. Sauce-on-side is not one of the two tasks in the research evaluation rubric. Multiple edits are sequential and need final-image preservation checks; passing each step alone would not establish that earlier changes survived. Worker configuration being present is not proof of model readiness.

## Concrete implementation sequence

1. Start with the two supported research requests only: add cooked broccoli while retaining the staple; replace white rice with brown rice. Keep sauce, softness and mildness out of the validated-model flow until methods and independent evaluation exist. They may remain explicitly labelled exploratory requests elsewhere.
2. Use the exact research `Runner`/`Editor`/checker contracts through a tested adapter. Lock model checkpoint identity, source-photo and mask hashes, prompt/policy version, seed, attempts and per-attempt outputs. A model-free contract test should exercise this adapter with test doubles; a real GPU acceptance test is a separate required gate.
3. Make the app flow: original meal photo → explicit requested edit → mask/region confirmation → generated candidate beside the exact original. Explain that the rest of the meal should stay unchanged. Do not substitute the current decorative reference photo for the actual model input.
4. Carry structured evidence in the API response: actual task, source/mask identifiers, selected candidate, model/policy identifiers, retry count and selector diagnostics. Distinguish unavailable, rejected, unverified and produced states. Do not label a selector pass as independently verified success.
5. For multiple edits, check the final candidate against the original for unintended outside-region changes and verify every requested target remains. Until this is implemented and evaluated, restrict validated-model requests to one edit.
6. Reuse the research rubric for independent annotation: requested edit 0–2, preservation 0–2, realism 1–5, unrequested additions yes/no; pairwise preference asks which better fulfils the edit while preserving the meal. Evaluate fixed methods on the same locked examples, blind identities/order and report failure cases and retry cost. Reviewer familiarity/usability questions are secondary and must not replace these method outcomes.
7. Only after a real model test, truthful provenance display, final-image checks and outage tests should hosting advertise the GPU capability as ready. Keep public health claims and any participant research behind their separate evidence/approval requirements.

## Adapter repair (2026-11-10, later the same day)

The interface mismatch above is fixed in `gpu-worker/gpu_worker.py`: the built-in path now runs the retry arm through `sgedit.loop.Runner.candidate`, `base_spec`, `next_spec`, `CheckerClient.check` and `sgedit.editor.Editor.edit`, selects by checker score as `Runner.run` does, restricts requests to one of the two research tasks (step 1 and 5), and reports the real policy version, ladder step, seed and attempt count. `gpu-worker/test_gpu_worker.py` exercises this against the real `sgedit.loop` code with a fake editor and a fake checker service (step 2's model-free contract test). Setting `WORKER_RUN_DIR` keeps per-attempt outputs with input/mask hashes. The run record also names the checkpoint paths, and `WORKER_TIME_BUDGET_SECS` (20 s default) stops retries before the gateway (25 s) and app (28 s) timeouts, returning the best candidate so far; using the full attempt budget needs all three raised together. Still open: the real GPU acceptance run (no weights or fixtures were available where this was written), steps 3–4 (the gateway's `GpuArtifact` schema is unchanged, so structured evidence is not yet in the API response) and steps 6–7. Texture/flavour are still ignored by the model path.

## Spark02 real-model runs (2026-11-10 and 2026-11-11)

These are private development runs, not study results, human validation or a deployment. The live loopback services (API 8787, worker 8791) were not changed and still run the worker in `dry-run` mode.

**Runtime.** Everything lives outside Git in `/home/lily/senior-meal-spark-runtime` (mode 700); its `manifest/` folder holds the installed-package lists, model hashes and run records.

- Host: aarch64, NVIDIA GB10, CUDA 13. The research pins (`torch 2.6.0+cu124`, `bitsandbytes 0.45.5`) have no build for this platform.
- Editor environment: `torch 2.14.1+cu130`, `transformers 4.38.2`, BrushNet's vendored `diffusers` from `TencentARC/BrushNet` at `0f9d9e54ca85c40a11a8f0504b4b5b2e7e8fd14d`.
- Checker environment: `torch 2.14.1+cu130`, `transformers 4.57.6`, started with `--no-quant4` because `bitsandbytes` is unavailable. This is not the validated 4-bit checker.
- Weights: SDXL base 1.0 at revision `462165984030d82259a11f4367a4eed129e94a7b`; `Qwen/Qwen2.5-VL-7B-Instruct` at `cc594898137f460bfe9f0759e9844b3ce807cfb5`; BrushNet `brushnet_sdxl_seg` copied from the V100 host with matching SHA-256.
- Launch: `SGEDIT_BASELINE` points at the runtime's `baseline/`, `WORKER_SGEDIT_ROOT` at the coursework checkout (read only), `HF_HUB_OFFLINE=1`, and `CPATH` at locally extracted Python headers.

**Loopback HTTP run (10 Nov, commit `798cc51`).** Checker, warmed worker and API were started on temporary loopback ports and stopped afterwards.

| Request | Result |
|---|---|
| `chicken_rice` + `brown_rice` | 200 in 13.9 s, one attempt, `checker_passed: true` |
| `tofu_rice` + `brown_rice` | 503 `gpu_not_ready` (no tofu fixture exists) |
| `chicken_rice` + two changes | 422 `gpu_unsupported_request` |

The chicken rice image was rejected on visual review: the rice looked like large raw seed kernels. The checker passed it.

**Prompt comparison (11 Nov).** The research policy prompt (20 steps, guidance 7.5) and one development prompt (30 steps, guidance 5.0, with a negative prompt against raw or oversized grains) were each run on the 15 dev-split rice photos with two seeds: 60 outputs. No test-split photo was used.

| Setting | Checker pass | Agent's visual review |
|---|---|---|
| Research policy | 29/30 | Consistent brown colour, but grains often oversized and unrequested toppings appear; on one photo a decorated bowl replaced the rice |
| Development prompt | 16/30 | Finer grains, but colour drifts to pink or grey and unrequested items still appear |

The development prompt was not adopted, so the worker still uses the research policy unchanged. Neither setting gives output on this runtime that should be shown to users without a person selecting it, and a checker pass did not predict acceptable appearance. Whether the validated V100 runtime produces the same artefacts for the same seeds has not been compared.

**Still open.**

- No tofu-with-rice photo and mask exist, so `tofu_rice` stays unavailable.
- The chicken rice fixture is a dev-split FoodSG photo, approved by the project owner on 11 November 2026 for internal use only. Its redistribution status is unverified, so it must not be committed or published.
- No human has reviewed any output.
- Steps 3–4 and 6–7 above are unchanged: `gpu_preview` should not be advertised as ready.

This document is a proposal grounded in current source, not an implementation or a new experimental result. No model, masks, private images, or study responses were changed or published in preparing it.
