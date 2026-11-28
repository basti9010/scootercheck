"""Task domain models aligned with schemas/task.schema.json."""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional
from uuid import uuid4

from pydantic import BaseModel, Field


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


class TaskStatus(str, Enum):
    CREATED = "CREATED"
    VALIDATING = "VALIDATING"
    PLANNED = "PLANNED"
    WAITING_FOR_APPROVAL = "WAITING_FOR_APPROVAL"
    QUEUED = "QUEUED"
    RUNNING = "RUNNING"
    TESTING = "TESTING"
    REVIEW = "REVIEW"
    BLOCKED = "BLOCKED"
    FAILED = "FAILED"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class TaskPriority(str, Enum):
    P0 = "P0"
    P1 = "P1"
    P2 = "P2"
    P3 = "P3"


class TaskSource(str, Enum):
    CHATGPT = "chatgpt"
    MCP = "mcp"
    CLI = "cli"
    API = "api"
    MANUAL = "manual"
    AUTOMATION = "automation"


class SecurityClassification(str, Enum):
    PUBLIC = "public"
    INTERNAL = "internal"
    CONFIDENTIAL = "confidential"
    RESTRICTED = "restricted"


class EstimatedComplexity(str, Enum):
    XS = "XS"
    S = "S"
    M = "M"
    L = "L"
    XL = "XL"


class ApprovalStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    source: TaskSource = TaskSource.API
    repository: str = Field(min_length=1)
    base_branch: str = Field(min_length=1)
    priority: TaskPriority = TaskPriority.P2
    requirements: list[str] = Field(default_factory=list)
    acceptance_criteria: list[str] = Field(default_factory=list)
    affected_components: list[str] = Field(default_factory=list)
    assigned_agents: list[str] = Field(default_factory=list)
    dependencies: list[str] = Field(default_factory=list)
    security_classification: SecurityClassification = SecurityClassification.INTERNAL
    estimated_complexity: EstimatedComplexity = EstimatedComplexity.M
    idempotency_key: str = Field(min_length=1)
    correlation_id: Optional[str] = None
    requested_by: Optional[str] = None
    approval_required: bool = False


class Task(BaseModel):
    task_id: str
    title: str
    description: str
    source: TaskSource
    repository: str
    base_branch: str
    priority: TaskPriority
    requirements: list[str] = Field(default_factory=list)
    acceptance_criteria: list[str] = Field(default_factory=list)
    affected_components: list[str] = Field(default_factory=list)
    assigned_agents: list[str] = Field(default_factory=list)
    dependencies: list[str] = Field(default_factory=list)
    security_classification: SecurityClassification = SecurityClassification.INTERNAL
    estimated_complexity: EstimatedComplexity = EstimatedComplexity.M
    status: TaskStatus = TaskStatus.CREATED
    created_at: str
    updated_at: str
    idempotency_key: str
    correlation_id: Optional[str] = None
    requested_by: Optional[str] = None
    approval_required: bool = False
    approval_status: Optional[ApprovalStatus] = None
    plan: Optional[dict[str, Any]] = None
    cursor_agent_id: Optional[str] = None
    cursor_run_id: Optional[str] = None
    error_message: Optional[str] = None
    report_path: Optional[str] = None

    @classmethod
    def from_create(cls, payload: TaskCreate, *, task_id: Optional[str] = None) -> "Task":
        now = utc_now_iso()
        approval_status = ApprovalStatus.PENDING if payload.approval_required else None
        return cls(
            task_id=task_id or f"task-{uuid4()}",
            title=payload.title,
            description=payload.description,
            source=payload.source,
            repository=payload.repository,
            base_branch=payload.base_branch,
            priority=payload.priority,
            requirements=list(payload.requirements),
            acceptance_criteria=list(payload.acceptance_criteria),
            affected_components=list(payload.affected_components),
            assigned_agents=list(payload.assigned_agents),
            dependencies=list(payload.dependencies),
            security_classification=payload.security_classification,
            estimated_complexity=payload.estimated_complexity,
            status=TaskStatus.CREATED,
            created_at=now,
            updated_at=now,
            idempotency_key=payload.idempotency_key,
            correlation_id=payload.correlation_id,
            requested_by=payload.requested_by,
            approval_required=payload.approval_required,
            approval_status=approval_status,
        )


class CreateAgentRequest(BaseModel):
    prompt_text: str
    repository_url: Optional[str] = None
    starting_ref: Optional[str] = None
    model_id: Optional[str] = None
    name: Optional[str] = None
    auto_create_pr: bool = False


class AgentInfo(BaseModel):
    id: str
    name: str
    status: str
    latest_run_id: Optional[str] = None
    url: Optional[str] = None


class RunInfo(BaseModel):
    id: str
    agent_id: str
    status: str
    result: Optional[str] = None
    duration_ms: Optional[int] = None
    git: Optional[dict[str, Any]] = None
