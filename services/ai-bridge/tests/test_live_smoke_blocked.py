"""Live smoke without credentials must stay NOT VERIFIED."""

from __future__ import annotations

import json

from ai_bridge.run_live_smoke import main


def test_live_smoke_blocked_without_key(monkeypatch, tmp_path) -> None:
    monkeypatch.delenv("CURSOR_API_KEY", raising=False)
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    code = main()
    assert code == 2
    data = json.loads((tmp_path / "live_smoke_result.json").read_text(encoding="utf-8"))
    assert data["block"] == "BLOCKED_MISSING_CREDENTIAL"
    assert data["CURSOR_API_LIVE_VERIFIED"] is False
