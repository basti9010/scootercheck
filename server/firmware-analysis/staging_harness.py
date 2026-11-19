"""Isolated staging harness for Phase 2.2H (no production paths).

Creates a temporary work tree with its own WORK_DIR / stores / tokens.
Does not touch /var/lib/scootercheck.
"""
from __future__ import annotations

import os
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


def staging_env(
    root: Path | None = None,
    *,
    enable_ghidra: bool = False,
    jwt_secret: str = "staging-jwt-secret-not-prod",
    api_token: str = "staging-api-token",
    admin_token: str = "staging-admin-token",
) -> dict[str, str]:
    base = Path(root) if root else Path(tempfile.mkdtemp(prefix="scootercheck-staging-"))
    base.mkdir(parents=True, exist_ok=True)
    work = base / "jobs"
    plain = base / "plaintext"
    decomp = base / "decompiled"
    stock = base / "stock-fw"
    catalogs = base / "catalogs"
    for d in (work, plain, decomp, stock, catalogs):
        d.mkdir(parents=True, exist_ok=True)
    return {
        "WORK_DIR": str(work),
        "PLAINTEXT_STORE": str(plain),
        "DECOMPILE_STORE": str(decomp),
        "STOCK_FW_DIR": str(stock),
        "STOCK_CATALOG_DIR": str(catalogs),
        "STOCK_CATALOG_BATCH_DIR": str(base / "catalog-batch"),
        "API_TOKEN": api_token,
        "ADMIN_API_TOKEN": admin_token,
        "API_TOKEN_GRANTS_ADMIN": "0",
        "JWT_SECRET": jwt_secret,
        "JWT_ALGORITHM": "HS256",
        "ENABLE_GHIDRA": "1" if enable_ghidra else "0",
        "ENABLE_R2": "0",
        "ENABLE_ANGR": "0",
        "ENABLE_FSM_RUNTIME": "1",
        "HOST": "127.0.0.1",
        "PORT": "18088",
    }


@contextmanager
def apply_env(env: dict[str, str]) -> Iterator[dict[str, str | None]]:
    prev = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        yield prev
    finally:
        for k, v in prev.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def reload_app_modules() -> Any:
    """Reload app + auth modules after env change (for TestClient)."""
    import importlib

    import analysis_profile
    import ble_container
    import job_auth
    import stock_diff
    import app as app_mod

    importlib.reload(analysis_profile)
    importlib.reload(ble_container)
    importlib.reload(stock_diff)
    importlib.reload(job_auth)
    importlib.reload(app_mod)
    return app_mod


def health_snapshot(app_mod: Any) -> dict[str, Any]:
    client = __import__("fastapi.testclient", fromlist=["TestClient"]).TestClient(app_mod.APP)
    r = client.get("/health")
    return {"status_code": r.status_code, "body": r.json()}
