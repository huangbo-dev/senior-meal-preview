#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# The reference photos are kept out of Git (*.jpg is ignored), so a fresh checkout builds an app
# whose meal cards all read "Photo unavailable". Fail before building instead. See ATTRIBUTION.md.
for photo in chicken_rice fish_soup tofu_rice; do
  if [[ ! -s "mobile/assets/meals/$photo.jpg" ]]; then
    echo "ERROR: mobile/assets/meals/$photo.jpg is missing. Copy the three licensed reference" >&2
    echo "photos listed in mobile/assets/meals/ATTRIBUTION.md before building." >&2
    exit 1
  fi
done
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
