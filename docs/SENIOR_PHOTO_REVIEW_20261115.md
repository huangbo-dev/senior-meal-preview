# Senior photo review flow candidate — 15 November 2026

Base: c5affb5de6bf5c18b951c05e2888ac68fe235535 (fix/spark-photo-request-admission).
Scope: app usability and truthful disclosure, not a new generation model.
No live restart, deployment, frozen study or rating changes.

## Implemented
- Require explicit square-crop confirmation before uploading; retain clear route to choose a wider photo if food is cut off.
- Keep the same photo and painted mask for adjustment and an explicit retry after a result; guard stale double submissions.
- Show a failed automatic check as an Unverified preview before images, with accessible live-region status and a correction action.
- Toggle Before/After at the same display size instead of stacking full-size images.
- Name the current own-photo brown-rice method as a colour preview, not new grains.
- Explain that catalogue defaults to an unchanged-photo request summary. Built-in AI accepts only one brown-rice or vegetable request; unsupported sauce/combinations are blocked locally with a summary-only alternative.
- Clarify soft/mild preferences are request-only, not applied by the built-in model.
- Replace unconditional deletion claims in both client and API with normal-processing temporary-file cleanup and crash limitation; visible identifying content is not removed by metadata stripping.
- Avoid a one-minute upper-bound promise; progress is explicitly estimated.

## Verified on ANGEL-WS011
- Flutter format and analyze --fatal-infos: passed.
- Full Flutter suite: 51 passed; includes same-photo/mask preservation, duplicate submit, failed-check warning before comparison, crop gate and unsupported AI combination fallback.
- Release web build: passed. Existing missing CupertinoIcons font warning remains.
- Rust fmt: passed after formatting the updated assertion.
- Rust integration suite: 27 passed; clippy -D warnings: passed.
- No GPU inference run or generation defaults changed.

## Remaining limitations / release gates
- Not deployed; original live app and older local candidates untouched.
- Native camera/permissions, physical-device flows, live Spark requests, and visual browser QA of this new build have not been performed.
- Mask drawing still requires pointer/touch motor control; not fully accessible without a suitable helper. No validated automatic mask correction added.
- Crop confirmation prevents unnoticed loss but is not an adjustable crop editor.
- Before/After toggle is not a zoom/slider.
- No evidence this UI patch improves image realism. Review existing paired pilot outputs before promoting any model method.
- Checker acceptance is candidate selection, not independent evaluation or clinical/nutrition validation.
- Build/version remains 0.4.1 candidate; use commit identity to distinguish it. No release tag or production artifact publication.
