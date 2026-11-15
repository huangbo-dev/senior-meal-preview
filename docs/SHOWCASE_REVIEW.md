# SG Food Edit presentation review

Reviewed the standalone app at main commit `24091d8` on 15 November 2026. The coursework extension and the deployed instance can differ from this checkout. The examples below demonstrate app behaviour and do not change the coursework evaluation.

## What to show in two minutes

1. Open the self-contained **SG Food Edit walkthrough.html** in a browser. Under **Chicken rice**, switch from **Colour edit** to **Rice region**. The hand-marked region explains why the chicken and cucumber keep their appearance. The live app's colour-transfer code produced these pixels locally. The mask was prepared by hand, and this replay has no automatic checker verdict.
2. Switch to **Tofu rice**. Compare both attempts against the original fish cake, tofu and rice meal. The previous real Spark fixture run replaced a small rice patch with an object. Qwen rejected both attempts. Attempt 1 still won the score-based selection. This photograph also differs from the tofu-only reference on the live Meals tab.
3. In the local Flutter presentation, choose **Try meal choices → Chicken rice → Try brown rice → Review 1 change**. This runs the real Flutter client and Rust gateway. With the model worker disconnected, the result is a request summary and the original photo. The saved image examples remain available using the Back button at the top left.

## Findings and next tests

| Priority | Code and observed behaviour | Consequence and next step |
| --- | --- | --- |
| 1. A returned image can fail the edit | On main, the stock-photo result in `mobile/lib/main.dart` (`_showPicture`) omitted the checker verdict. The own-photo result in `photo_flow.dart` put the verdict below both images. The previous Spark tofu repeat returned HTTP 200 after 24.58 s despite two failed attempts. | The local changes surface the verdict before each edited image and identify a failed candidate. Evaluate completion, human-rated realism and unintended changes separately from transport success. |
| 2. Mask quality and rendering quality are confounded | In `gpu-worker/auto_mask.py`, `find_rice` seeds SAM from the largest connected heat-map region. Its agreement threshold compares SAM to CLIPSeg, not to an independent rice annotation. The v0.5 changelog records five development photos. `broccoli_patch` draws one disk at the deepest point inside the rice. | Disconnected pockets of rice can be missed. A disk imposes a single placement even on mixed dishes. On fresh licensed Singapore meals, compare automatic and hand-reviewed masks on the same photos with the same settings. Record misses, plate or side-dish spill, and unconvincing vegetable placement. Include tofu, occluded rice and a rice-free control. |
| 3. The showcased rice method cannot synthesize grain mixtures | `gpu-worker/app_methods.py::recolour_rice` uses one CIELAB target and preserves photographed grain geometry. It can also tint a white plate included in the mask. The blended SDXL broccoli parameters were chosen by eye on one public photograph. | For the next run, score rice coverage and grain appearance separately. Include the team's pale and reddish-brown mixed-grain references in the visual rubric. First establish whether a good mask fixes the output. |
| 4. Readiness and retries are fragile during a presentation | `is_photo_pipeline_ready` tests for the research checkout. The cached segmenter check looks for two config files. Neither exercises segmentation, generation or Qwen. The gateway default is 25 s, very close to the 24.58 s tofu repeat. The app also waits on a synchronous request. The main worker serializes computation with a blocking lock; another request can remain queued after a client gives up. | Before offering a live run, test the exact worker build with a known photo, inspect the returned image and checker verdict, then try an unavailable worker and two concurrent requests. Verify the worker admission fix on the auto-mask lineage. A job ID and result retrieval would allow a disconnected client to recover its original request. |
| 5. The app methods and the research pipeline answer different questions | The showcased colour edit uses the app method and a manual mask. The recorded tofu fixture used BrushNet and Qwen. The live own-photo broccoli path uses masked SDXL image-to-image. Existing CE7454 fixed-mask results therefore do not establish quality on uploaded meals. | Keep the per-example method, source, mask origin and checker status visible. For a class demo, use the saved comparison; for a live-quality claim, use a held-out app evaluation with independently reviewed outcomes. |

**Next experiment.** Freeze both mask conditions before looking at the edits. Use each meal as its own comparison, fix the broccoli seeds, and count all eligible photos, including detection failures. Report automatic-versus-manual mask IoU, background change outside an independently reviewed mask, and blinded author judgments of edit completion and naturalness. Report per-meal results and the number of distinct meals. This design can distinguish segmentation failures from editor failures. A single successful photo or a Qwen pass cannot establish reliability.

## Rebuild locally

From the standalone app root, use a Python environment containing Pillow, NumPy and SciPy. The licensed source photos and saved Spark contact sheet are kept outside Git.

```sh
python scripts/fetch_reference_photos.py
python scripts/prepare_showcase.py ~/ce7454-tofu-comparison.jpg --html '../SG Food Edit walkthrough.html'
```

The script verifies the pinned source bytes, runs the current app colour method, crops the two saved Spark candidates from their labelled contact sheet, and embeds the six comparison images into one HTML file. The HTML opens directly in a browser and can be shared with the group. The Flutter build uses the same six images. Its display labels identify the source and licence of each photograph.

Start the real local catalogue API in one terminal. Leave the optional model worker unset for the offline presentation.

```sh
APP_PORT=18787 cargo run --locked --manifest-path backend/Cargo.toml
```

In a second terminal, build and serve the presentation on loopback.

```sh
cd mobile
flutter build web --release --no-web-resources-cdn --dart-define=MEAL_SHOWCASE=true --dart-define=API_BASE_URL=http://127.0.0.1:18787
python3 -m http.server 15173 --bind 127.0.0.1 --directory build/web
```

Open http://127.0.0.1:15173/ on this computer. The self-contained HTML is the portable version for other devices.
