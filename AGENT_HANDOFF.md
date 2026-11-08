# Take over the meal-preview UI

## Read first

1. [README.md](README.md): scope, stack and local commands.
2. [DESIGN.md](DESIGN.md): current UI, proposed visual direction and evidence boundaries.
3. [docs/UI_ACCEPTANCE.md](docs/UI_ACCEPTANCE.md): scenario matrix and completion checks.
4. [docs/design-tokens.json](docs/design-tokens.json): implemented explicit tokens and clearly separate proposals.
5. [docs/API.md](docs/API.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/TESTING.md](docs/TESTING.md): contract, security/inference boundary and verified limits.

## Exact working context

- Repository: `huangbo-dev/ce7454-sgfood-edit`.
- App branch: `app/senior-meal-preview`.
- Baseline app commit: `023aac0ceab7d64fd795345277fec93d086b8dc7`.
- Canonical Mac worktree at preparation: `/Users/huangbo/Programming/NTU/CE7454/ce7454-senior-meal-preview-worktree`.
- App path: `extensions/senior-meal-preview/`.
- Root `main` clone: `/Users/huangbo/Programming/NTU/CE7454/ce7454-sgfood-edit`. Do not switch it or move the app onto main.
- User requested an independent Rust-backend/mobile app, code pushed to the repository, explicitly **not submitted as coursework**; then requested UI design and files so other agents can take over. This handoff does not authorize unrelated deployment, new data collection or inference jobs.

At pickup, verify the actual branch, `git status`, recent commits and current files. Paths and test results are a dated record, not permission to overwrite local work. Review any applicable repository instructions. Coordinate file ownership with active workers before editing.

## Existing runtime, not a mockup

Rust/Axum/Tokio stateless API, Flutter/Dart client with Android/iOS/web source projects. The complete three-step flow works against the loopback catalog/preview endpoints. Client holds choices in memory and paints symbolic plates. There are no uploaded photographs, generated meal images, accounts, stored health data, model calls or GPU jobs.

Do not rebuild the prototype in React/HTML or replace Rust with the research Python service. No new dependency is needed for the first UI pass. Keep v1 IDs/enums/schema and `illustrative_only` validation intact.

## Recommended first assignment

“Improve the existing Flutter UI using DESIGN.md P0/P1 and UI_ACCEPTANCE.md. Start with readable progress labels and responsive compact meal cards; retain optional preferences, exact selection constraints, error recovery and evidence disclosures. Extract reusable theme/components only as needed. Preserve all current API and privacy boundaries. Add targeted regression checks and capture all key screens at narrow width and large text. Run the extension checks. Report exact changes, test results, unresolved limits and next steps.”

This is a suggested task prompt, not a claim that these improvements are already implemented.

## File ownership for parallel work

- UI implementation: `mobile/lib/main.dart` and extracted theme/widgets; coordinate any `plate.dart` change with the UI owner.
- Tests/review: `mobile/test/` and this acceptance checklist; avoid simultaneous edits to the same tests.
- Backend: no changes required for visual P1. If necessary, a separate owner reviews `backend/`, `models.dart`, `api.dart` and contract tests together.
- Design/docs: DESIGN.md and tokens. Do not independently change token values while UI implementation is in flight.
- Integration owner reviews the combined diff and is the only worker to commit/push the agreed change set.

Do not edit coursework root files, `report/`, experiments, study/annotation service, inference code, frozen datasets, prompts or running GPU work for this UI task. Never overwrite user modifications, force-push, merge to main or publish a website/app as a side effect.

## Run and verify

From the app directory:

```sh
./scripts/check.sh
python3 scripts/smoke.py
```

For local visual work, follow README commands: API at `127.0.0.1:8787`, Flutter web at `127.0.0.1:5173`. The API intentionally does not bind to LAN/public addresses. Use only your own processes and clean them up when done. Recheck interrupted/repeated flows, not just the happy path.

Before calling the change ready:

- Run the final format, test, analyzer, Clippy and web-build checks. Report passed, failed and not-run separately.
- Run production Dart-to-Rust smoke if API/client contracts or request behavior changed; rerunning it for the integrated deliverable is preferred.
- Perform the relevant visual/keyboard/semantics checks in UI_ACCEPTANCE.md. New source screenshots and automated tests are not native VoiceOver/TalkBack evidence.
- Update docs/TESTING.md only with actually observed results, versions, viewport/text scale and limits. Do not copy an earlier pass as new verification.
- Inspect `git diff --check`, diff scope and staged files. Do not commit build/cache artifacts, credentials, photos, participant data or screenshots. Repository image rules also exclude generated meal images.
- Push only the intended app branch when covered by the task; verify the remote commit before reporting it. Do not open a PR or deploy without the applicable authorization.

## Completion report

Return: changed files and concise rationale; which P0/P1 criteria passed; test commands and outcomes; screenshots/artifact location if available; native/user-validation gaps; exact commit/verified branch link if pushed; one concrete next task. Never describe the symbolic preview as a completed AI edit, a nutrition calculation or demonstrated benefit for older adults.
