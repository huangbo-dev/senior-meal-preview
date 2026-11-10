# Senior Meal Preview repository guidance

- This is a non-submission app, separate from the CE7454 coursework repository. Never modify the coursework checkout from here and never merge this app into its `main`. The GPU worker only reads `sgedit` via `WORKER_SGEDIT_ROOT`.
- Branches: `main` (integration) and `production` (deployed, fast-forward from `main` only after `./deploy/predeploy-check.sh` passes). Do not push, deploy, make public, or tag releases without the user's direction.
- Keep meal photographs, fixtures, generated images, model weights, run records, API keys and environments out of Git.
- Truthful provenance: never substitute a mock image for a model output; dry-run artifacts must say so and must not claim a checker pass. The checker selects candidates; it does not evaluate them. A plausible image is not evidence of nutrition, ingredients, allergens or clinical benefit.
- Do not change `sgedit` prompts, thresholds or retry policy from this repository; those are chosen on validation photos in the coursework repository.
- No ratings, surveys or feedback from people outside the project team (NTU ERC/IRB approval would be needed first).
