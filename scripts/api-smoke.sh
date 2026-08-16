#!/usr/bin/env bash
# Local API contract smoke — simulates App call chain against api.cursor.com
# Usage: CURSOR_API_KEY=crsr_... ./scripts/api-smoke.sh
set -euo pipefail
KEY="${CURSOR_API_KEY:-}"
if [[ -z "$KEY" ]]; then
  echo "SKIP: set CURSOR_API_KEY to run live smoke"
  exit 0
fi
BASE=https://api.cursor.com
HDR=(-H "Authorization: Bearer $KEY" -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: CursorHarmonyNative/1.0-smoke")

echo "== me =="
ME=$(curl -sS "${HDR[@]}" "$BASE/v1/me")
echo "$ME" | python3 -c "import sys,json;d=json.load(sys.stdin); assert d.get('userEmail') or d.get('apiKeyName'); print('ok', d.get('apiKeyName'))"

echo "== agents =="
AGENTS=$(curl -sS "${HDR[@]}" "$BASE/v1/agents?limit=5")
python3 - <<PY
import json,os
d=json.loads('''$AGENTS'''.replace("'''","'"))
items=d.get('items') or d.get('agents') or []
assert isinstance(items,list)
print('ok agents', len(items), 'cursor', bool(d.get('nextCursor')))
open('/tmp/hm_smoke_agent.txt','w').write(items[0]['id'] if items else '')
PY
AGENT=$(cat /tmp/hm_smoke_agent.txt)
[[ -n "$AGENT" ]] || { echo "no agents"; exit 1; }

echo "== agent $AGENT =="
curl -sS "${HDR[@]}" "$BASE/v1/agents/$AGENT" | python3 -c "import sys,json;d=json.load(sys.stdin); assert d.get('id'); print('ok', d.get('name'), 'repos', len(d.get('repos') or []))"

echo "== runs =="
RUNS=$(curl -sS "${HDR[@]}" "$BASE/v1/agents/$AGENT/runs?limit=3")
python3 - <<PY
import json
d=json.loads('''$RUNS'''.replace("'''","'"))
items=d.get('items') or d.get('runs') or []
assert isinstance(items,list)
print('ok runs', len(items))
open('/tmp/hm_smoke_run.txt','w').write(items[0]['id'] if items else '')
PY
RUN=$(cat /tmp/hm_smoke_run.txt)

if [[ -n "$RUN" ]]; then
  echo "== get run $RUN =="
  curl -sS "${HDR[@]}" "$BASE/v1/agents/$AGENT/runs/$RUN" | python3 -c "import sys,json;d=json.load(sys.stdin); assert d.get('id'); print('ok status', d.get('status'))"
fi

echo "== models =="
curl -sS "${HDR[@]}" "$BASE/v1/models" | python3 -c "import sys,json;d=json.load(sys.stdin);items=d.get('items') or d.get('models') or []; assert items; print('ok models', len(items), 'variants?', bool(items[0].get('variants') or items[0].get('parameters')))"

echo "== repos =="
curl -sS "${HDR[@]}" "$BASE/v1/repositories" | python3 -c "import sys,json;d=json.load(sys.stdin);items=d.get('items') or d.get('repositories') or []; print('ok repos', len(items))"

echo "== artifacts (best-effort) =="
curl -sS -o /tmp/hm_arts.json -w "%{http_code}" "${HDR[@]}" "$BASE/v1/agents/$AGENT/artifacts" > /tmp/hm_arts_code.txt || true
CODE=$(cat /tmp/hm_arts_code.txt)
echo "artifacts HTTP $CODE"

echo "== usage (best-effort) =="
curl -sS -o /tmp/hm_usage.json -w "%{http_code}" "${HDR[@]}" "$BASE/v1/agents/$AGENT/usage" > /tmp/hm_usage_code.txt || true
echo "usage HTTP $(cat /tmp/hm_usage_code.txt)"

echo "== createRun unwrap shape =="
CREATE=$(curl -sS -X POST "${HDR[@]}" "$BASE/v1/agents/$AGENT/runs" -d '{"prompt":{"text":"smoke: reply only ok-smoke"}}')
python3 - <<PY
import json
d=json.loads('''$CREATE'''.replace("'''","'"))
run=d.get('run') or d
assert run.get('id'), d
print('ok createRun keys', list(d.keys()), 'id', run.get('id'))
PY

echo "SMOKE PASS"
