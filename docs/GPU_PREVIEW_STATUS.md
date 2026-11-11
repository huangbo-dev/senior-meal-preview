# GPU preview status and next steps (11 November 2026)

The real GPU preview runs end to end on Spark02, but its images are not good enough to show users. Plumbing is not the blocker; image quality is. Details of the runs are in [MODEL_INTEGRATION_PLAN.md](MODEL_INTEGRATION_PLAN.md), "Spark02 real-model runs".

Everything here is a private development result on dev-split photos. None of it is a study result or human validation, and it supports no nutrition or health claim.

## Where things stand

- **Live services:** the API on `127.0.0.1:8787` and worker on `127.0.0.1:8791` are unchanged. The worker is in `dry-run` mode, yet the catalog reports `gpu_preview: true` and returns a placeholder.
- **Real-model path:** a loopback request for chicken rice with brown rice returned in 13.9 s with `checker_passed: true`. The rice looked like large raw seed kernels.
- **Prompt comparison:** 15 dev-split rice photos, two seeds, two settings (60 outputs).

  | Setting | Checker pass | Visual review (agent only) |
  |---|---|---|
  | Research policy prompt | 29/30 | Brown, but grains often oversized; unrequested toppings; one rice mound replaced by a bowl |
  | Development prompt | 16/30 | Finer grains, but pink or grey rice; unrequested items remain |

  The development prompt was rejected. The worker still uses the research policy unchanged.
- **Checker:** it passed many outputs that look wrong, so `checker_passed` is a selector diagnostic and cannot serve as the quality gate.
- **Local fit:** the project owner judged that the outputs do not look like brown rice as served in Singapore.
- **Fixture:** the chicken rice photo is a dev-split FoodSG image, approved by the owner on 11 November 2026 for internal use only. It stays outside Git and unpublished. No tofu-with-rice fixture exists.
- **Runtime:** Spark02 differs from the validated host (torch 2.14.1+cu130 instead of 2.6.0+cu124; checker unquantised instead of 4-bit). Whether the validated V100 host produces the same artefacts has not been compared.

## Human review page

A blinded review page exists outside Git in `/home/lily/senior-meal-spark-runtime/work/review-20261111` (`build.py`, `serve.py`).

- It serves 20 pairs on `127.0.0.1:8794`: the five dev-split chicken rice photos, four outputs each, in shuffled order with neutral names.
- It asks the three questions of the approved human portal (requested change achieved, other food preserved, looks plausible), each Yes / No / Unsure, plus an optional note.
- Answers append to `responses.csv` in that folder. The key mapping pairs to prompt and seed is a separate file the page does not serve.
- Reach it from another machine with `ssh -L 8794:127.0.0.1:8794 <user>@<spark02>`.
- No answers have been recorded yet. Decide the acceptance bar (for example, Yes on all three) before reviewing.

## Ways to get closer to Singapore brown rice

Prompt wording alone is unlikely to work: the model's idea of brown rice is a Western whole grain, and BrushNet blanks the rice region before generating, so the original grain size and shape are lost.

1. **Tint instead of generate.** The research code has a colour-transfer baseline (`sgedit/tint_baseline.py`) that keeps the real grains and changes only colour. Cheapest to try; its target colour was measured from generated outputs and may need re-measuring from real photos.
2. **Keep the grains, regenerate lightly.** Low-strength image-to-image inside the mask. App-only method, not built.
3. **Condition on real examples.** An image-prompt adapter or a small fine-tune. Most work; compatibility with BrushNet's vendored `diffusers` is unknown.

Reference photos of cooked brown rice as served in Singapore, taken by or licensed to the owner, are needed: 5 to 10 as the reviewer's reference and for the tint target, 20 to 30 for route 3.

## Effect on the coursework report

This app is separate from the CE7454 coursework and these runs should not appear there as results. One point is worth checking against the report: if it relies on checker pass rates as evidence that edits succeeded, the behaviour seen here is a caution. It is not established for the validated setup, because no comparison on the V100 host has been made. Human ratings from the approved portal remain the appropriate primary evidence. Method changes such as tint or reference conditioning belong in the app or in future work, not in the frozen study.

## Open tasks

1. **Runtime or method?** Run the research policy prompt with seeds 1107 and 2207 on the same dev-split chicken rice photos on the V100 host and compare with the Spark02 outputs.
2. **Human review.** Complete the 20-pair review; optionally add tint-baseline outputs as a third blinded option first.
3. **Reference photos.** Owner to supply Singapore brown rice photos.
4. **Tofu rice.** Owner to supply a photo and mask, or the worker and catalog stop offering `tofu_rice` for GPU preview.
5. **Catalog flag.** Decide whether to stop advertising `gpu_preview` while the worker is dry-run. Changing it restarts a live service.
6. **Branch.** `docs/spark02-runtime-20261111` is local only; decide whether to merge or push.

Rules that apply to all of these: dev-split photos only; FoodSG photos never committed, published or sent to external services; the coursework checkout is read only; other listeners on the host are left alone.
