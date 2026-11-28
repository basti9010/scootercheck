"""Live Cursor smoke — only succeeds with CURSOR_API_KEY and a real agent id.

Never prints the API key. Sets CURSOR_API_LIVE_VERIFIED only after a real
POST /v1/agents returns an agent id that is not a mock prefix.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from ai_bridge.cursor_client import (
    CURSOR_API_LIVE_VERIFIED,
    RealCursorClient,
    live_api_available,
    set_live_verified,
)
from ai_bridge.models import CreateAgentRequest


def main() -> int:
    out_dir = Path(
        os.environ.get(
            "AI_BRIDGE_LIVE_EVIDENCE_DIR",
            str(Path(__file__).resolve().parent.parent / "data" / "live_evidence"),
        )
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = out_dir / "live_smoke_result.json"

    if not live_api_available():
        result = {
            "CURSOR_API_LIVE_VERIFIED": False,
            "block": "BLOCKED_MISSING_CREDENTIAL",
            "message": (
                "CURSOR_API_KEY is not set in this process. Place it only in the "
                "server EnvironmentFile / secret store (never git, iOS, or dashboard JS)."
            ),
            "endpoint": "POST https://api.cursor.com/v1/agents",
        }
        evidence_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, indent=2))
        return 2

    client = RealCursorClient.from_env()
    assert client is not None
    req = CreateAgentRequest(
        prompt_text=(
            "ScooterCheck AI Bridge live smoke (harmless). "
            "Create research/ai-bridge-v2/LIVE_SMOKE_NOTE.md with a short note that "
            "the Cloud Agents API was reached. Do not change application code. "
            "Prepare a PR if appropriate."
        ),
        repository_url="https://github.com/basti9010/scootercheck",
        starting_ref="cursor/ai-bridge-v2-b100",
        name="ai-bridge-live-smoke",
        auto_create_pr=True,
    )
    agent, run = client.create_agent(req)
    verified = bool(agent.id) and not str(agent.id).startswith("bc-mock-")
    set_live_verified(verified)
    # Re-read module flag
    from ai_bridge import cursor_client as cc

    result = {
        "CURSOR_API_LIVE_VERIFIED": cc.CURSOR_API_LIVE_VERIFIED,
        "block": None if verified else "LIVE_CALL_DID_NOT_VERIFY",
        "endpoint": "POST https://api.cursor.com/v1/agents",
        "cursor_agent_id": agent.id,
        "cursor_run_id": run.id,
        "agent_status": agent.status,
        "run_status": run.status,
        "agent_url": agent.url,
    }
    evidence_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if verified else 1


if __name__ == "__main__":
    raise SystemExit(main())
