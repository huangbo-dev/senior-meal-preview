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


## Follow-up browser QA and asset packaging
- Tested the actual release web build in Chrome on ANGEL-WS011 using an isolated loopback mock service (port5187), never the live GPU worker.
- Desktop and390x844 browser view: home options/privacy, catalogue entry, change selection, preference sheet/cancel, and request-summary disclosure rendered without observed clipping.
- Uploaded the existing public chicken-rice reference fixture, marked rice, verified the crop gate, submitted a local-only response and observed the prominent failed-check result. The mock explicitly labels unchanged output as LOCAL UI TEST, not model output.
- Returned to choosing another photo. Same-photo retry and Before/After switching remain covered by automated widget tests; they were not independently completed in this browser pass.
- A missing-assets problem was found in the initial local build. The repository intentionally excludes meal JPGs; the existing scripts/check.sh already rejects missing assets. The earlier targeted checks bypassed that aggregate packaging prerequisite.
- Reused the three existing licensed Wikimedia reference JPGs from the prior v0.3.1 local package, confirmed attribution file SHA256 matches this repository, inspected all three images, and rebuilt. Browser verified all three catalogue cards display photographs.
- No source/user meal photos added to Git. Future fresh-checkout builds still require these attributed files before building.
- No real model latency measurement: browser upload tooling incurred a long delay, not attributable to app inference.
- Both temporary local servers stopped, temporary browser viewport reset, QA tabs closed. Production services untouched.

## Reproducible reference-photo setup (fresh checkout)

The three meal JPEGs are deliberately **not in Git**, following CLAUDE.md. A bare
clone therefore cannot show catalogue photos until this explicit prerequisite runs:

```sh
python3 scripts/fetch_reference_photos.py
python3 scripts/fetch_reference_photos.py --check
./scripts/check.sh
```

On Windows use `python` or the installed Python executable instead of `python3`.
The acquisition command uses only the three public Wikimedia thumbnail URLs in
`mobile/assets/meals/ATTRIBUTION.md`; it does not inspect/upload user photographs.
It verifies pinned SHA-256 hashes and JPEG headers and refuses to overwrite a
mismatching existing file. If Wikimedia is unreachable or its thumbnail bytes
change, acquisition fails closed rather than silently accepting a different file.
A previously verified release/cache is an offline alternative:

```sh
python3 scripts/fetch_reference_photos.py --source-dir /path/to/assets/meals
```

The cache must contain the same three pinned files. Original authors, source links
and Creative Commons license terms remain in ATTRIBUTION.md (bundled by Flutter).
Retain those notices in distributions, including the tofu image's CC BY-SA terms.
Once populated, the existing Flutter asset declaration bundles these files into the
web/native build. Rebuild after acquisition; copying into source does not update an
already-built package. No photos are committed or force-added.

Acquisition verification: the network command was run against an empty temporary
repository-shaped directory on ANGEL-WS011. All three Wikimedia downloads passed
the pinned hashes and installed successfully. Two automated tests cover offline
cache installation, check mode, invalid bytes/hashes, and refusing to overwrite an
existing mismatched file. The local candidate build already verified packaging and
mobile catalogue display; a second full Flutter build from a fresh clone was not run.
