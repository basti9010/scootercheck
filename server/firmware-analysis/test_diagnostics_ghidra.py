"""Cycle 11 Agent C — unit tests for diagnostics_ghidra (mocked missing Ghidra).

Never requires a real analyzeHeadless install. Asserts honest FAILED/UNKNOWN
with MISSING_PREREQUISITE and zero fabricated exports.
"""
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import diagnostics_ghidra as dg


class DiagnosticsGhidraFixtureTests(unittest.TestCase):
    def test_fixture_sha256_matches_frozen_digest(self) -> None:
        path = dg.resolve_fixture_path()
        self.assertTrue(path.is_file(), f"missing fixture: {path}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        self.assertEqual(digest, dg.EXPECTED_FIXTURE_SHA256)
        self.assertIn(dg.FIXTURE_MARKER, path.read_bytes())

    def test_testdata_and_cycle10_constant_agree(self) -> None:
        td = dg._TESTDATA_FIXTURE
        c10 = dg.CYCLE10_FIXTURE
        self.assertTrue(td.is_file())
        if c10.is_file():
            self.assertEqual(
                hashlib.sha256(td.read_bytes()).hexdigest(),
                hashlib.sha256(c10.read_bytes()).hexdigest(),
            )


class DiagnosticsGhidraMissingPrereqTests(unittest.TestCase):
    def test_mocked_missing_ghidra_returns_failed_unknown(self) -> None:
        def _missing() -> tuple[None, list]:
            return None, [
                {"path": "env:GHIDRA_HEADLESS", "status": "unset"},
                {"path": "PATH:analyzeHeadless", "status": "absent"},
            ]

        result = dg.run_ghidra_diagnostics_selftest(resolve_headless_fn=_missing)
        self.assertFalse(result["executed"])
        self.assertFalse(result["grades"]["configured"])
        self.assertFalse(result["grades"]["available"])
        self.assertFalse(result["grades"]["verified"])
        self.assertFalse(result["grades"]["endToEndVerified"])
        self.assertEqual(result["grades"]["overall"], dg.GRADE_FAILED)
        self.assertEqual(result["overallCode"], dg.CODE_MISSING_PREREQUISITE)
        self.assertIsNotNone(result["exactMissingCause"])
        self.assertIn(dg.CODE_MISSING_PREREQUISITE, result["exactMissingCause"])

        by_id = {s["id"]: s for s in result["steps"]}
        self.assertEqual(by_id[1]["status"], dg.GRADE_FAILED)
        self.assertEqual(by_id[1]["code"], dg.CODE_MISSING_PREREQUISITE)
        for sid in (2, 3, 4, 5, 6):
            self.assertEqual(by_id[sid]["status"], dg.GRADE_UNKNOWN, sid)
            self.assertEqual(by_id[sid]["code"], dg.CODE_MISSING_PREREQUISITE, sid)
        self.assertEqual(by_id[7]["status"], dg.GRADE_VERIFIED)
        self.assertEqual(by_id[8]["status"], dg.GRADE_VERIFIED)
        self.assertEqual(by_id[8]["evidence"]["actual"], dg.EXPECTED_FIXTURE_SHA256)

        # Never fabricate exports in the result envelope
        run = result.get("run")
        self.assertTrue(run is None or not (run.get("exports") or {}))

    def test_missing_ghidra_does_not_write_fake_exports(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ghidra-diag-nofake-") as td:
            out = Path(td)
            # Precondition: empty work dir
            self.assertEqual(list(out.iterdir()), [])

            def _missing() -> tuple[None, list]:
                return None, []

            result = dg.run_ghidra_diagnostics_selftest(resolve_headless_fn=_missing)
            self.assertEqual(result["overallCode"], dg.CODE_MISSING_PREREQUISITE)

            # Module must not create banned filenames anywhere under temp work
            for name in dg.FAKE_EXPORT_NAMES:
                self.assertFalse(
                    (out / name).exists(),
                    f"fabricated export must not appear: {name}",
                )

    def test_fixed_argv_builder_has_no_shell_metacharacters_user_args(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            cmd = dg._build_fixed_headless_argv(
                "/opt/ghidra/support/analyzeHeadless",
                bin_path=dg.resolve_fixture_path(),
                proj_dir=td_path / "proj",
                out_dir=td_path / "out",
                script_dir=dg.SCRIPT_DIR,
            )
        self.assertIsInstance(cmd, list)
        self.assertEqual(cmd[0], "/opt/ghidra/support/analyzeHeadless")
        self.assertIn("-import", cmd)
        self.assertIn("-processor", cmd)
        self.assertIn(dg.PROCESSOR, cmd)
        self.assertIn(dg.BASE_ADDR, cmd)
        # No shell string — every element is a discrete argv token
        for tok in cmd:
            self.assertIsInstance(tok, str)
            self.assertNotIn("\n", tok)


class DiagnosticsGhidraMockSuccessTests(unittest.TestCase):
    def test_mocked_successful_pipeline_marks_verified(self) -> None:
        fake_headless = Path(tempfile.gettempdir()) / "fake-analyzeHeadless-c11"
        fake_headless.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_headless.chmod(0o755)

        def _present() -> tuple[str, list]:
            return str(fake_headless), [{"path": "mock", "status": "hit"}]

        def _runner(headless: str, **kwargs) -> dict:
            out = Path(tempfile.mkdtemp(prefix="ghidra-diag-mock-"))
            fn = out / "diag.functions.json"
            cg = out / "diag.callgraph.json"
            fn.write_text(
                json.dumps({"functions": [{"name": "reset"}], "processor": dg.PROCESSOR}),
                encoding="utf-8",
            )
            cg.write_text(
                json.dumps({"edges": [], "nodes": ["reset"]}),
                encoding="utf-8",
            )
            return {
                "ok": True,
                "code": dg.CODE_OK,
                "detail": "analyzeHeadless completed",
                "returncode": 0,
                "elapsedSec": 0.01,
                "argvFixed": [headless, "-import", str(kwargs.get("bin_path"))],
                "exports": {
                    "functions": {
                        "present": True,
                        "path": str(fn),
                        "size": fn.stat().st_size,
                        "jsonOk": True,
                        "sha256": hashlib.sha256(fn.read_bytes()).hexdigest(),
                    },
                    "callgraph": {
                        "present": True,
                        "path": str(cg),
                        "size": cg.stat().st_size,
                        "jsonOk": True,
                        "sha256": hashlib.sha256(cg.read_bytes()).hexdigest(),
                    },
                    "decompile": {"present": False, "path": "", "size": 0},
                },
                "processorRequested": dg.PROCESSOR,
                "baseAddrRequested": dg.BASE_ADDR,
            }

        try:
            result = dg.run_ghidra_diagnostics_selftest(
                resolve_headless_fn=_present,
                run_headless_fn=_runner,
            )
        finally:
            fake_headless.unlink(missing_ok=True)

        self.assertTrue(result["executed"])
        self.assertTrue(result["grades"]["configured"])
        self.assertTrue(result["grades"]["available"])
        self.assertTrue(result["grades"]["verified"])
        self.assertEqual(result["grades"]["overall"], dg.GRADE_VERIFIED)
        self.assertEqual(len(result["steps"]), 8)
        for step in result["steps"]:
            self.assertEqual(step["status"], dg.GRADE_VERIFIED, step)


class DiagnosticsGhidraLiveMissingTests(unittest.TestCase):
    """Live probe: on VMs without Ghidra, selftest must stay honest."""

    def test_live_selftest_when_unconfigured(self) -> None:
        headless, _ = dg._resolve_headless()
        if headless is not None:
            self.skipTest("Ghidra present — live missing-path test not applicable")
        result = dg.run_ghidra_diagnostics_selftest()
        self.assertFalse(result["executed"])
        self.assertEqual(result["overallCode"], dg.CODE_MISSING_PREREQUISITE)
        self.assertEqual(result["grades"]["overall"], dg.GRADE_FAILED)
        self.assertFalse(result["grades"]["verified"])
        self.assertEqual(result["fixture"]["actual"], dg.EXPECTED_FIXTURE_SHA256)


if __name__ == "__main__":
    unittest.main()
