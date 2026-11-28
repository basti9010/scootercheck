"""CI AutoFix classifier + attempt limits."""

from __future__ import annotations

from ai_bridge import __version__  # noqa: F401 — path smoke
from ci_autofix.classifier import FailureClass, classify, fingerprint
from ci_autofix.engine import AutoFixHistory, evaluate_failure


def test_classify_swift_and_pytest() -> None:
    assert classify("error: cannot find type X in swiftc") == FailureClass.SWIFT_COMPILE
    assert classify("FAILED tests/test_foo.py::test_bar - AssertionError") == FailureClass.PYTHON_TEST_FAILURE


def test_max_two_attempts_then_blocked() -> None:
    history = AutoFixHistory()
    log = "FAILED tests/x.py::test_y"
    d1 = evaluate_failure(workflow="ios-tests", commit="abc", log_text=log, history=history)
    assert d1.action == "prepare_task"
    history.record(d1.fingerprint, "failed")
    d2 = evaluate_failure(workflow="ios-tests", commit="abc", log_text=log, history=history)
    assert d2.action == "prepare_task"
    history.record(d2.fingerprint, "failed")
    d3 = evaluate_failure(workflow="ios-tests", commit="abc", log_text=log, history=history)
    assert d3.action == "blocked"
    assert d3.attempts >= 2


def test_fingerprint_stable() -> None:
    a = fingerprint("w", "c", FailureClass.UNKNOWN_FAILURE, "same")
    b = fingerprint("w", "c", FailureClass.UNKNOWN_FAILURE, "same")
    assert a == b
