from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Allow `import mcp...` via package path services/ai-bridge
ROOT = Path(__file__).resolve().parents[2]  # services/ai-bridge
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from mcp.auth import Principal, TokenRegistry  # noqa: E402
from mcp.orchestrator_stubs import MockOrchestrator  # noqa: E402
from mcp.roles import Role  # noqa: E402
from mcp.tools import ToolDispatcher  # noqa: E402


@pytest.fixture
def registry() -> TokenRegistry:
    reg = TokenRegistry()
    reg.register("tok_read", Principal(subject="reader", role=Role.READ))
    reg.register("tok_write", Principal(subject="writer", role=Role.TASK_WRITE))
    reg.register("tok_approval", Principal(subject="approver", role=Role.APPROVAL))
    reg.register("tok_admin", Principal(subject="admin", role=Role.ADMIN))
    return reg


@pytest.fixture
def dispatcher(registry: TokenRegistry) -> ToolDispatcher:
    return ToolDispatcher(registry, MockOrchestrator())
