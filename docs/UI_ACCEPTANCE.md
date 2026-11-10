# UI acceptance and review matrix

This is a checklist for the **next** design pass, not a record of passed checks. Existing results belong in [TESTING.md](TESTING.md). Record evidence per scenario with date, build/commit, platform, viewport, text scale, actual result and any limitation.

## Review fixtures and screenshots

Use only the built-in demo catalog and synthetic responses. No identifiable people, personal food photos, health details, real participant data or unpublished experiment outputs.

Capture at least: initial meal screen (unselected/selected), change screen (one/two selected), one-choice Fish soup, preview, catalog error, submit error and loading/submitting state. Include wide layout, 390×844, 360×800 at 200% text and the most constrained supported layout. Screenshots stay outside Git under the repository image rules; share approved artifacts separately if needed. A screenshot proves appearance for that state, not behavior or accessibility conformance.

## Functional and interruption scenarios

| ID | Action | Accept when |
| --- | --- | --- |
| F01 | Open with API available | Loading is communicated; real catalog appears; no preselected meal or fabricated result |
| F02 | Open with API unavailable, then restore it | Truthful failure, visible retry; successful retry loads catalog; no hidden fixture fallback |
| F03 | Continue before selecting | Disabled with understandable instruction; no progression |
| F04 | Select each meal | Selection visible without color alone and announced; continue selects exact dish |
| F05 | Go back and reselect same meal | Prior choices/preferences remain; no stale preview |
| F06 | Change to a different meal | Prior changes/preferences cleared; only compatible options shown |
| F07 | Fish soup | Only Add vegetables shown; copy does not suggest a nonexistent second option; preview works |
| F08 | Select 0, 1, 2 changes; attempt third | Zero cannot submit, 1/2 can; selected controls removable; third cannot silently replace a choice |
| F09 | Choose Soft/Mild, then No preference | Each group has one clear selection, request payload matches; no nutrition/safety claim |
| F10 | Submit several times quickly | One request, disabled submit, state announced; no repeated transition |
| F11 | Back/reset during request; late success/error arrives | No return to obsolete preview or restored cleared choices; no stale error |
| F12 | Timeout/server error; retry | Choices retained, actionable message, retry possible; no fake success |
| F13 | Wrong dish/target/preference, duplicate target, unsupported schema/mode | Refused with recoverable error; no misleading preview |
| F14 | Edit preview | Choices/preferences retained, old preview invalidated; changed request produces matching summary |
| F15 | Start over/another meal, then choose again | Meal/changes/preferences/preview reset; no persisted state |
| F16 | Close/refresh, reopen | No saved-record implication; initial flow starts again |
| F17 | Native/system back, web navigation and stage changes | No app trap, unexpected state or obsolete request outcome; document unsupported platform behavior honestly |
| F18 | If confirmation/sticky controls introduced | Cancel restores focus/state; confirmation resets; sticky region never hides controls or content |

## Visual, keyboard and assistive-technology checks

| ID | Check | Accept when |
| --- | --- | --- |
| A01 | 360/390px, tablet/wide and landscape | No horizontal clipping/overflow; hierarchy stays readable; every action reachable |
| A02 | 100/150/200% and largest practical OS text | No global scale cap, truncated essential copy or fixed-height clipping; scroll remains usable |
| A03 | Touch targets | Actual interactive hit regions at least 48×48 logical pixels; large primary buttons and spacing preserved |
| A04 | Color/contrast | Normal text ≥4.5:1, large text/essential indicators ≥3:1 where applicable; inspect rendered states, not token math alone |
| A05 | Selection and disabled reasons | Check/radio/outline plus semantics; count/instruction explains two-choice limit; no color-only cues |
| A06 | Keyboard tab/shift-tab/Enter/Space | Logical order, visible focus, all controls operable, no trap; focus not hidden by sticky bars |
| A07 | Screen-reader labels | Meal name, group, selected state, change count and button purpose clear, without duplicate narration |
| A08 | New step/error/loading | Relevant state announced once; focus moves to useful heading/error; no focus on a removed control |
| A09 | Plate illustration | Image semantics identify it as symbolic; text conveys requested changes independently; decorative shapes silent |
| A10 | Motion and interruptions | No required animation/gesture/timer; any new motion respects reduced-motion preferences |
| A11 | Native VoiceOver and TalkBack | Complete all three steps, edit and reset in built native apps; log platform/version/device, issues and untested cases |

Do not mark A11 passed based on Flutter widget semantics or Chrome canvas inspection. Do not equate lack of overflow exceptions with full A01/A02 verification.

## Evidence and scope review (P0/P1 pass, 8 November 2026)

- [x] Each preview plate explicitly says it is simulated; distinction survives narrow/large-text layouts.
- [x] “Requested” is used consistently; no checked/approved health result implied by icons or wording (`RequestSummary` uses neutral circle bullets).
- [x] Soft/Mild remain optional and do not claim verified texture or swallowing safety.
- [x] No calories, allergen guarantees, nutrient deltas, model confidence or fabricated improvement metrics.
- [x] No photos/uploads, saved accounts/preferences, health fields, analytics or remote inference added.
- [x] Catalog/API unavailable is truthful, without hidden fixture fallback.
- [x] Research experiment/report/study files remain unchanged; extension remains outside coursework submission.
- [x] Test outcome distinguishes code tests, visual inspection, native tests and actual user research (`A11` native VoiceOver/TalkBack and older-adult usability sessions remain open).

## Human usability work, later

Before recruitment, agree scope, consent, privacy, appropriate ethics review and data handling. Recruit with varied visual/motor/digital experience rather than treating age as a capability label. Ask users to choose a meal, change their mind, recover from an error and explain what the preview does and does not establish. Observe comprehension, task completion, mistakes and comfort; predefine the measures. Do not collect personal health data for a basic usability task. A pilot with developers is not evidence of benefit or acceptance among older adults.
