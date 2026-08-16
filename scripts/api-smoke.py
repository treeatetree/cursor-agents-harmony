#!/usr/bin/env python3
"""Local API contract smoke simulating the Harmony app call chain."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = "https://api.cursor.com"
KEY = os.environ.get("CURSOR_API_KEY", "").strip()


def req(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    data = None if body is None else json.dumps(body).encode()
    r = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {KEY}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "CursorHarmonyNative/1.0-smoke",
        },
    )
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return e.code, payload


def unwrap_agents(d: dict) -> list:
    return d.get("items") or d.get("agents") or []


def unwrap_run(d: dict) -> dict:
    return d.get("run") or d


def main() -> int:
    if not KEY:
        print("SKIP: set CURSOR_API_KEY to run live smoke")
        return 0

    code, me = req("GET", "/v1/me")
    assert code == 200, me
    assert me.get("userEmail") or me.get("apiKeyName")
    print("ok me", me.get("apiKeyName"), me.get("userEmail"))

    code, agents = req("GET", "/v1/agents?limit=5")
    assert code == 200, agents
    items = unwrap_agents(agents)
    assert isinstance(items, list)
    print("ok agents", len(items), "nextCursor", bool(agents.get("nextCursor")))
    assert items, "need at least one agent"
    agent_id = items[0]["id"]

    code, agent = req("GET", f"/v1/agents/{agent_id}")
    assert code == 200 and agent.get("id")
    print("ok agent", agent.get("name"), "repos", len(agent.get("repos") or []))

    code, runs = req("GET", f"/v1/agents/{agent_id}/runs?limit=3")
    assert code == 200
    run_items = runs.get("items") or runs.get("runs") or []
    print("ok runs", len(run_items))
    if run_items:
        rid = run_items[0]["id"]
        code, run = req("GET", f"/v1/agents/{agent_id}/runs/{rid}")
        assert code == 200 and run.get("id")
        print("ok getRun", run.get("status"))

    code, models = req("GET", "/v1/models")
    assert code == 200
    mitems = models.get("items") or models.get("models") or []
    assert mitems
    print("ok models", len(mitems))

    code, repos = req("GET", "/v1/repositories")
    assert code == 200
    ritems = repos.get("items") or repos.get("repositories") or []
    print("ok repos", len(ritems))

    code, _arts = req("GET", f"/v1/agents/{agent_id}/artifacts")
    print("artifacts HTTP", code)

    code, _usage = req("GET", f"/v1/agents/{agent_id}/usage")
    print("usage HTTP", code)

    code, created = req(
        "POST",
        f"/v1/agents/{agent_id}/runs",
        {"prompt": {"text": "smoke: reply only ok-smoke"}},
    )
    assert code in (200, 201), created
    run = unwrap_run(created)
    assert run.get("id"), created
    print("ok createRun keys", list(created.keys()), "id", run.get("id"))

    # Local unwrap unit checks (no device)
    assert unwrap_agents({"agents": [{"id": "x"}]})[0]["id"] == "x"
    assert unwrap_run({"run": {"id": "r1"}}).get("id") == "r1"

    print("SMOKE PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print("SMOKE FAIL", e)
        raise SystemExit(1)
