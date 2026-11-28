from __future__ import annotations

import importlib
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

# Ensure `import app` works when pytest is started from repo root or backend/.
_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    db_path = tmp_path / "scootercheck-test.db"
    monkeypatch.setenv("DATABASE_PATH", str(db_path))
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret-not-for-prod")
    monkeypatch.setenv("JWT_EXPIRE_HOURS", "336")
    monkeypatch.setenv("ADMIN_EMAIL", "admin@example.com")
    monkeypatch.setenv("ADMIN_PASSWORD", "AdminPass123!")
    monkeypatch.setenv("ADMIN_NAME", "Test Admin")
    monkeypatch.setenv("CORS_ORIGINS", "*")

    # Settings/db/security/main capture env at import — reload after env is set.
    import app.settings as settings_mod

    importlib.reload(settings_mod)
    import app.db as db_mod

    importlib.reload(db_mod)
    import app.security as security_mod

    importlib.reload(security_mod)
    import app.errors as errors_mod

    importlib.reload(errors_mod)
    import app.main as main_mod

    importlib.reload(main_mod)

    main_mod.on_startup()
    with TestClient(main_mod.app) as test_client:
        yield test_client
