"""Cycle 12 AGENT D — deploy smoke / rollback logic (no network, no SSH).

Covers:
  - parse /health JSON grades & flags
  - fail if only CONFIGURED claimed as VERIFIED
  - rollback trigger conditions (mirrors phase1-rollout.sh)
  - post-deploy smoke CLI argument parsing (expected interface)
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import deploy_smoke_logic as dsl


def _health(**overrides):
    base = {
        "ok": True,
        "service": "scootercheck-fw",
        "decryptConfigured": True,
        "ghidraConfigured": False,
        "ghidraEnabled": False,
        "jwtConfigured": True,
        "apiTokenConfigured": True,
        "adminApiTokenConfigured": True,
        "authSecurityOk": True,
        "authSecurityCritical": False,
        "authSecurityWarnings": [],
    }
    base.update(overrides)
    return base


class ParseHealthJsonTests(unittest.TestCase):
    def test_parse_string_payload(self) -> None:
        snap = dsl.parse_health_json(json.dumps(_health()))
        self.assertTrue(snap.ok)
        self.assertEqual(snap.service, "scootercheck-fw")
        self.assertTrue(snap.config_flags["decryptConfigured"])
        self.assertFalse(snap.config_flags["ghidraConfigured"])
        self.assertTrue(snap.auth_security_ok)

    def test_parse_dict_payload(self) -> None:
        snap = dsl.parse_health_json(_health(ok=False))
        self.assertFalse(snap.ok)

    def test_missing_ok_raises(self) -> None:
        with self.assertRaises(dsl.SmokeLogicError):
            dsl.parse_health_json({"service": "x"})

    def test_non_bool_flag_raises(self) -> None:
        with self.assertRaises(dsl.SmokeLogicError):
            dsl.parse_health_json(_health(decryptConfigured="yes"))

    def test_invalid_json_raises(self) -> None:
        with self.assertRaises(dsl.SmokeLogicError):
            dsl.parse_health_json("{not-json")

    def test_load_fixture_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "health.json"
            path.write_text(json.dumps(_health()), encoding="utf-8")
            snap = dsl.load_health_fixture(str(path))
            self.assertTrue(snap.ok)


class GradeFromFlagsTests(unittest.TestCase):
    def test_configured_flag_never_verified(self) -> None:
        self.assertEqual(
            dsl.grade_from_configured_flag(True),
            dsl.DiagnosticGrade.CONFIGURED,
        )
        self.assertEqual(
            dsl.grade_from_configured_flag(False),
            dsl.DiagnosticGrade.NOT_CONFIGURED,
        )

    def test_max_grade_from_health_is_configured(self) -> None:
        snap = dsl.parse_health_json(_health(decryptConfigured=True))
        self.assertEqual(
            dsl.max_grade_from_health_flags(snap),
            dsl.DiagnosticGrade.CONFIGURED,
        )

    def test_max_grade_unknown_when_no_flags(self) -> None:
        snap = dsl.parse_health_json(
            {
                "ok": True,
                "service": "scootercheck-fw",
            }
        )
        self.assertEqual(
            dsl.max_grade_from_health_flags(snap),
            dsl.DiagnosticGrade.UNKNOWN,
        )


class VerifiedFromConfiguredOnlyTests(unittest.TestCase):
    def test_fail_when_verified_claimed_from_flags(self) -> None:
        snap = dsl.parse_health_json(_health(decryptConfigured=True))
        claims = [
            dsl.ComponentGradeClaim(
                component_id="tea",
                grade="VERIFIED",
                evidence="flags",
            )
        ]
        with self.assertRaises(dsl.SmokeLogicError) as ctx:
            dsl.assert_no_verified_from_configured_only(claims, health=snap)
        self.assertIn("never equal VERIFIED", str(ctx.exception))

    def test_fail_end_to_end_from_health_flags(self) -> None:
        snap = dsl.parse_health_json(_health())
        claims = [
            dsl.ComponentGradeClaim(
                component_id="pipeline",
                grade="END_TO_END_VERIFIED",
                evidence="health",
            )
        ]
        errors = dsl.validate_grade_claims(claims, health=snap)
        self.assertTrue(errors)
        self.assertTrue(any("END_TO_END_VERIFIED" in e for e in errors))

    def test_fail_verified_unknown_evidence_with_configured_only_health(self) -> None:
        snap = dsl.parse_health_json(_health(decryptConfigured=True, ghidraConfigured=True))
        claims = [
            dsl.ComponentGradeClaim(
                component_id="ghidra",
                grade="VERIFIED",
                evidence="unknown",
            )
        ]
        errors = dsl.validate_grade_claims(claims, health=snap)
        self.assertTrue(any("only justify CONFIGURED" in e for e in errors))

    def test_pass_verified_with_probe_evidence(self) -> None:
        snap = dsl.parse_health_json(_health())
        claims = [
            dsl.ComponentGradeClaim(
                component_id="tea",
                grade="VERIFIED",
                evidence="probe",
            )
        ]
        # Probe evidence is allowed by this gate (Agent B/C own the probe).
        dsl.assert_no_verified_from_configured_only(claims, health=snap)

    def test_pass_configured_claim_from_flags(self) -> None:
        snap = dsl.parse_health_json(_health())
        claims = [
            dsl.ComponentGradeClaim(
                component_id="tea",
                grade="CONFIGURED",
                evidence="flags",
            )
        ]
        dsl.assert_no_verified_from_configured_only(claims, health=snap)


class RollbackDecisionTests(unittest.TestCase):
    def test_dry_run_never_rolls_back(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=False,
            health_curl_ok=False,
            health=None,
            import_tests_ok=False,
            live_deploy=False,
        )
        self.assertFalse(decision.should_rollback)
        self.assertIn("dry-run", decision.reasons[0])

    def test_restart_failure_triggers_rollback(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=False,
            health_curl_ok=True,
            health=dsl.parse_health_json(_health()),
            live_deploy=True,
        )
        self.assertTrue(decision.should_rollback)
        self.assertTrue(any("restart" in r for r in decision.reasons))

    def test_health_curl_failure_triggers_rollback(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=True,
            health_curl_ok=False,
            health=None,
            live_deploy=True,
        )
        self.assertTrue(decision.should_rollback)
        self.assertTrue(any("curl" in r for r in decision.reasons))

    def test_ok_false_triggers_rollback(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=True,
            health_curl_ok=True,
            health=dsl.parse_health_json(_health(ok=False)),
            live_deploy=True,
        )
        self.assertTrue(decision.should_rollback)
        self.assertTrue(any("ok!=true" in r for r in decision.reasons))

    def test_missing_health_payload_triggers_rollback(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=True,
            health_curl_ok=True,
            health=None,
            live_deploy=True,
        )
        self.assertTrue(decision.should_rollback)
        self.assertTrue(any("missing" in r for r in decision.reasons))

    def test_import_tests_failure_triggers_rollback(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=True,
            health_curl_ok=True,
            health=dsl.parse_health_json(_health()),
            import_tests_ok=False,
            live_deploy=True,
        )
        self.assertTrue(decision.should_rollback)
        self.assertTrue(any("import/tests" in r for r in decision.reasons))

    def test_healthy_live_deploy_no_rollback(self) -> None:
        decision = dsl.evaluate_rollback(
            restart_ok=True,
            health_curl_ok=True,
            health=dsl.parse_health_json(_health()),
            import_tests_ok=True,
            live_deploy=True,
        )
        self.assertFalse(decision.should_rollback)
        self.assertEqual(decision.reasons, ())


class SmokePassTests(unittest.TestCase):
    def test_smoke_pass_healthy(self) -> None:
        ok, failures = dsl.evaluate_smoke_pass(
            dsl.parse_health_json(_health(authMode="token"))
        )
        self.assertTrue(ok)
        self.assertEqual(failures, ())

    def test_smoke_fail_ok_false(self) -> None:
        ok, failures = dsl.evaluate_smoke_pass(dsl.parse_health_json(_health(ok=False)))
        self.assertFalse(ok)
        self.assertTrue(any("ok" in f for f in failures))

    def test_smoke_fail_open_auth_mode(self) -> None:
        ok, failures = dsl.evaluate_smoke_pass(
            dsl.parse_health_json(_health(authMode="open"))
        )
        self.assertFalse(ok)
        self.assertTrue(any("open" in f for f in failures))

    def test_smoke_fail_auth_when_required(self) -> None:
        snap = dsl.parse_health_json(
            _health(authSecurityOk=False, authSecurityCritical=True)
        )
        ok, failures = dsl.evaluate_smoke_pass(
            snap, require_auth_security_ok=True
        )
        self.assertFalse(ok)
        self.assertGreaterEqual(len(failures), 1)

    def test_smoke_fail_verified_from_flags(self) -> None:
        snap = dsl.parse_health_json(_health())
        ok, failures = dsl.evaluate_smoke_pass(
            snap,
            grade_claims=[
                dsl.ComponentGradeClaim("tea", "VERIFIED", "flags"),
            ],
        )
        self.assertFalse(ok)
        self.assertTrue(any("VERIFIED" in f for f in failures))

    def test_health_flag_grades_are_configured_not_verified(self) -> None:
        snap = dsl.parse_health_json(
            _health(decryptConfigured=True, ghidraConfigured=False)
        )
        lines = dsl.health_flag_grade_lines(snap)
        self.assertEqual(lines["decryptConfigured"], "CONFIGURED")
        self.assertEqual(lines["ghidraConfigured"], "NOT_CONFIGURED")
        self.assertNotIn("VERIFIED", lines.values())

    def test_release_smoke_rollback_gate(self) -> None:
        self.assertTrue(
            dsl.should_rollback_after_release(
                smoke_passed=False, release_succeeded=True
            )
        )
        self.assertFalse(
            dsl.should_rollback_after_release(
                smoke_passed=True, release_succeeded=True
            )
        )
        self.assertFalse(
            dsl.should_rollback_after_release(
                smoke_passed=False, release_succeeded=False
            )
        )


class SmokeArgParseTests(unittest.TestCase):
    """CLI helpers for offline smoke (Python) + shell env contract."""

    def test_defaults_are_safe(self) -> None:
        args = dsl.parse_smoke_argv([])
        self.assertTrue(args.dry_run)
        self.assertTrue(args.no_ssh)
        self.assertTrue(args.require_ok)
        self.assertTrue(args.forbid_verified_from_flags)
        self.assertFalse(args.require_auth_security_ok)
        self.assertEqual(args.service_name, "scootercheck-fw")
        self.assertIn("8088", args.health_url)

    def test_health_json_fixture_path(self) -> None:
        args = dsl.parse_smoke_argv(
            ["--health-json", "/tmp/fixture-health.json", "--timeout-sec", "5"]
        )
        self.assertEqual(args.health_json_path, "/tmp/fixture-health.json")
        self.assertEqual(args.timeout_sec, 5.0)

    def test_can_disable_dry_run_flag_parse_only(self) -> None:
        # Parsing --live / --allow-ssh must work; this module still does not SSH.
        args = dsl.parse_smoke_argv(["--live", "--allow-ssh"])
        self.assertFalse(args.dry_run)
        self.assertFalse(args.no_ssh)

    def test_json_out_and_auth_gate(self) -> None:
        args = dsl.parse_smoke_argv(
            [
                "--json-out",
                "/tmp/smoke-result.json",
                "--require-auth-security-ok",
                "--service-name",
                "scootercheck-fw",
            ]
        )
        self.assertEqual(args.json_out, "/tmp/smoke-result.json")
        self.assertTrue(args.require_auth_security_ok)

    def test_offline_smoke_via_fixture_end_to_end_helper(self) -> None:
        """Fixture path: parse CLI → load JSON → evaluate (still no network)."""
        with tempfile.TemporaryDirectory() as td:
            fixture = Path(td) / "health.json"
            fixture.write_text(
                json.dumps(_health(authMode="token")), encoding="utf-8"
            )
            args = dsl.parse_smoke_argv(
                ["--health-json", str(fixture), "--dry-run", "--no-ssh"]
            )
            self.assertTrue(args.dry_run)
            self.assertTrue(args.no_ssh)
            self.assertIsNotNone(args.health_json_path)
            snap = dsl.load_health_fixture(args.health_json_path)  # type: ignore[arg-type]
            ok, failures = dsl.evaluate_smoke_pass(
                snap,
                require_ok=args.require_ok,
                require_auth_security_ok=args.require_auth_security_ok,
                forbid_verified_from_flags=args.forbid_verified_from_flags,
            )
            self.assertTrue(ok, failures)


class PostDeploySmokeEnvTests(unittest.TestCase):
    """Mock/fixture tests for deploy/post-deploy-smoke.sh env interface."""

    def test_default_env_contract(self) -> None:
        env = dsl.parse_post_deploy_smoke_env({})
        self.assertEqual(env.service_name, "scootercheck-fw")
        self.assertIn("8088", env.health_url)
        self.assertEqual(env.smoke_admin_token, "")
        self.assertTrue(env.remote_smoke)
        self.assertTrue(env.public_smoke)
        self.assertFalse(env.require_diagnostics)

    def test_offline_ci_env_disables_remote_and_public(self) -> None:
        env = dsl.parse_post_deploy_smoke_env(
            {
                "REMOTE_SMOKE": "0",
                "PUBLIC_SMOKE": "0",
                "HEALTH_URL": "http://127.0.0.1:8088/health",
                "SERVICE_NAME": "scootercheck-fw",
            }
        )
        self.assertFalse(env.remote_smoke)
        self.assertFalse(env.public_smoke)
        # Offline mode must not imply a token was present.
        self.assertEqual(env.smoke_admin_token, "")

    def test_admin_token_from_smoke_or_admin_env_not_echoed(self) -> None:
        env = dsl.parse_post_deploy_smoke_env({"SMOKE_ADMIN_TOKEN": "secret-value"})
        self.assertEqual(env.smoke_admin_token, "secret-value")
        # Helper must not log; representation should still hold the value for
        # callers — tests only assert presence, never print it.
        self.assertTrue(bool(env.smoke_admin_token))
        env2 = dsl.parse_post_deploy_smoke_env({"ADMIN_API_TOKEN": "fallback-token"})
        self.assertEqual(env2.smoke_admin_token, "fallback-token")

    def test_script_documents_configured_not_verified(self) -> None:
        script = Path(__file__).resolve().parent / "deploy" / "post-deploy-smoke.sh"
        self.assertTrue(script.is_file(), "post-deploy-smoke.sh missing on base")
        text = script.read_text(encoding="utf-8")
        self.assertIn("CONFIGURED", text)
        self.assertIn("VERIFIED", text)
        self.assertIn("HEALTH_URL", text)
        self.assertIn("SMOKE_ADMIN_TOKEN", text)
        # Must not claim E2E from flags alone.
        self.assertIn("END_TO_END_VERIFIED", text)


if __name__ == "__main__":
    unittest.main()
