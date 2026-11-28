"""CLI: run one mock vertical slice and print the report path."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from ai_bridge.cursor_client import CURSOR_API_LIVE_VERIFIED, MockCursorClient
from ai_bridge.models import TaskCreate, TaskPriority, TaskSource
from ai_bridge.orchestrator import TaskOrchestrator
from ai_bridge.store import TaskStore


def main() -> int:
    root = Path(__file__).resolve().parent.parent / "data"
    store = TaskStore(root)
    orch = TaskOrchestrator(store, client=MockCursorClient())
    payload = TaskCreate(
        title="Mock E2E CLI",
        description="Development Automation Etappe 1–3 mock vertical slice",
        source=TaskSource.CLI,
        repository="https://github.com/basti9010/scootercheck",
        base_branch="cursor/development-automation-b100",
        priority=TaskPriority.P2,
        requirements=["mock only"],
        acceptance_criteria=["COMPLETED", "CURSOR_API_LIVE_VERIFIED false"],
        idempotency_key="cli-mock-e2e",
    )
    report = orch.run_vertical(payload)
    print(json.dumps(report, indent=2))
    print(
        f"\nCURSOR_API_LIVE_VERIFIED={CURSOR_API_LIVE_VERIFIED} "
        "(must stay false for mock)"
    )
    assert report["status"] == "COMPLETED"
    assert CURSOR_API_LIVE_VERIFIED is False
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
