"""Security checks for the live-smoke GitHub Actions workflow (static)."""

from __future__ import annotations

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github" / "workflows" / "ai-bridge-live-smoke.yml"


@pytest.fixture(scope="module")
def wf() -> str:
    assert WORKFLOW.is_file(), f"missing workflow: {WORKFLOW}"
    return WORKFLOW.read_text(encoding="utf-8")


def test_workflow_dispatch_only(wf: str) -> None:
    assert "workflow_dispatch:" in wf
    for forbidden in ("pull_request:", "push:", "schedule:", "repository_dispatch:"):
        # Allow comments mentioning them; ban as YAML keys under on:
        assert f"\n  {forbidden}" not in wf.split("on:")[1].split("jobs:")[0]


def test_uses_production_environment(wf: str) -> None:
    assert "environment: production" in wf


def test_minimal_permissions(wf: str) -> None:
    assert "permissions:" in wf
    assert "contents: read" in wf
    # No write scopes
    for bad in ("contents: write", "pull-requests: write", "actions: write", "id-token: write"):
        assert bad not in wf


def _active_lines(wf: str) -> list[str]:
    """YAML lines that are not pure comments (inline comments still scanned)."""
    out: list[str] = []
    for line in wf.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        out.append(line)
    return out


def test_no_set_x(wf: str) -> None:
    active = "\n".join(_active_lines(wf))
    assert "set -x" not in active
    assert "set -o xtrace" not in active


def test_secret_not_echoed(wf: str) -> None:
    # Must reference secret, must not echo it.
    assert "secrets.CURSOR_API_KEY" in wf
    assert "echo \"$CURSOR_API_KEY\"" not in wf
    assert "echo ${{ secrets.CURSOR_API_KEY }}" not in wf


def test_confirm_gate(wf: str) -> None:
    assert "confirm_live" in wf
    assert "LIVE" in wf


def test_no_deploy_steps(wf: str) -> None:
    active = "\n".join(_active_lines(wf)).lower()
    assert "hetzner_ssh" not in active
    assert "ssh " not in active
    assert "appleboy/ssh-action" not in active
    assert "deploy-hetzner" not in active


def test_artifact_retention(wf: str) -> None:
    assert "scootercheck-cursor-live-smoke" in wf
    assert "retention-days: 7" in wf


def test_no_shell_input_injection(wf: str) -> None:
    # Inputs are constrained; must not pass freeform shell into run: scripts via eval.
    assert "eval " not in wf
    assert "${{ inputs." in wf  # starting_ref / max_polls / confirm used intentionally
    # Freeform shell command input must not exist
    assert "shell_command" not in wf
    assert "custom_script" not in wf


def test_concurrency_lock(wf: str) -> None:
    assert "concurrency:" in wf
    assert "cancel-in-progress: false" in wf
