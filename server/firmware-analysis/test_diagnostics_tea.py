"""Unit tests for safe NinebotTEA / DECRYPT_CMD diagnostics."""
from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import diagnostics_tea as tea


class RedactionTests(unittest.TestCase):
    def test_redact_empty(self) -> None:
        meta = tea.redact_decrypt_cmd("")
        self.assertFalse(meta["set"])
        self.assertIsNone(meta["basename"])

    def test_redact_never_embeds_full_path(self) -> None:
        meta = tea.redact_decrypt_cmd("/opt/scootercheck/decrypt-firm.sh")
        blob = json.dumps(meta)
        self.assertNotIn("/opt/scootercheck", blob)
        self.assertTrue(meta["set"])
        self.assertEqual(meta["basename"], "decrypt-firm.sh")
        self.assertTrue(meta["looksAbsolute"])


class ResolveWrapperTests(unittest.TestCase):
    def test_missing_when_unset(self) -> None:
        r = tea.resolve_wrapper("")
        self.assertFalse(r["configured"])
        self.assertFalse(r["exists"])

    def test_path_hit(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "decrypt-firm.sh"
            path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            r = tea.resolve_wrapper(str(path))
            self.assertTrue(r["configured"])
            self.assertTrue(r["exists"])
            self.assertEqual(r["via"], "path")
            self.assertEqual(r["resolvedBasename"], "decrypt-firm.sh")

    def test_which_hit(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "fake-tea-wrap"
            path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            env_path = f"{td}{os.pathsep}{os.environ.get('PATH', '')}"
            with mock.patch.dict(os.environ, {"PATH": env_path}, clear=False):
                r = tea.resolve_wrapper("fake-tea-wrap")
            self.assertTrue(r["exists"])
            self.assertEqual(r["via"], "which")

    def test_configured_but_missing(self) -> None:
        r = tea.resolve_wrapper("/no/such/decrypt-firm-zzzz.sh")
        self.assertTrue(r["configured"])
        self.assertFalse(r["exists"])


class SafeFlagDetectionTests(unittest.TestCase):
    def test_example_wrapper_has_no_safe_flags(self) -> None:
        example = Path(__file__).resolve().parent / "decrypt-firm.example.sh"
        self.assertTrue(example.is_file())
        flags = tea.detect_documented_safe_flags(example, basename=example.name)
        self.assertEqual(flags, [])

    def test_ninebottea_basename_gets_help(self) -> None:
        flags = tea.detect_documented_safe_flags(None, basename="ninebottea")
        self.assertEqual(flags, ["--help"])

    def test_script_documenting_dry_run(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "wrap.sh"
            path.write_text(
                "#!/bin/sh\n# usage: wrap.sh --dry-run\ncase $1 in --dry-run) exit 0;; esac\n",
                encoding="utf-8",
            )
            flags = tea.detect_documented_safe_flags(path, basename="wrap.sh")
            self.assertEqual(flags, ["--dry-run"])


class DiagnoseGradeTests(unittest.TestCase):
    def test_unset_is_unknown(self) -> None:
        report = tea.diagnose_tea(decrypt_cmd="", run_probe=True)
        self.assertEqual(report["grade"], tea.GRADE_UNKNOWN)
        self.assertFalse(report["grades"]["CONFIGURED"])
        self.assertFalse(report["policy"]["decryptRealPacks"])
        self.assertFalse(report["policy"]["inventKeys"])
        self.assertFalse(report["policy"]["echoEnvSecrets"])
        blob = json.dumps(report)
        self.assertNotIn("KEY=", blob)

    def test_missing_wrapper_is_failed(self) -> None:
        report = tea.diagnose_tea(
            decrypt_cmd="/tmp/definitely-missing-tea-wrapper-9f3a.sh",
            run_probe=True,
        )
        self.assertEqual(report["grade"], tea.GRADE_FAILED)
        self.assertTrue(report["grades"]["CONFIGURED"])
        self.assertFalse(report["grades"]["AVAILABLE"])

    def test_available_without_probe_flag(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "decrypt-firm.sh"
            # No --help / --dry in body → probe skipped → AVAILABLE
            path.write_text(
                "#!/bin/sh\n# usage: decrypt-firm.sh input.enc output.bin\nexit 2\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            report = tea.diagnose_tea(decrypt_cmd=str(path), run_probe=True)
            self.assertEqual(report["grade"], tea.GRADE_AVAILABLE)
            self.assertFalse(report["probe"]["attempted"])
            self.assertEqual(report["probe"]["skippedReason"], "no_documented_safe_flag")

    def test_verified_on_help_exit_zero(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ninebottea"
            path.write_text(
                "#!/bin/sh\nif [ \"$1\" = \"--help\" ]; then echo 'ninebottea help'; exit 0; fi\nexit 1\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            report = tea.diagnose_tea(decrypt_cmd=str(path), run_probe=True)
            self.assertEqual(report["grade"], tea.GRADE_VERIFIED)
            self.assertTrue(report["probe"]["attempted"])
            self.assertTrue(report["probe"]["ok"])
            self.assertEqual(report["probe"]["probeArgs"], ["--help"])

    def test_failed_when_help_nonzero(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ninebottea"
            path.write_text(
                "#!/bin/sh\nif [ \"$1\" = \"--help\" ]; then echo boom; exit 9; fi\nexit 1\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            report = tea.diagnose_tea(decrypt_cmd=str(path), run_probe=True)
            self.assertEqual(report["grade"], tea.GRADE_FAILED)
            self.assertTrue(report["probe"]["attempted"])
            self.assertFalse(report["probe"]["ok"])

    def test_no_probe_caps_at_available(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ninebottea"
            path.write_text(
                "#!/bin/sh\nif [ \"$1\" = \"--help\" ]; then exit 0; fi\nexit 1\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            report = tea.diagnose_tea(decrypt_cmd=str(path), run_probe=False)
            self.assertEqual(report["grade"], tea.GRADE_AVAILABLE)

    def test_health_flag_alone_never_verified(self) -> None:
        self.assertEqual(tea.grade_from_configured_flag(True), tea.GRADE_CONFIGURED)
        self.assertEqual(tea.grade_from_configured_flag(False), tea.GRADE_UNKNOWN)

    def test_probe_output_redacts_secret_lines(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ninebottea"
            path.write_text(
                "#!/bin/sh\necho 'KEY=should-not-leak'\necho 'ok help'\nexit 0\n",
                encoding="utf-8",
            )
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
            report = tea.diagnose_tea(decrypt_cmd=str(path), run_probe=True)
            blob = json.dumps(report)
            self.assertNotIn("should-not-leak", blob)
            self.assertTrue(
                "<redacted-env-assignment>" in blob or "<redacted-secret-line>" in blob,
                blob,
            )

    def test_diagnose_reads_environ_override(self) -> None:
        report = tea.diagnose_tea(
            environ={"DECRYPT_CMD": ""},
            run_probe=False,
        )
        self.assertEqual(report["grade"], tea.GRADE_UNKNOWN)


class CliTests(unittest.TestCase):
    def test_cli_json(self) -> None:
        import io
        from contextlib import redirect_stdout

        buf = io.StringIO()
        with redirect_stdout(buf):
            code = tea.diagnose_tea_cli(["--no-probe"])
        self.assertEqual(code, 0)
        data = json.loads(buf.getvalue())
        self.assertEqual(data["component"], "ninebottea")
        self.assertIn(data["grade"], tea.GRADES)


if __name__ == "__main__":
    unittest.main()
