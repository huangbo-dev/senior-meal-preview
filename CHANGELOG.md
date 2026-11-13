# SG Food Edit changelog

Android debug builds are published on the `apk/debug-0.1.0-20261111` branch as
`sg-food-edit-<version>-debug-<abi>.apk`. The version is also shown in the app under **About**.

## 0.3.2 — 2026-11-13

- **Bottom tab bar** on every screen: Meals · My photo · About. A screen's main action is pinned
  just above it (Generate/Review, Edit choices, Make the change, Try another photo); at large text
  sizes or on short screens it moves back into the page so nothing is covered. Tapping Meals again
  returns to the meal list; switching tabs keeps a half-painted photo. About is now a tab.
- Fix (web): choosing or taking a photo always failed with "Could not open that photo" because the
  page's Content-Security-Policy blocked reading the picked file (`blob:` URL).
- Fix: on the own-photo screen, errors told people to "choose Summary only", which only exists in
  the meal flow. GPU error messages no longer mention Tailscale, GPU nodes or "symbolic illustration".
- Fix: a recoloured brown-rice photo was labelled "Not AI-generated" while the notice beside it said
  "Experimental AI edit". The notice now reads "Experimental edit of your photo".
- The gateway timeout must cover the worker's retry budget: `backend.env.example` now says so. With
  the old 25 s value, broccoli edits needing retries (~30 s) were reported as timeouts although the
  worker finished. Spark02's gateway already uses 85 s.
- `scripts/check.sh` fails if the three reference photos are missing (`*.jpg` is git-ignored, which
  is how 0.3.0 shipped without them). Worker tests no longer crash their test server on Windows;
  `scripts/smoke.py` honours `CARGO_TARGET_DIR` and runs on Windows.

## 0.3.1 — 2026-11-13

- Fix: the 0.3.0 APK was built without the three meal reference photos, so every meal card read
  "Photo unavailable". They are bundled again. No other change.

## 0.3.0 — 2026-11-13

**Own-photo edits: faster, and they keep your meal** (project team only)
- **Brown rice** now recolours your own rice instead of generating new rice: the grains, the mound
  and the plate stay as photographed. No AI image model is used for this change. About 3 s
  (was about 12 s). Paint the rice only: a white plate under the brush is tinted too.
- **Add broccoli** now takes one small painted patch and places broccoli there, leaving the rest of
  the rice untouched. About 11 s per attempt.
- Before this, both changes blanked the painted area and regenerated it, which often drew a new
  bowl or plate in place of the rice.
- The waiting screen shows a progress bar and the seconds so far. The bar is an estimate from
  elapsed time; the server does not report progress.
- These two methods are app-only (`WORKER_PHOTO_METHOD=app` on the worker). They were chosen by eye
  on one public chicken rice photo, are not the CE7454 research method, and are not evaluated.
  The automatic check was written for the research method and often marks a recoloured photo
  "not passed".

## 0.2.0 — 2026-11-12

**New: edit your own meal photo** (project team only)
- "Use my own meal photo" on the Meals screen: take or choose a photo of a rice meal, choose
  *brown rice* or *add broccoli*, paint over the rice, and get the edited photo back beside the original.
- The photo is cropped to a square and its location data removed on the phone. The server deletes
  it after the edit and keeps nothing.
- Results come from the BrushNet-SDXL editor with the Qwen2.5-VL checker on Spark02. They are
  labelled as experimental and not reviewed by a person. In testing, the rice was sometimes replaced
  with a decorated bowl even when the checker passed it.
- Server: new `POST /api/v1/photo-preview`, and the catalog advertises `photo_upload`.

## 0.1.1 — 2026-11-12 (published as 0.1.0)

- App renamed to **SG Food Edit** on the home screen, recent apps, iOS and web.
- New app icon: a plate with one small leaf (Android adaptive, iOS, web).
- The three meal reference photos are now bundled; before, every meal card read "Photo unavailable".
- The home screen offers **Try again** after 8 s and shows an error after 15 s, instead of staying on
  "Getting the meal choices…".

## 0.1.0 — 2026-11-11

- First Android debug build ("A little change"): choose a meal and up to two changes, and see an
  illustrated summary. No AI editing.
