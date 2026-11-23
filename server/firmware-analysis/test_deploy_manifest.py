"""Ensure CD release manifest covers diagnostics + core modules."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "deploy" / "deploy-manifest.txt"

REQUIRED = [
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
]


def test_manifest_exists_and_lists_required():
    text = MANIFEST.read_text(encoding="utf-8")
    for name in REQUIRED:
        assert name in text, f"missing from deploy-manifest: {name}"


def test_required_files_exist_on_disk():
    for name in REQUIRED:
        assert (ROOT / name).is_file(), f"file missing: {name}"
