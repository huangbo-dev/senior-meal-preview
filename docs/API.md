# Local API v1

Base URL: `http://127.0.0.1:8787`. JSON only. The service is stateless; no route creates a saved record. All successful catalog/preview responses carry `schema_version: 1` and `mode: "illustrative_only"`.

## GET /healthz

```json
{"status":"ok","mode":"illustrative_only","gpu_worker":{"configured":false,"transport":"none"}}
```

When `MODEL_WORKER_URL` is configured on EC2, `gpu_worker` reports `{"configured":true,"transport":"tailscale"}` (or `"loopback"` in local testing). `/healthz` remains unauthenticated so EC2/ALB/Caddy probes work when `APP_API_TOKEN` is enabled.

## GET /api/v1/catalog

Returns `dishes`, `changes`, `selection`, `capabilities`, and `notice`. Each dish has `id`, `name`, `description`, `color`. Each change has `id`, `label`, `description`, and compatible `dish_ids`. `selection` publishes the server's enforced limits (`{"min_changes": 1, "max_changes": 2}`) and `capabilities` advertises `{"symbolic_preview": true, "gpu_preview": <bool>}` so clients know whether a current, bounded worker health probe reports real GPU mode with configuration readiness. A configured URL alone, dry-run mode, a malformed response or an unreachable worker advertises false. This is not quality certification or a guarantee that every request succeeds; older v1 clients that ignore these additive fields remain compatible.

Dish IDs: `chicken_rice`, `fish_soup`, `tofu_rice`.

- `extra_vegetables`: all three dishes.
- `brown_rice`: chicken rice and tofu rice.
- `sauce_on_side`: chicken rice and tofu rice.

The catalog is a hand-authored demo fixture built once in memory. Its names and colour codes do not assert ingredients, allergies, nutritional values, or suitability.

## POST /api/v1/preview

```sh
curl -i http://127.0.0.1:8787/api/v1/preview \
  -H 'Content-Type: application/json' \
  -d '{"dish_id":"chicken_rice","change_ids":["brown_rice","extra_vegetables"],"preferences":{"texture":"soft","flavour":"mild"}}'
```

`change_ids` must contain one or two distinct, compatible IDs. Optional preferences default to `any`. Supported texture values are `any`, `soft`; flavour values are `any`, `mild`. Unknown fields/enum values are rejected, including any photo URL, personal name, health condition, or medication field. Text preferences are not accepted.

Success returns the selected `dish`, ordered `edit_targets` (`id`, `label`, `description`), normalized `preferences`, a `summary`, and `notices`. For default requests (`render_mode: "illustrative_only"` or omitted), the client draws the illustration locally and `gpu_artifact` is omitted. When `render_mode: "gpu_assisted"` is requested and `MODEL_WORKER_URL` is configured over Tailscale, the response also includes `gpu_artifact` (`provider`, `model`, `prompt_id`, `seed`, `attempts`, `checker_passed`, `image_data_url`, `generated_label`).

Error shape:

```json
{"error":{"code":"change_count","message":"Choose one or two meal changes."}}
```

- `400`: unsupported dish/change, duplicate/incompatible change, or change count outside 1–2.
- `401`: missing or invalid `Authorization: Bearer <APP_API_TOKEN>` when `APP_API_TOKEN` is configured on EC2.
- `404`: route does not exist.
- `405`: method not supported for the route.
- `408`: request timed out (`code: "timeout"`).
- `413`: body exceeds 16 KiB.
- `415`: not `application/json`.
- `422`: malformed or unsupported JSON shape, fields, or enum values.
- `502`: Tailscale GPU worker unreachable (`gpu_unreachable`) or returned an invalid artifact (`gpu_invalid_response`).
- `503`: Tailscale GPU worker not configured (`gpu_unavailable`), at concurrency limit (`gpu_busy`), or reachable but without loaded models/fixtures (`gpu_not_ready`).
- `422` with `gpu_unsupported_request`: the worker has no validated model path for this selection (currently anything other than a single `brown_rice` or `extra_vegetables` change on a rice meal).
- `504`: Tailscale GPU worker timed out (`gpu_timeout`).

Errors do not echo submitted content. Repeating a valid request returns the same descriptive response and creates no persistent data.

## POST /api/v1/photo-preview

Edits a photo: one the user took, or a meal's reference photo sent by the app. Body limit 8 MiB (other routes stay at 16 KiB). Unknown fields are rejected.

```json
{"change_ids":["brown_rice","extra_vegetables"],"image_png_base64":"iVBORw0KGgo…"}
{"change_id":"brown_rice","image_png_base64":"iVBORw0KGgo…","mask_png_base64":"iVBORw0KGgo…"}
```

- `change_ids`: one or two different values from `brown_rice` and `extra_vegetables`. The older single `change_id` is still accepted; send one of the two fields, not both.
- `image_png_base64`: square PNG. The app centre-crops and re-encodes it at 1024×1024 on the phone, which drops EXIF/GPS metadata.
- `mask_png_base64`: optional. Without it the worker finds the rice itself (needs `capabilities.auto_mask`; app photo methods only): brown rice recolours all the rice, broccoli goes on one patch inside it, and with both the broccoli is added first. With it (same-size PNG, white where the user painted, 0.5–85 % coverage) exactly one change is allowed.

Success returns `schema_version: 1`, `edit_target` (the first requested change), `edit_targets` (all of them), `notices` and a `gpu_artifact` (same schema as above; `generated_label` says whether the result is a recolour, an AI edit, or both, and always that no person reviewed it). With two changes `attempts` is the total and `checker_passed` is true only if every step passed. The worker writes the photo only to a per-request temporary directory and deletes it afterwards; `WORKER_RUN_DIR` is ignored for user photos. Nothing is stored by the gateway.

Errors: `400 unsupported_change`, `400 photo_invalid` (gateway check or worker could not use the photo/mask), `422 rice_not_found` (no mask was sent and the worker found no rice; the app then offers painting), `503 gpu_unavailable` (no worker), plus the GPU errors listed above. `GET /api/v1/catalog` advertises `capabilities.photo_upload` from the worker's `photo_ready` health field, separately from `gpu_preview`, and `capabilities.auto_mask` from `auto_mask_ready`.

The rice finder is CLIPSeg (`CIDAS/clipseg-rd64-refined`) for a coarse location and SAM (`facebook/sam-vit-base`) for the outline, loaded from the Hugging Face cache directory in `WORKER_SEGMENTER_CACHE` and never downloaded at run time. Its thresholds were set by eye on five photos on 15 Nov 2026; it is not evaluated.

Quality: on 12 Nov 2026 a public Wikimedia chicken rice photo, brown-rice request, passed the checker in one attempt (≈15 s through the tunnel) but replaced the rice dome with a patterned bowl of grain and garnish. Treat results as unreviewed experiments, for project-team use only.

## Local browser development

CORS permits only exact HTTP loopback origins using `localhost` or `127.0.0.1` and a valid port. No credentials are allowed. Native emulator requests do not rely on browser CORS. This restriction is a development safeguard, not an authorization mechanism. No endpoint should be forwarded to a public network.
