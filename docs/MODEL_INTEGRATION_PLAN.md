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

The interface mismatch above is fixed in `gpu-worker/gpu_worker.py`: the built-in path now runs the retry arm through `sgedit.loop.Runner.candidate`, `base_spec`, `next_spec`, `CheckerClient.check` and `sgedit.editor.Editor.edit`, selects by checker score as `Runner.run` does, restricts requests to one of the two research tasks (step 1 and 5), and reports the real policy version, ladder step, seed and attempt count. `gpu-worker/test_gpu_worker.py` exercises this against the real `sgedit.loop` code with a fake editor and a fake checker service (step 2's model-free contract test). Setting `WORKER_RUN_DIR` keeps per-attempt outputs with input/mask hashes. Still open: the real GPU acceptance run (no weights or fixtures were available where this was written), checkpoint identity in the run record, steps 3–4 (the gateway's `GpuArtifact` schema is unchanged, so structured evidence is not yet in the API response) and steps 6–7. Texture/flavour are still ignored by the model path.

This document is a proposal grounded in current source, not an implementation or a new experimental result. No model, masks, private images, or study responses were changed or published in preparing it.
