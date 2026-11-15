# Rice finder: agreement with hand-drawn rice masks

Measured 2026-11-15 for `gpu-worker/auto_mask.py` (`automask-v1`: CLIPSeg `CIDAS/clipseg-rd64-refined`
for the location, SAM `facebook/sam-vit-base` for the outline).

## Data

The 30 rice photos of the CE7454 project bundle (`pairs.json`, task T2, source rice): 15 `dev`, 15 `test`.
Reference: each photo's hand-drawn rice mask `M1`. Photos and masks were only read, at 1024×1024,
and are not copied into this repository. The masks carry a "needs-review" flag in the project
manifest, so they are a reference, not verified ground truth.

The finder's thresholds were set by eye on five other photos before this measurement and were
not changed afterwards. The `test` split was not used for any choice.

## Result

| Split | Photos | Mean IoU | Median IoU | IoU ≥ 0.5 | Not found |
| --- | --- | --- | --- | --- | --- |
| dev | 15 | 0.91 | 0.93 | 15 | 0 |
| test | 15 | 0.83 | 0.94 | 13 | 0 |

Per photo, recall is 0.81–0.97 (the finder rarely misses rice). The two `test` failures have
precision 0.31 and 0.35: the outline spills well past the rice, onto a plate or another white
food. A third photo (IoU 0.61, precision 0.67) shows the same pattern more mildly. When this
happens, brown rice also tints whatever the finder included.

## Limits

- 30 photos, one annotator, hawker-style rice plates only. No other cuisines, lighting or bowls.
- IoU measures where the edit goes, not how the edited photo looks.
- No person has rated the edited photos; nothing here is evidence about nutrition or health.

# Brown-rice colour (app-v3)

The recolour target was changed from L\*a\*b\* (56, 11, 29) with grain contrast 1.35 to (40, 8, 24)
with contrast 1.7. It was chosen on the 15 `dev` photos above, using the CE7454 checker as a
guide and looking at the results; the `test` photos were then checked once, for reporting only.
The checker selects candidates; it is not a person's judgement.

| Split | Colour | Checker pass | "Is it brown rice" (0–2) | Realism (1–5) |
| --- | --- | --- | --- | --- |
| dev | old (56, 11, 29) | 2/15 | 0.74 | 3.54 |
| dev | new (40, 8, 24) | 6/15 | 1.42 | 3.56 |
| test | old | 2/15 | 0.94 | 4.10 |
| test | new | 2/15 | 1.32 | 3.37 |

On held-out photos the new colour reads more as brown rice but less realistic, and the pass rate
did not change. It is a trade-off, not a measured improvement.

## Paired demo check on three Singapore meals

On 15 November 2026, Spark 02 ran the 0.6.0 app methods on three public meal photos. For each 1024 px square crop, a rice mask was manually traced and visually checked before inspecting automatic masks or edits. These are approximate single-reviewer outlines. Each arm used the same source pixels, app-v3 colour target, broccoli placement rule, SDXL configuration and broccoli seed (1107). There was one candidate per condition. Qwen judged each candidate. This diagnostic used the worker functions directly and did not measure upload latency or the app retry policy.

| Meal (Wikimedia Commons ID) | Rice-mask IoU | Brown rice, automatic / hand | Broccoli, automatic / hand |
| --- | ---: | --- | --- |
| White chicken rice (30708968) | 0.84 | fail / pass | fail / fail |
| Roast chicken and char siu (28840135) | 0.31 | fail / fail | fail / pass |
| Changi T4 chicken rice (140834417) | 0.36 | fail / fail | pass / pass |

The Changi automatic mask included the pale chicken. Recolouring tinted the meat, and a broccoli candidate covered it while still passing Qwen. The reviewed mask moved the floret toward the edge of the rice. On the close-up chicken meal both masks produced a single, conspicuously bright floret. Before showcasing a live edit, inspect the proposed region over the original and offer correction. Then test broccoli portion size, contact with the rice and lighting on the same reviewed region. These three meals cannot establish a general performance gain.
