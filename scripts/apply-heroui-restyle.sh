#!/usr/bin/env bash
# Apply the HeroUI restyle onto the CURRENT branch (no git checkout / no full fetch).
# Usage: ./scripts/apply-heroui-restyle.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PATCH="$ROOT/scripts/heroui-restyle.patch"
if [[ ! -f "$PATCH" ]]; then
  echo "Missing $PATCH"
  exit 1
fi

echo "==> Applying HeroUI restyle patch onto $(git rev-parse --abbrev-ref HEAD)"
if git apply --check "$PATCH" 2>/tmp/heroui-apply.err; then
  git apply "$PATCH"
  echo "OK: patch applied."
else
  echo "Clean apply failed, trying 3-way..."
  git apply --3way "$PATCH" || {
    echo "FAILED. Your tree is too far from the previous native client."
    echo "Do NOT git checkout the full cloud branch (it hangs)."
    echo "Open a new terminal and copy these 19 files from the PR instead."
    cat /tmp/heroui-apply.err || true
    exit 1
  }
  echo "OK: patch applied with 3-way merge."
fi
git status -sb
