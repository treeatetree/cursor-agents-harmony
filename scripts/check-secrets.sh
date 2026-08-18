#!/usr/bin/env bash
# Fail if tracked files contain signing passwords, API keys, or personal home paths.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

scan() {
  local pattern="$1"
  local label="$2"
  local hits
  hits="$(git grep -nE "$pattern" -- \
    ':!build-profile.local.json5.example' \
    ':!scripts/check-secrets.sh' \
    ':!.cursor/**' \
    ':!designs/**' \
    ':!**/*.md' \
    || true)"
  if [[ -n "$hits" ]]; then
    echo "SECRET SCAN FAIL: $label"
    echo "$hits"
    fail=1
  fi
}

scan 'keyPassword[[:space:]]*:[[:space:]]*"[0-9A-Fa-f]{16,}"' 'signing keyPassword'
scan 'storePassword[[:space:]]*:[[:space:]]*"[0-9A-Fa-f]{16,}"' 'signing storePassword'
scan 'crsr_[A-Za-z0-9]{8,}' 'Cursor API key'
scan '/Users/[A-Za-z0-9._-]+/' 'personal absolute path'

if [[ -f build-profile.json5 ]]; then
  if git grep -q 'keyPassword\|storePassword\|/Users/' -- build-profile.json5; then
    echo "SECRET SCAN FAIL: committed build-profile.json5 still has secrets or home paths"
    fail=1
  fi
fi

if [[ $fail -ne 0 ]]; then
  echo "Move signing material to gitignored build-profile.local.json5 and rotate leaked credentials."
  exit 1
fi

echo "secret scan clean"
