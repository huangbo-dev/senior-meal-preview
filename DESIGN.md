# A little change: UI design specification

**Scope:** this app repository only. Separate, non-submission Flutter + Rust app.
**Design baseline:** commit `023aac0ceab7d64fd795345277fec93d086b8dc7`, P0/P1 pass implemented 8 November 2026.
**Status:** P0 and P1 implemented in Flutter (`mobile/lib/theme.dart`, `mobile/lib/widgets.dart`, `mobile/lib/main.dart`) and Rust (`backend/src/lib.rs`). Native assistive-technology and older-adult usability work (P2) remain future work.

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
| 1. Choose a meal | Brand → step label → headline → instruction → illustrative notice → three meal cards → “Choose my changes” → selection helper | `_chooseMeal()`, `MealCard` |
| 2. Make it yours | Brand/reset → step label → dish context → 1–2 change instruction/count → compatible change rows → optional texture/flavour → error if any → “See my meal idea” → “Back to meals” | `_chooseChanges()`, `ChangeOption`, `PreferenceGroup` |
| Submission | Same screen, selections/preferences locked, submit disabled with progress; Back and Start over remain available | `_submit()`, request-version guard |
| 3. See the idea | Brand/reset → step label → headline/summary → simulation disclosure → requested changes/preferences (`RequestSummary`) → original/requested plates (`PlateCard`) → notices → edit/another-meal actions | `_showPreview()`, `RequestSummary`, `PlateCard` |

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
| Strong outline | `#718476` | Implemented boundary for unselected interactive cards and chips |

Computed sRGB contrast ratios for solid colors: ink/cream **11.09:1**, secondary/cream **5.75:1**, white/ink **11.99:1**, ink/selected **10.31:1**, ink/notice **9.79:1**, error text/error surface **8.41:1**. Subtle outline/white is only **1.39:1**; do not rely on that edge alone. Proposed strong outline/white is **3.99:1** and /cream **3.69:1**. These are token calculations, not a rendered UI audit. Test generated Material colors, disabled states, focus, text overlays and actual screenshots independently.

### Typography, spacing and shape

| Role | Implemented size / line-height / weight |
| --- | --- |
| Main headline (`displaySmall`) | 28sp / 1.18 / 700, tracking −0.3 |
| Section heading (`headlineSmall`) | 22sp / 1.25 / 700, tracking −0.15 |
| Card/title (`titleLarge`) | 20sp / 1.28 / 700 |
| Group title (`titleMedium`) | 18sp / 1.35 / 700 |
| Body large (`bodyLarge`) | 18sp / 1.45 / 400 |
| Body medium / notices (`bodyMedium`) | 16.5sp / 1.42 / 400 |
| Primary label (`labelLarge`) | 18sp / 1.30 / 700 |
| Progress metadata (`labelMedium`) | 16sp / 1.38 / 600, sentence case (“Step 1 of 3 · Choose a meal”) |

- Font: locally bundled Roboto (`AppTypography.fontFamily` in `mobile/lib/theme.dart`) applied explicitly to every `TextTheme` slot, button theme, chip, and card so iOS, Android, and Web never mix platform fallback fonts (`SF Pro` vs `Roboto`) or unbundled italics.
- Page padding is `EdgeInsets.fromLTRB(20, 16, 20, 28)`; max outer content width is 800px. SafeArea remains mandatory.
- Main and outlined button minimum height is 56px, text-button target 48px high; labels can wrap and containers must grow with scaling.
- Card radii: meal 20px, change 18px, plate 22px, notice 16px. Button radius 16px.
- Progress label uses sentence case, 16sp minimum (“Step 1 of 3 · Choose a meal”), allowing natural wrapping.
- Theme and tokens are centralized in `mobile/lib/theme.dart` with reusable widgets in `mobile/lib/widgets.dart`. Avoid a parallel CSS or React implementation of this Flutter UI.

## 4. Layout pass (P1, implemented)

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
| Stage transition | Scroll to top and move accessibility/keyboard focus to new step heading (`StepHeading`) without duplicate announcements |
| Reset safety | Current reset is immediate. **Proposed:** assess accidental-reset risk during usability work; if adding confirmation, “Keep editing” must preserve state and a canceled dialog must restore focus |

Current request invalidation prevents stale rendering; it is **not** cancellation of an executing server job. No server job currently exists. Any later asynchronous generation needs a separate cancellation contract.

## 6. Copy rules and implemented refinements

Keep current labels when they are truthful and familiar. Reduce cognitive load without hiding limitations.

| Context | Copy | Status |
| --- | --- | --- |
| Start headline | “Choose a familiar meal” | Implemented (`StepHeading`) |
| Demo callout | “Demo only. These drawings are not AI results or nutrition advice.” | Implemented (`NoticeCard`) |
| Progress | “Step 2 of 3 · Make it yours” | Implemented (`StepProgress`, 16sp sentence case) |
| No selected changes | “Choose at least one change to continue.” / “Choose this change to continue.” (1-choice dish) | Implemented (`change-selection-status`) |
| Two selected | “2 of 2 selected. Remove one to choose another.” plus inline disabled helper | Implemented (`change-selection-status`, `ChangeOption`) |
| Submission | “Preparing your meal idea…” | Implemented with neutral preview icon (`Icons.visibility_outlined`) |
| Preview heading | “Your requested meal idea” | Implemented (`StepHeading`) |
| Preview disclosure | “Illustration only. These drawings do not show a real meal or an AI result. Nutrition, texture, allergens and clinical safety have not been checked.” | Implemented (`NoticeCard`) |
| Soft preference helper | “A texture request only. This does not check swallowing safety.” | Implemented (`PreferenceGroup`) |

`RequestSummary` (“What you requested”) uses neutral circle bullets rather than check icons so requested changes are never visually confused with verified outcomes. Keep technical “local Rust service” recovery help for this developer prototype, not as assumed final consumer copy.

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

Reviewed and updated source: `mobile/lib/main.dart`, `mobile/lib/theme.dart`, `mobile/lib/widgets.dart`, `mobile/lib/plate.dart`, `mobile/lib/models.dart`, `mobile/lib/api.dart`, `mobile/test/widget_test.dart`, `mobile/test/api_test.dart`, `backend/src/lib.rs`, `backend/src/main.rs`, `backend/tests/api.rs`, and all extension documentation on 8 November 2026.

The current verification record in [TESTING.md](docs/TESTING.md) reports 19 Rust API test functions, 3 Python GPU worker test suites, 26 Flutter unit/widget tests, strict static/format checks (`flutter analyze --fatal-infos`), release web build, Android debug APK build, iOS simulator build + launch (`iPhone 17 Pro`, iOS 26.5), live Dart-to-Rust dual-mode smoke, and 15 rendered acceptance screenshots across `390×844` (100% text), `360×800` (200% text) and `800×900` wide layout. Native assistive-technology (VoiceOver/TalkBack) and older-adult usability sessions remain outstanding. No coursework, experiment, report or GPU process was changed.
