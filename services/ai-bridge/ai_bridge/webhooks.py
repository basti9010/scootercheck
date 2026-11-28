"""Optional webhook handler stub for Cursor statusChange events (ERROR/FINISHED)."""

from __future__ import annotations

import logging
from typing import Any, Callable, Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


class StatusChangeEvent(BaseModel):
    event: str = "statusChange"
    agent_id: str = Field(alias="agentId")
    run_id: Optional[str] = Field(default=None, alias="runId")
    status: str
    timestamp: Optional[str] = None
    raw: Optional[dict[str, Any]] = None

    model_config = {"populate_by_name": True}


StatusChangeHandler = Callable[[StatusChangeEvent], None]


def handle_status_change(
    payload: dict[str, Any], *, on_event: Optional[StatusChangeHandler] = None
) -> StatusChangeEvent:
    event = StatusChangeEvent.model_validate({**payload, "raw": payload})
    if event.status not in ("ERROR", "FINISHED"):
        logger.info(
            "webhook statusChange ignored (not ERROR/FINISHED): agent=%s status=%s",
            event.agent_id,
            event.status,
        )
    else:
        logger.info(
            "webhook statusChange: agent=%s run=%s status=%s",
            event.agent_id,
            event.run_id,
            event.status,
        )
    if on_event is not None:
        on_event(event)
    return event
