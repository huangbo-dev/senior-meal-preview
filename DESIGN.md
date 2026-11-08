# A little change: UI design specification

**Scope:** `extensions/senior-meal-preview/` only. Separate, non-submission Flutter + Rust app.
**Design baseline:** commit `023aac0ceab7d64fd795345277fec93d086b8dc7`, inspected 8 November 2026.
**Status:** implemented baseline plus prioritized proposals. Proposals below are not shipped features or evidence of validation.

Start with [AGENT_HANDOFF.md](AGENT_HANDOFF.md) for the takeover sequence, [UI acceptance](docs/UI_ACCEPTANCE.md) for test cases, and [design tokens](docs/design-tokens.json) for machine-readable values. This document is the requested design.md handoff; keep one canonical specification rather than a second case-only filename.

## 1. Product intent and evidence boundary

Help someone explore one or two small changes to a familiar meal, with optional flavour/texture requests, then review what they selected. The visual direction should feel calm, adult, approachable and easy to operate. Do not frame older adults as a uniform group or use infantilizing copy, health rankings, guilt, streaks or compliance scores.

The implemented prototype is **Flutter → loopback Rust API → hand-authored catalog → symbolic plate drawing**. It does not generate an AI image. A successful request validates selection IDs and returns a description, not evidence that a meal was made, changed, healthier or safe. Actual older-adult usability, nutrition benefits and model faithfulness are three separate questions, none established by this app.

### Non-negotiable content rules

- Label the app as a local, illustrative prototype and keep the non-submission boundary in the footer/docs.
- Keep a short illustration disclosure before the preview and an explicit label on **each** plate, not only in a footer or tooltip.
- Always distinguish requested changes from achieved changes. Use “What you requested,” “Original idea,” and “Requested idea.” Never “AI verified,” “nutrition approved,” “healthier,” “safe for swallowing,” or “recommended for your condition.”
- “Soft” and “Mild” are optional requests. No dish texture, allergen absence, nutritional quality, portion amount or clinical suitability has been checked. Do not imply these attributes are visually verified.
- The example catalog is not a guideline-backed recommendation list. A brown-rice option is a choice, not a universal prescription.
- No photos, free-text health fields, medical history, identity, participant data, analytics, accounts, saved preferences or model/GPU requests in this design pass.
- Do not present checker scores, experiment comparisons or researcher controls inside this consumer-facing flow. The earlier offline Hawker Lab evaluation workbench is a different artifact, not a screen to merge into this app.

## 2. Implemented screen map

| Screen/state | Current hierarchy and actions | Implementation |
| --- | --- | --- |
| Loading | Brand → loading indicator and “Getting the meal choices…” | `_loadingView()` |
| Catalog failure | Brand → “Let’s reconnect” → explanation → “Try again” → local-service note | `_catalogFailure()` |
| 1. Choose a meal | Brand → step label → headline → instruction → illustrative notice → three meal cards → “Choose my changes” → selection helper | `_chooseMeal()`, `_mealCard()` |
| 2. Make it yours | Brand/reset → step label → dish context → 1–2 change instruction/count → compatible change rows → optional texture/flavour → error if any → “See my meal idea” → “Back to meals” | `_chooseChanges()` |
| Submission | Same screen, selections/preferences locked, submit disabled with progress; Back and Start over remain available | `_submit()`, request-version guard |
| 3. See the idea | Brand/reset → step label → headline/summary → simulation disclosure → original/requested plates → requested changes/preferences → notices → edit/another-meal actions | `_showPreview()`, `_plateCard()` |

There is no bottom navigation, login, dashboard, camera, history, saving, nutrition panel, settings screen or permanent user record. Do not add navigation destinations merely to fill a mockup.

### Current choices and contract

- Meals: Chicken rice (`chicken_rice`), Fish soup (`fish_soup`), Tofu rice (`tofu_rice`).
- Add vegetables (`extra_vegetables`) works with all three illustrative meals.
- Try brown rice (`brown_rice`) and Sauce on the side (`sauce_on_side`) work with chicken/tofu rice only.
- Select one or two compatible changes. Fish soup currently exposes one change, so its UI should not promise two available choices.
- Texture: No preference (`any`) or Soft (`soft`). Flavour: No preference (`any`) or Mild (`mild`). Both default to `any`.
- API v1 must retain `mode: illustrative_only`; there is no image URL, nutrition quantity, score, session ID or saved-preview ID. See [API.md](docs/API.md).

## 3. Visual direction

**Working name:** A little change. Preserve it unless the user requests a rename.

Use warm cream, deep green text/action surfaces, white cards, restrained sage selection fills and simple plate illustrations. The green denotes the interface and selection state, not health approval. Keep the large, readable type and generous control spacing. Prefer short, descriptive labels to decorative copy; one primary action per screen. Avoid extra gradients, glass effects, busy photography, pill-shaped metrics and dashboard chrome.

The baseline mobile screenshot shows a clear, calm hierarchy but tall meal illustrations push later choices and the action well below the first screen. The next pass should improve decision density **without shrinking text or touch targets**. This is an inspection finding, not a measured usability result.

### Color tokens

Values in [design-tokens.json](docs/design-tokens.json) are explicit source values, not a complete export of Material 3's generated color scheme.

| Role | Current value | Use |
| --- | --- | --- |
| Ink / primary | `#163D34` | Headings, selected outlines, primary actions |
| Background | `#F8F6EF` | Page canvas |
| Secondary text | `#52655C` | Supporting copy, progress label |
| Surface | `#FFFFFF` | Unselected meal/change cards |
| Selected card | `#EAF0E2` | Selected meal/change surface, accompanied by check/radio state |
| Selected chip | `#E1EBD7` | Optional preference selection |
| Notice surface | `#EEE8D5` | Prototype/information disclosure |
| Error surface / text | `#FBE9E3` / `#7E211E` | Plain-language error box; icon `#9C2520` |
| Subtle outline | `#D7DDD1` | Decorative card edge; insufficient as sole state/control indicator |
| Plate-card surface | `#EAEDE2` | Illustration presentation |
| Proposed strong outline | `#718476` | Candidate for interactive boundaries/focus-adjacent controls when needed; not implemented |

Computed sRGB contrast ratios for solid colors: ink/cream **11.09:1**, secondary/cream **5.75:1**, white/ink **11.99:1**, ink/selected **10.31:1**, ink/notice **9.79:1**, error text/error surface **8.41:1**. Subtle outline/white is only **1.39:1**; do not rely on that edge alone. Proposed strong outline/white is **3.99:1** and /cream **3.69:1**. These are token calculations, not a rendered UI audit. Test generated Material colors, disabled states, focus, text overlays and actual screenshots independently.

### Typography, spacing and shape

| Role | Implemented size / line-height / weight |
| --- | --- |
| Main headline | 38sp / 1.12 / 700, tracking −1.2 |
| Section heading | 27sp / 1.20 / 700 |
| Card/title | 22sp / 1.30 / 700 |
| Group title | 19sp / 1.40 / 600 |
| Body large | 19sp / 1.50 |
| Body medium / notices | 17sp / 1.45 |
| Primary label | 18sp / 700 |
| Progress metadata | 14sp / 800, uppercase, tracking 1.3 |

- Font: locally bundled Roboto in web builds; do not introduce remote font calls. Verify the actual native font behavior before claiming parity.
- Baseline spacing is generally 8/12/16/18/20/24/32 logical pixels. Retain clear 24px major section gaps; do not imply these are already centralized tokens.
- Page horizontal padding is 24px; max outer content width is 800px. SafeArea remains mandatory.
- Main button minimum height is 58px, outlined 56px, text-button target 52px high; labels can wrap and containers must grow with scaling.
- Card radii: meal 22px, change 18px, plate 24px, notice 16px. Button radius 18px.
- Proposal: progress label becomes sentence case, 16sp minimum (“Step 1 of 3 · Choose a meal”). Allow natural wrapping. Test rather than constraining it to one line.
- Proposal: extract a reusable theme/token layer before changing values across screens. Avoid a parallel CSS or React implementation of this Flutter UI.

## 4. Proposed layout pass (P1, not implemented)

### Meal selection

Keep the hierarchy: purpose → demo disclosure → choices → clear next action. The disclosure must remain available before selecting a meal, but can be a short, readable callout rather than a large repeated legal block.

At 360–430px widths, explore a compact horizontal meal card: 72–88px symbolic illustration, a flexible text column, and a clearly visible selected indicator. Minimum card height about 120px is a **starting point**, not a fixed height. Switch back to vertical content if text scaling or available width requires it. Never truncate meal names or descriptions to force all three into one viewport. Reuse the existing painter, not stock meal photography.

A bottom action region may improve discovery, but prototype it first. If used, it must reserve body padding, respect safe areas/keyboard, not cover focused controls, and become normal document flow when large text leaves insufficient space. Do not introduce a sticky button that solves scrolling at 100% by breaking 200% text.

### Changes and preferences

Keep requested changes primary, optional preferences secondary. Use checkbox semantics for the multi-select change list and a single-choice group for each preference. Announce the number selected. With two selected, preserve a visible explanation of why the third option cannot be chosen; never silently replace a previous choice. For a meal with only one compatible change, adapt instruction copy to “Choose this change to see an idea” or another accurate one-choice instruction.

Keep “No preference” easy to choose. Supporting copy should clarify that preferences are requests, not verification. Do not default Soft based on presumed age. Avoid a new health questionnaire.

### Preview

Keep exact requested changes as the primary readout. On narrow screens, consider a compact request summary directly before the illustrated comparison; do not force a user to scroll past two large drawings to discover what changed. Each illustration keeps its own “Simulated plate illustration” label.

Current layout stacks the comparison below 600px **available inner width** and shows two columns at or above it. Card layout changes at 500px inner width. Those are LayoutBuilder constraints, not device-width breakpoints. Test the proposed design at the actual available width after padding.

The symbolic vegetables/rice/sauce may change in the painter, but Soft and Mild do not alter the rendering. Say “requested” in the summary. No before/after nutritional delta, confidence gauge or clinical checkmark.

## 5. Interaction and interruption contract

| Event | Required behavior, baseline unless marked proposed |
| --- | --- |
| Initial load | Visible loading text; no selectable stale catalog or invented fallback |
| Catalog fails | Error with Try again; remain on failure state until a genuine successful fetch |
| No meal | Continue disabled, explanatory helper visible |
| Choose another meal | Clear prior changes/preferences because compatibility may differ |
| Back to the same meal | Keep current meal/choices/preferences; do not silently reset |
| No change | Preview disabled; instruction visible |
| Two changes selected | Third unselected change disabled; selected options remain removable |
| Submit repeatedly | One request; locked selection/preferences and disabled submit |
| Back/reset while pending | Navigation works; late success/error must not re-open preview or resurrect cleared choices |
| Preview timeout/error | Stay on changes, preserve choices, show retry action and plain explanation |
| Response mismatch or wrong mode | Reject response rather than displaying another dish/selection or fake illustration |
| Edit preview | Return to change screen with choices intact; discard obsolete preview |
| Start over / another meal | Clear meal, changes, preferences and preview; return to first step |
| Refresh/close | In-memory choices disappear; no false “saved” message |
| Stage transition | Scroll to top already implemented. **Proposed:** move accessibility/keyboard focus to new heading and announce stage without duplicate announcements |
| Reset safety | Current reset is immediate. **Proposed:** assess accidental-reset risk during usability work; if adding confirmation, “Keep editing” must preserve state and a canceled dialog must restore focus |

Current request invalidation prevents stale rendering; it is **not** cancellation of an executing server job. No server job currently exists. Any later asynchronous generation needs a separate cancellation contract.

## 6. Copy rules and recommended refinements

Keep current labels when they are truthful and familiar. Reduce cognitive load without hiding limitations.

| Context | Suggested next-pass copy | Status |
| --- | --- | --- |
| Start headline | “Choose a familiar meal” | Proposal for testing against current editorial headline |
| Demo callout | “Demo only. These drawings are not AI results or nutrition advice.” | Proposal; preserve full limitations at preview |
| Progress | “Step 2 of 3 · Make it yours” | Proposal |
| No selected changes | “Choose at least one change to continue.” | Proposal, supporting copy |
| Two selected | “2 of 2 selected. Remove one to choose another.” | Current meaning, plain-language refinement |
| Submission | “Preparing your meal idea…” | Proposal; replace sparkles with neutral preview/plate icon to reduce implied AI generation |
| Preview heading | “Your requested meal idea” | Proposal |
| Preview disclosure | “Illustration only. These drawings do not show a real meal or an AI result. Nutrition, texture, allergens and clinical safety have not been checked.” | Proposal; never reduce to an ambiguous “results may vary” |
| Soft preference helper | “A texture request only. This does not check swallowing safety.” | Proposal for contextual placement |

Do not use a success check icon to imply the requested change has been independently verified. If retaining check icons in the “What you requested” list, pair them clearly with that heading/semantics; a neutral bullet is the safer proposed option. Keep technical “local Rust service” recovery help for this developer prototype, not as assumed final consumer copy.

## 7. Accessibility acceptance intent

Targets are implementation criteria, not certification or proof of older-adult validation:

- Core body copy at least 17sp, action labels 18sp, optional metadata 16sp in the proposed pass. Respect system text scaling; no global scale cap.
- Test 100%, 150%, 200% and the largest practical OS accessibility setting; prioritize completion, wrapping and access over keeping content above the fold.
- Target 48×48 logical-pixel controls minimum across platforms; 56–60px primary actions. Test actual rendered hit regions and group spacing, not declared sizes alone.
- Normal text contrast at least 4.5:1; large text and essential non-text indicators at least 3:1. Selection must also have checked/selected semantics and a visible icon/outline, not color alone.
- Logical focus order, visibly distinct keyboard focus, Enter/Space activation, descriptive control names, group labels and selected/disabled state. Avoid duplicated spoken labels from nested semantics.
- Announce selection-count/error/submission changes once. Move focus deliberately on stage changes and after errors; never leave focus on an element removed from the tree.
- Each illustration has meaningful image semantics; decorative internal shapes/icons are excluded. Text must describe the request even when the illustration cannot be seen.
- No timed task, gesture-only action, hover-only explanation, autoplay, flashing, audio requirement or motion-dependent information. Respect reduced-motion behavior if adding animations.
- Test VoiceOver/TalkBack on actual native builds, keyboard use in web, portrait/landscape and interruption recovery. Existing widget tests are necessary but insufficient.
- Translation is future work: externalize strings before adding languages; validate terminology with intended users. Do not infer a preferred language or replace text with symbols alone.

## 8. Work order and scope gates

**P0: truth and regressions.** Preserve explicit illustration/evidence labels, compatibility rules, error/retry paths, no-persistence boundary and stale-response protection. Add regression tests for any changed flow before visual polish.

**P1: accessible presentation.** Extract theme/components, compact meal selection responsively, improve progress legibility, contextualize Soft/Mild, improve preview request hierarchy, and test focus/semantics. Deliver reviewed screenshots of all three screens and failure/loading states with no personal data; keep screenshots out of Git under the repository image rules.

**P2: native and user validation.** Build/run Android and iOS targets, perform assistive-technology checks, then plan consent/privacy-reviewed usability work with a varied older-adult group. Record completion, errors, comprehension of “illustrative,” ability to undo/edit, and stated comfort. Do not fabricate usability metrics or call a developer walkthrough a study.

**Separate future approval/scope:** real image uploads, remote backend, model jobs, saved accounts/preferences, nutrition calculations, participant data, public deployment, app-store publication or changes to research/report files. Read [ARCHITECTURE.md](docs/ARCHITECTURE.md) before proposing any such integration.

## 9. Inspection and source record

Reviewed source: `mobile/lib/main.dart`, `plate.dart`, `models.dart`, `api.dart`, `mobile/test/widget_test.dart`, `backend/src/lib.rs`, README and all existing API/architecture/testing docs at the baseline commit. Visually inspected the existing 390px-wide start-screen capture supplied by the implementation worker. Later-screen findings above are source inspection unless identified as earlier testing in [TESTING.md](docs/TESTING.md).

The existing verification record reports 11 Rust API test functions, 20 Flutter unit/widget tests, static/format checks, web build, live Dart-to-Rust smoke and Chrome desktop/mobile flow checks. This documentation pass does not repeat or extend those results. Native device/assistive-technology/user-study validation remains outstanding. No code, experiment, report or GPU process was changed by this design specification.
