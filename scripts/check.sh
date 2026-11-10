#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
cargo fmt --manifest-path backend/Cargo.toml --check
cargo test --manifest-path backend/Cargo.toml --locked
cargo clippy --manifest-path backend/Cargo.toml --all-targets --locked -- -D warnings
if [[ -z "${WORKER_SGEDIT_ROOT:-}" ]]; then
  echo "NOTE: WORKER_SGEDIT_ROOT is not set; the sgedit adapter contract tests will be skipped." >&2
fi
python3 -m unittest discover -s gpu-worker -p "test_*.py"
cd mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos
flutter test
flutter build web --release --no-web-resources-cdn
