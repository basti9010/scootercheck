"""Live Cursor Cloud Agents smoke harness (AI Bridge 2.1).

Uses RealCursorClient only. Never prints CURSOR_API_KEY or Authorization headers.
CURSOR_API_LIVE_VERIFIED becomes true only after:
  1) POST /v1/agents returns a non-mock agent id, AND
  2) GET run/agent status for that id succeeds.

CURSOR_AGENT_COMPLETED is a separate flag (true only on FINISHED).
TIMEOUT leaves RESULT_STATUS=UNKNOWN while keeping the agent id.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ai_bridge.cursor_client import (
    RUN_TERMINAL,
    CursorAPIError,
    RealCursorClient,
    live_api_available,
    set_live_verified,
)
from ai_bridge.live_status import is_live_agent_id, is_mock_agent_id, map_cursor_run_to_report
from ai_bridge.models import CreateAgentRequest

SECRET_PATTERNS = (
    re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)\S+"),
    re.compile(r"(?i)(cursor_api_key\s*[:=]\s*)\S+"),
    re.compile(r"(?i)(api[_-]?key\s*[:=]\s*)\S+"),
)

HARMLESS_PROMPT = (
    "ScooterCheck AI Bridge live smoke (harmless verification).\n\n"
    "Erstelle im ScooterCheck-Repository eine Markdown-Datei unter "
    "research/ai-bridge-live-smoke/ mit einer kurzen technischen Dokumentation "
    "des erfolgreichen Cursor-API-Live-Tests.\n\n"
    "Verändere keine bestehenden produktiven Komponenten.\n"
    "Führe keine Deployments aus.\n"
    "Ändere keine Benutzerkonten, Secrets oder Sicherheitskonfigurationen.\n"
    "Wenn die Cursor-Plattform einen separaten Branch und Pull Request "
    "unterstützt, verwende diesen Weg."
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def redact(text: str) -> str:
    out = text
    for pat in SECRET_PATTERNS:
        out = pat.sub(r"\1[REDACTED]", out)
    return out


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def write_reports(out_dir: Path, result: dict[str, Any]) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "LIVE_RESULT.json"
    md_path = out_dir / "LIVE_RESULT.md"
    safe = json.loads(redact(json.dumps(result)))
    json_path.write_text(json.dumps(safe, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_path.write_text(_to_markdown(safe), encoding="utf-8")
    return json_path, md_path


def _to_markdown(result: dict[str, Any]) -> str:
    lines = [
        "# Cursor Live Smoke — LIVE_RESULT",
        "",
        f"- **timestamp:** `{result.get('timestamp')}`",
        f"- **repository:** `{result.get('repository')}`",
        f"- **workflow_run_id:** `{result.get('workflow_run_id')}`",
        f"- **workflow_commit:** `{result.get('workflow_commit')}`",
        f"- **cursor_agent_id:** `{result.get('cursor_agent_id')}`",
        f"- **cursor_run_id:** `{result.get('cursor_run_id')}`",
        f"- **cursor_api_status:** `{result.get('cursor_api_status')}`",
        f"- **final_status / RESULT_STATUS:** `{result.get('final_status')}`",
        f"- **start_time:** `{result.get('start_time')}`",
        f"- **end_time:** `{result.get('end_time')}`",
        f"- **branch:** `{result.get('branch')}`",
        f"- **pull_request:** `{result.get('pull_request')}`",
        f"- **CURSOR_API_LIVE_VERIFIED:** `{result.get('CURSOR_API_LIVE_VERIFIED')}`",
        f"- **CURSOR_AGENT_COMPLETED:** `{result.get('CURSOR_AGENT_COMPLETED')}`",
        f"- **errors:** `{result.get('errors')}`",
        "",
        "## Task",
        "",
        str(result.get("task_description") or ""),
        "",
        "## Test results",
        "",
        "```json",
        json.dumps(result.get("test_results") or {}, indent=2),
        "```",
        "",
    ]
    return "\n".join(lines) + "\n"


def _idempotency_path(out_dir: Path) -> Path:
    return out_dir / "idempotency_state.json"


def _load_idempotency(out_dir: Path, key: str) -> dict[str, Any] | None:
    path = _idempotency_path(out_dir)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    if data.get("idempotency_key") == key and data.get("cursor_agent_id"):
        return data
    return None


def _save_idempotency(out_dir: Path, key: str, agent_id: str, run_id: str | None) -> None:
    path = _idempotency_path(out_dir)
    payload = {
        "idempotency_key": key,
        "cursor_agent_id": agent_id,
        "cursor_run_id": run_id,
        "saved_at": utc_now(),
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def build_base_result(**kwargs: Any) -> dict[str, Any]:
    base = {
        "timestamp": utc_now(),
        "repository": os.environ.get("GITHUB_REPOSITORY", "basti9010/scootercheck"),
        "workflow_run_id": os.environ.get("GITHUB_RUN_ID"),
        "workflow_commit": os.environ.get("GITHUB_SHA"),
        "cursor_agent_id": None,
        "cursor_run_id": None,
        "cursor_api_status": None,
        "task_description": HARMLESS_PROMPT,
        "start_time": None,
        "end_time": None,
        "final_status": "UNKNOWN",
        "branch": None,
        "pull_request": None,
        "test_results": {},
        "errors": None,
        "CURSOR_API_LIVE_VERIFIED": False,
        "CURSOR_AGENT_COMPLETED": False,
        "endpoint": "POST https://api.cursor.com/v1/agents",
        "block": None,
    }
    base.update(kwargs)
    return base


def poll_until_terminal(
    client: RealCursorClient,
    agent_id: str,
    run_id: str,
    *,
    max_polls: int,
    poll_interval_s: float,
) -> tuple[Any, str, bool]:
    """Returns (run, report_status, timed_out)."""
    last = None
    for _ in range(max_polls):
        last = client.get_run(agent_id, run_id)
        if last.status in RUN_TERMINAL:
            return last, map_cursor_run_to_report(last.status), False
        if poll_interval_s > 0:
            time.sleep(poll_interval_s)
    # Timeout: do not claim FAILED — status unknown to us.
    return last, "TIMEOUT", True


def _default_out_dir() -> Path:
    override = os.environ.get("AI_BRIDGE_LIVE_EVIDENCE_DIR", "").strip()
    if override:
        return Path(override)
    # ai_bridge/run_live_smoke.py → repo root = parents[3]
    repo_root = Path(__file__).resolve().parents[3]
    research = repo_root / "research" / "ai-bridge-live-smoke"
    if research.parent.is_dir():
        return research
    return Path(__file__).resolve().parent.parent / "data" / "live_evidence"


def main() -> int:
    out_dir = _default_out_dir()

    max_polls = _env_int("AI_BRIDGE_LIVE_MAX_POLLS", 60)
    poll_interval = _env_float("AI_BRIDGE_LIVE_POLL_INTERVAL_S", 10.0)
    starting_ref = os.environ.get(
        "AI_BRIDGE_LIVE_STARTING_REF",
        os.environ.get("GITHUB_REF_NAME", "cursor/ai-bridge-v2-b100"),
    )
    repo_url = os.environ.get(
        "AI_BRIDGE_LIVE_REPO_URL", "https://github.com/basti9010/scootercheck"
    )
    idem_key = os.environ.get("AI_BRIDGE_LIVE_IDEMPOTENCY_KEY") or (
        f"gha-{os.environ.get('GITHUB_RUN_ID', 'local')}-"
        f"{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}"
    )
    resume_agent = os.environ.get("AI_BRIDGE_RESUME_AGENT_ID", "").strip() or None
    resume_run = os.environ.get("AI_BRIDGE_RESUME_RUN_ID", "").strip() or None

    start_time = utc_now()

    if not live_api_available():
        result = build_base_result(
            start_time=start_time,
            end_time=utc_now(),
            final_status="FAILED",
            block="BLOCKED_MISSING_CREDENTIAL",
            errors="CURSOR_API_KEY is not set",
            CURSOR_API_LIVE_VERIFIED=False,
            CURSOR_AGENT_COMPLETED=False,
        )
        write_reports(out_dir, result)
        print(json.dumps({k: result[k] for k in (
            "CURSOR_API_LIVE_VERIFIED", "CURSOR_AGENT_COMPLETED", "block", "endpoint", "final_status"
        )}, indent=2))
        return 2

    client = RealCursorClient.from_env()
    assert client is not None

    existing = _load_idempotency(out_dir, idem_key)
    agent_id = resume_agent or (existing or {}).get("cursor_agent_id")
    run_id = resume_run or (existing or {}).get("cursor_run_id")
    created_this_run = False

    try:
        if agent_id and is_live_agent_id(str(agent_id)):
            # Resume / idempotent path — do not POST /v1/agents again.
            if not run_id:
                agent = client.get_agent(str(agent_id))
                run_id = agent.latest_run_id
            if not run_id:
                raise CursorAPIError("Resume agent has no run id")
            # Prove status retrieval for LIVE_VERIFIED.
            client.get_run(str(agent_id), str(run_id))
        else:
            req = CreateAgentRequest(
                prompt_text=HARMLESS_PROMPT,
                repository_url=repo_url,
                starting_ref=starting_ref,
                name="scootercheck-ai-bridge-live-smoke",
                auto_create_pr=True,
            )
            agent, run = client.create_agent(req)
            agent_id = agent.id
            run_id = run.id
            created_this_run = True
            if is_mock_agent_id(agent_id):
                result = build_base_result(
                    start_time=start_time,
                    end_time=utc_now(),
                    cursor_agent_id=agent_id,
                    cursor_run_id=run_id,
                    cursor_api_status=run.status,
                    final_status="FAILED",
                    errors="Mock agent id returned in live mode",
                    block="MOCK_ID_IN_LIVE_MODE",
                )
                write_reports(out_dir, result)
                print(json.dumps({"CURSOR_API_LIVE_VERIFIED": False, "block": "MOCK_ID_IN_LIVE_MODE"}, indent=2))
                return 1
            if not is_live_agent_id(agent_id):
                result = build_base_result(
                    start_time=start_time,
                    end_time=utc_now(),
                    final_status="FAILED",
                    errors="Missing agent id from Cursor API",
                    block="MISSING_AGENT_ID",
                )
                write_reports(out_dir, result)
                return 1
            _save_idempotency(out_dir, idem_key, str(agent_id), str(run_id) if run_id else None)
            # Immediate status fetch — required for LIVE_VERIFIED.
            if run_id:
                client.get_run(str(agent_id), str(run_id))
            else:
                client.get_agent(str(agent_id))

        # At this point we have a real id and successful status retrieval.
        set_live_verified(True)
        live_verified = True

        run, report_status, timed_out = poll_until_terminal(
            client,
            str(agent_id),
            str(run_id),
            max_polls=max_polls,
            poll_interval_s=poll_interval,
        )

        branch = None
        pr_url = None
        if run and getattr(run, "git", None) and isinstance(run.git, dict):
            branches = run.git.get("branches") or []
            if branches and isinstance(branches[0], dict):
                branch = branches[0].get("branch")
            pr_url = run.git.get("pullRequestUrl") or run.git.get("prUrl")

        completed = report_status == "COMPLETED"
        final = "TIMEOUT" if timed_out else report_status
        # On timeout keep RESULT_STATUS semantics as UNKNOWN for operators.
        result_status = "UNKNOWN" if timed_out else final

        result = build_base_result(
            start_time=start_time,
            end_time=utc_now(),
            cursor_agent_id=agent_id,
            cursor_run_id=run_id,
            cursor_api_status=getattr(run, "status", None),
            final_status=result_status,
            branch=branch,
            pull_request=pr_url,
            CURSOR_API_LIVE_VERIFIED=live_verified,
            CURSOR_AGENT_COMPLETED=completed,
            test_results={
                "created_this_run": created_this_run,
                "idempotency_key": idem_key,
                "timed_out": timed_out,
                "poll_max": max_polls,
                "poll_interval_s": poll_interval,
                "run_result_excerpt": redact(str(getattr(run, "result", None) or ""))[:2000],
                "RESULT_STATUS": result_status,
            },
            errors=None if (completed or timed_out) else f"run_status={getattr(run, 'status', None)}",
            block=None,
        )
        write_reports(out_dir, result)
        print(
            json.dumps(
                {
                    "CURSOR_API_LIVE_VERIFIED": live_verified,
                    "CURSOR_AGENT_COMPLETED": completed,
                    "cursor_agent_id": agent_id,
                    "final_status": result_status,
                    "RESULT_STATUS": result_status,
                },
                indent=2,
            )
        )
        # Exit 0 if API verified (even if agent still running / timeout / failed task).
        # Exit 1 only for verified=false paths above.
        return 0
    except CursorAPIError as exc:
        result = build_base_result(
            start_time=start_time,
            end_time=utc_now(),
            cursor_agent_id=agent_id,
            cursor_run_id=run_id,
            final_status="FAILED",
            errors=redact(f"CursorAPIError status={exc.status_code} corr={exc.correlation_id}"),
            CURSOR_API_LIVE_VERIFIED=False,
            CURSOR_AGENT_COMPLETED=False,
            block="CURSOR_API_ERROR",
        )
        write_reports(out_dir, result)
        print(json.dumps({"CURSOR_API_LIVE_VERIFIED": False, "block": "CURSOR_API_ERROR"}, indent=2))
        return 1
    except Exception as exc:  # noqa: BLE001
        result = build_base_result(
            start_time=start_time,
            end_time=utc_now(),
            cursor_agent_id=agent_id,
            cursor_run_id=run_id,
            final_status="FAILED",
            errors=redact(f"{type(exc).__name__}"),
            CURSOR_API_LIVE_VERIFIED=False,
            CURSOR_AGENT_COMPLETED=False,
            block="UNEXPECTED_ERROR",
        )
        write_reports(out_dir, result)
        print(json.dumps({"CURSOR_API_LIVE_VERIFIED": False, "block": "UNEXPECTED_ERROR"}, indent=2))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
