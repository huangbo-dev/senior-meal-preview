# Architecture and integration boundaries

Flutter client → local Rust HTTP API → static, versioned illustrative catalog.

The API validates intent and echoes a coherent preview description. Flutter renders symbolic plates. Neither process reads the CE7454 checkout, uses GPU resources, starts Python, consumes model outputs, or claims to produce model outputs.

## Why this boundary exists

The research question about checker/targeted-retry faithfulness is distinct from a preference-led app's usability. This app does not validate either hypothesis. A model-selected score is not human ground truth, and a photorealistic edit is not nutritional evidence. There is no participant recruitment, consent workflow, preference-learning model, trial result, or outcome measurement.

## Contract before model integration

A future backend adapter should explicitly version and test:

1. Authorized input photo/mask formats and size limits, with removal of identifying metadata.
2. Dish/edit intent validation, user-visible confirmation, and image-use consent.
3. Asynchronous job states, cancellation, timeouts, ownership/access controls, and bounded concurrency.
4. Source/edited image provenance, generated-image labels, and method/budget accounting.
5. Separation of checker diagnostics from independent human judgments.
6. Failure and uncertain-result handling without silently substituting mock outputs.
7. Retention/deletion rules, secure transport, logging redaction, and deployment controls.

Do not expose the current process or retrofit arbitrary file paths/commands into the request model. Keep Python inference in an independently controlled service or job adapter rather than reimplementing ML inference in Rust without a verified need.

## Nutrition and accessibility

A later meal-swap catalog needs trustworthy source references, recipe quantities, known limitations, versioned changes, and validated calculations before numerical nutrient comparisons. Preferences must not become medical advice. Images cannot determine allergens or clinical suitability.

The current UI aims for readable text, high contrast, large labelled controls, screen-reader semantics, and scalable layouts. Automated tests are not evidence of validation with older adults or assistive technologies. Native VoiceOver/TalkBack and real-device sessions remain necessary before making accessibility claims.

## Deliberate omissions

No user accounts, photo uploads, health data, database, analytics, remote models, real-time GPU jobs, participant export, public deployment, or app-store submission. Add these only with an explicit scope and suitable review. Build artifacts and platform signing secrets are excluded from source packaging.
