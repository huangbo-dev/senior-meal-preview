# SG Food Edit changelog

Android debug builds are published on the `apk/debug-0.1.0-20261111` branch as
`sg-food-edit-<version>-debug-<abi>.apk`. The version is also shown in the app under **About**.

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
