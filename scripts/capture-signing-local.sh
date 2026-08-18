#!/usr/bin/env bash
# After DevEco "Automatically generate signature" writes into tracked
# build-profile.json5, scoop secrets into the gitignored overlay and restore
# the committed empty profile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! grep -q 'keyPassword' "$ROOT/build-profile.json5"; then
  echo "Tracked build-profile.json5 has no signing secrets."
  echo "If DevEco wrote somewhere else, copy that file to build-profile.local.json5 yourself."
  exit 0
fi

stamp="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$ROOT/build-profile.local.json5" ]]; then
  cp "$ROOT/build-profile.local.json5" "$ROOT/build-profile.local.json5.bak.$stamp"
  echo "==> backed up previous overlay to build-profile.local.json5.bak.$stamp"
fi

cp "$ROOT/build-profile.json5" "$ROOT/build-profile.local.json5"
python3 - <<'PY'
from pathlib import Path
p = Path('build-profile.local.json5')
t = p.read_text()
if '"signingConfig": "default"' not in t:
    old = '''      {
        "name": "default",
        "compatibleSdkVersion":'''
    new = '''      {
        "name": "default",
        "signingConfig": "default",
        "compatibleSdkVersion":'''
    if old not in t:
        raise SystemExit('could not bind signingConfig to product default')
    p.write_text(t.replace(old, new, 1))
    print('==> bound product default to signingConfig default')
PY
git checkout -- "$ROOT/build-profile.json5"
echo "==> wrote gitignored build-profile.local.json5 and restored tracked profile"
echo "Next: ./scripts/build.sh"
echo "Signature change usually needs: hdc uninstall com.brian.cursor.mobile"
echo "(HUKS 里的 API Key 可能要重贴)"
