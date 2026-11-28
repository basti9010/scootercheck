"""Fail-closed startup when JWT/admin secrets are insecure defaults."""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _reload_settings(monkeypatch: pytest.MonkeyPatch, **env: str):
    for key in (
        "DATABASE_PATH",
        "JWT_SECRET",
        "ADMIN_PASSWORD",
        "ADMIN_EMAIL",
        "ALLOW_INSECURE_AUTH_DEFAULTS",
    ):
        monkeypatch.delenv(key, raising=False)
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    import app.settings as settings_mod

    importlib.reload(settings_mod)
    return settings_mod.settings


def test_refuses_insecure_defaults(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    s = _reload_settings(
        monkeypatch,
        DATABASE_PATH=str(tmp_path / "x.db"),
        JWT_SECRET="change-me-in-production",
        ADMIN_PASSWORD="change-me",
    )
    with pytest.raises(RuntimeError, match="fail-closed"):
        s.assert_secure_configuration()


def test_accepts_strong_secrets(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    s = _reload_settings(
        monkeypatch,
        DATABASE_PATH=str(tmp_path / "x.db"),
        JWT_SECRET="strong-jwt-secret-for-tests-only",
        ADMIN_PASSWORD="StrongAdminPass123!",
    )
    s.assert_secure_configuration()  # must not raise


def test_allow_insecure_opt_in(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    s = _reload_settings(
        monkeypatch,
        DATABASE_PATH=str(tmp_path / "x.db"),
        JWT_SECRET="change-me",
        ADMIN_PASSWORD="change-me",
        ALLOW_INSECURE_AUTH_DEFAULTS="1",
    )
    s.assert_secure_configuration()
