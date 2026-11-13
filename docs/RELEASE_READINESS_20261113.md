# App release gates: 13 November 2026

Reviewed source base: Spark 34731cb, v0.2.0. Mac research app worktree 06d37a3 is
older and distinct. GitHub main/production were 798cc51 at this check; APK branch
129a79c publishes v0.2 artifacts, not a source merge. This isolated branch preserves
v0.2 source with validation fixes. It does not deploy or promote production.

## Runtime observed
Gateway 8788 responds healthy; real worker8793 reports photo_ready=true,
gpu_ready=false. Old gateway8787/worker8791 remain a separate dry-run deployment.
Health is not an inference or external-phone connectivity test.

## Prioritized gates
1. Run exact-revision tests and disclose skips; reconcile source before promotion.
2. Test authorized authenticated photo upload from the intended client. Do not
   expose internal FoodSG fixtures or credentials.
3. Verify physical Android/iPhone camera/gallery, painting, cancellation, retry,
   background/resume and slow/offline flows. Historical simulator builds do not
   verify v0.2 uploads. Android scaffold still uses debug release signing.
4. Choose per-user access, quotas, TLS/domain, retention, monitoring and rollback.
   A shared client token is not production user authentication.
5. Measure cold/warm latency and concurrent requests on development photos.
   Single-worker configuration and bounded timeouts need clear busy/timeout UX.
6. Human naturalness/preservation acceptance remains necessary. Qwen pass is not
   a brown-rice-quality or nutrition certificate. Compare preservation-first
   alternatives separately; never modify frozen coursework data or scores.

## Scope
Flutter client, Rust gateway and Python worker form the separate app. Research
repository and annotation portal are different systems. No deployment, model
run, parameter change or frozen-study edit occurs in this branch. Keep datasets,
weights, credentials, private photos and generated builds outside source.

## Promotion
Review diff from main and validation tests, run predeploy-check.sh in isolation,
and obtain deployment authorization before moving production. Keep a rollback
revision and preserve other authors' work.

## Verification of this handoff
- scripts/check.sh passed: Rust 26 integration tests, formatting and Clippy;
  Flutter analysis, 47 tests and release web build.
- Default Python discovery ran 29 tests, skipping 19 research-adapter tests.
  Independent CPU-only run of the same worker patch with WORKER_SGEDIT_ROOT
  and the installed research environment passed all 29 (no skips).
- scripts/smoke.py passed using its own ephemeral gateway/dry-run worker ports.
- git diff --check passed. Tracked-path/private-key/common-token scans found
  no matching secret indicators; this is a bounded scan, not a security audit.
- Web build warns about an unavailable Cupertino icon font; no build failure.
- No native-device, public upload or real-inference quality test was run here.
