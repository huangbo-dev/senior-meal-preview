# Local API v1

Base URL: `http://127.0.0.1:8787`. JSON only. The service is stateless; no route creates a saved record. All successful catalog/preview responses carry `schema_version: 1` and `mode: "illustrative_only"`.

## GET /healthz

```json
{"status":"ok","mode":"illustrative_only"}
```

## GET /api/v1/catalog

Returns `dishes`, `changes`, and `notice`. Each dish has `id`, `name`, `description`, `color`. Each change has `id`, `label`, `description`, and compatible `dish_ids`.

Dish IDs: `chicken_rice`, `fish_soup`, `tofu_rice`.

- `extra_vegetables`: all three dishes.
- `brown_rice`: chicken rice and tofu rice.
- `sauce_on_side`: chicken rice and tofu rice.

The catalog is a hand-authored demo fixture. Its names and colour codes do not assert ingredients, allergies, nutritional values, or suitability.

## POST /api/v1/preview

```sh
curl -i http://127.0.0.1:8787/api/v1/preview \
  -H 'Content-Type: application/json' \
  -d '{"dish_id":"chicken_rice","change_ids":["brown_rice","extra_vegetables"],"preferences":{"texture":"soft","flavour":"mild"}}'
```

`change_ids` must contain one or two distinct, compatible IDs. Optional preferences default to `any`. Supported texture values are `any`, `soft`; flavour values are `any`, `mild`. Unknown fields/enum values are rejected, including any photo URL, personal name, health condition, or medication field. Text preferences are not accepted.

Success returns the selected `dish`, ordered `edit_targets` (`id`, `label`, `description`), normalized `preferences`, a `summary`, and `notices`. The client draws the illustration locally. There is no image URL, nutrition estimate, AI score, user/session identifier, or saved preview ID.

Error shape:

```json
{"error":{"code":"change_count","message":"Choose one or two meal changes."}}
```

- `400`: unsupported dish/change, duplicate/incompatible change, or change count outside 1–2.
- `404`: route does not exist.
- `405`: method not supported for the route.
- `413`: body exceeds 16 KiB.
- `415`: not `application/json`.
- `422`: malformed or unsupported JSON shape, fields, or enum values.

Errors do not echo submitted content. Repeating a valid request returns the same descriptive response and creates no persistent data.

## Local browser development

CORS permits only exact HTTP loopback origins using `localhost` or `127.0.0.1` and a valid port. No credentials are allowed. Native emulator requests do not rely on browser CORS. This restriction is a development safeguard, not an authorization mechanism. No endpoint should be forwarded to a public network.
