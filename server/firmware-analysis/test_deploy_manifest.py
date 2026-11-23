"""Pure offline checks for CD deploy manifest + release config validation.

Runnable without Hetzner, secrets, Ghidra, or ninebottea.
Compatible with pytest (CI) and unittest.
"""
from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
DEPLOY_DIR = APP_DIR / "deploy"
MANIFEST = DEPLOY_DIR / "deploy-manifest.txt"
ENV_EXAMPLE = APP_DIR / ".env.example"
APP_PY = APP_DIR / "app.py"
VALIDATE_SH = DEPLOY_DIR / "validate-release-config.sh"

C11_DIAGNOSTICS = (
    "diagnostics_models.py",
    "diagnostics_status.py",
    "diagnostics_tea.py",
    "diagnostics_ghidra.py",
    "diagnostics_routes.py",
)

CRITICAL_ENV_KEYS = (
    "API_TOKEN",
    "ADMIN_API_TOKEN",
    "API_TOKEN_GRANTS_ADMIN",
    "TRUST_API_TOKEN_CLIENT_ID",
    "JWT_SECRET",
    "JWT_ALGORITHM",
    "DECRYPT_CMD",
    "WORK_DIR",
    "PLAINTEXT_STORE",
    "DECOMPILE_STORE",
    "STOCK_FW_DIR",
    "GHIDRA_HOME",
    "ENABLE_GHIDRA",
    "HOST",
    "PORT",
    "ENABLE_ANGR",
    "ANGR_MAX_BYTES",
    "ANGR_TIMEOUT_SEC",
    "ANGR_MEM_MB",
    "ANGR_CFG_DEPTH",
    "ANGR_SYMBOLIC",
)

APP_CRITICAL_GETENV = (
    "API_TOKEN",
    "ADMIN_API_TOKEN",
    "JWT_SECRET",
    "JWT_ALGORITHM",
    "DECRYPT_CMD",
    "WORK_DIR",
    "PLAINTEXT_STORE",
    "DECOMPILE_STORE",
    "ENABLE_GHIDRA",
    "ANGR_TIMEOUT_SEC",
    "ANGR_MEM_MB",
    "ANGR_CFG_DEPTH",
    "ANGR_SYMBOLIC",
)

REQUIRED_RUNTIME = [
    "app.py",
    "job_auth.py",
    "zip_safe.py",
    "diagnostics_routes.py",
    "diagnostics_tea.py",
    "diagnostics_ghidra.py",
    "diagnostics_models.py",
    "diagnostics_status.py",
    "ghidra_decompile.py",
    "requirements.txt",
    "deploy/release-deploy.sh",
    "deploy/release-rollback.sh",
    "deploy/post-deploy-smoke.sh",
    "deploy/scootercheck-fw.service",
    "deploy/validate-release-config.sh",
    "deploy/RELEASE_COMPAT.md",
]


def _manifest_entries(path: Path) -> list[str]:
    entries: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        entries.append(s)
    return entries


def _env_example_mentions(key: str, text: str) -> bool:
    return bool(re.search(rf"^#?\s*{re.escape(key)}=", text, re.MULTILINE))


def _app_getenv_keys(text: str) -> set[str]:
    return set(re.findall(r'os\.environ\.get\(\s*"([A-Z0-9_]+)"', text))


# --- pytest-friendly function tests (CI gate) ---

def test_manifest_exists_and_lists_required():
    text = MANIFEST.read_text(encoding="utf-8")
    for name in REQUIRED_RUNTIME:
        assert name in text, f"missing from deploy-manifest: {name}"


def test_required_files_exist_on_disk():
    for name in REQUIRED_RUNTIME:
        assert (APP_DIR / name).is_file(), f"file missing: {name}"


def test_c11_diagnostics_listed():
    entries = set(_manifest_entries(MANIFEST))
    for name in C11_DIAGNOSTICS:
        assert name in entries, f"manifest missing {name}"


def test_env_example_documents_critical_keys():
    text = ENV_EXAMPLE.read_text(encoding="utf-8")
    missing = [k for k in CRITICAL_ENV_KEYS if not _env_example_mentions(k, text)]
    assert missing == [], f".env.example missing keys: {missing}"


def test_validate_release_config_offline_passes():
    assert VALIDATE_SH.is_file()
    assert os.access(VALIDATE_SH, os.X_OK), "validate-release-config.sh must be executable"
    proc = subprocess.run(
        [str(VALIDATE_SH), "offline"],
        cwd=str(APP_DIR),
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, f"offline validator failed:\n{proc.stderr}"
    combined = proc.stdout + proc.stderr
    assert not re.search(r"(?i)(api_token|jwt_secret|admin_api_token)=.+", combined)


# --- unittest class (discoverable via python -m unittest) ---

class TestDeployManifest(unittest.TestCase):
    def test_manifest_entries_exist_on_disk(self) -> None:
        missing = [e for e in _manifest_entries(MANIFEST) if not (APP_DIR / e).exists()]
        self.assertEqual(missing, [], f"manifest paths missing: {missing}")

    def test_app_py_critical_getenv_documented(self) -> None:
        app_text = APP_PY.read_text(encoding="utf-8")
        env_text = ENV_EXAMPLE.read_text(encoding="utf-8")
        present = _app_getenv_keys(app_text)
        for key in APP_CRITICAL_GETENV:
            self.assertIn(key, present, f"app.py no longer getenv {key}")
            self.assertTrue(
                _env_example_mentions(key, env_text),
                f"app.py getenv {key} undocumented in .env.example",
            )

    def test_systemd_unit_readonly_ghidra_contract(self) -> None:
        unit = (DEPLOY_DIR / "scootercheck-fw.service").read_text(encoding="utf-8")
        self.assertIn("ProtectHome=true", unit)
        self.assertIn("/opt/ghidra", unit)
        self.assertIn("ReadOnlyPaths=", unit)
        self.assertIn("EnvironmentFile=/etc/scootercheck/firmware-analysis.env", unit)

    def test_phase1_rollout_includes_diagnostics(self) -> None:
        rollout = (DEPLOY_DIR / "phase1-rollout.sh").read_text(encoding="utf-8")
        for name in C11_DIAGNOSTICS:
            self.assertIn(name, rollout, f"phase1-rollout.sh missing {name}")


if __name__ == "__main__":
    unittest.main()
