"""CI AutoFix engine — prepares correction tasks; never loops unbounded."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .classifier import (
    MAX_ATTEMPTS_PER_FINGERPRINT,
    FailureClass,
    classify,
    fingerprint,
)


@dataclass
class AutoFixDecision:
    action: str  # prepare_task | blocked | ignore
    failure_class: FailureClass
    fingerprint: str
    attempts: int
    reason: str
    task_payload: dict[str, Any] | None = None


@dataclass
class AutoFixHistory:
    attempts: dict[str, int] = field(default_factory=dict)
    last_outcome: dict[str, str] = field(default_factory=dict)

    def record(self, fp: str, outcome: str) -> None:
        self.attempts[fp] = self.attempts.get(fp, 0) + 1
        self.last_outcome[fp] = outcome


FORBIDDEN_AUTO_TARGETS = frozenset(
    {
        "production-secrets",
        "branch-protection",
        "auth-bypass",
        "github-permissions",
        "security-check-disable",
    }
)


def evaluate_failure(
    *,
    workflow: str,
    commit: str,
    log_text: str,
    history: AutoFixHistory,
) -> AutoFixDecision:
    failure_class = classify(log_text)
    fp = fingerprint(workflow, commit, failure_class, log_text)
    attempts = history.attempts.get(fp, 0)
    if attempts >= MAX_ATTEMPTS_PER_FINGERPRINT:
        return AutoFixDecision(
            action="blocked",
            failure_class=failure_class,
            fingerprint=fp,
            attempts=attempts,
            reason=f"max {MAX_ATTEMPTS_PER_FINGERPRINT} attempts reached for fingerprint",
        )
    if history.last_outcome.get(fp) == "same_patch_failed":
        return AutoFixDecision(
            action="blocked",
            failure_class=failure_class,
            fingerprint=fp,
            attempts=attempts,
            reason="identical unsuccessful repair must not be repeated",
        )
    payload = {
        "title": f"AutoFix: {failure_class.value}",
        "description": f"Controlled autofix for workflow={workflow} commit={commit}",
        "approval_required": True,
        "security_classification": "internal",
        "requirements": [
            "Reproduce failure from CI log excerpt",
            "Minimal fix only",
            "Do not touch production secrets, branch protection, or auth bypasses",
        ],
        "meta": {
            "failure_class": failure_class.value,
            "fingerprint": fp,
            "forbidden_targets": sorted(FORBIDDEN_AUTO_TARGETS),
        },
    }
    return AutoFixDecision(
        action="prepare_task",
        failure_class=failure_class,
        fingerprint=fp,
        attempts=attempts,
        reason="eligible for bounded autofix task",
        task_payload=payload,
    )
