"""Classify CI failure logs into bounded classes."""

from __future__ import annotations

import hashlib
import re
from enum import Enum


class FailureClass(str, Enum):
    SWIFT_COMPILE = "Swift Compile"
    XCTEST_FAILURE = "XCTest Failure"
    PYTHON_TEST_FAILURE = "Python Test Failure"
    API_CONTRACT_FAILURE = "API Contract Failure"
    DEPENDENCY_FAILURE = "Dependency Failure"
    SECURITY_TEST_FAILURE = "Security Test Failure"
    DEPLOYMENT_VALIDATION_FAILURE = "Deployment Validation Failure"
    UNKNOWN_FAILURE = "Unknown Failure"


_RULES: list[tuple[FailureClass, re.Pattern[str]]] = [
    (FailureClass.SWIFT_COMPILE, re.compile(r"error:|swiftc|CompileSwift", re.I)),
    (FailureClass.XCTEST_FAILURE, re.compile(r"XCTAssert|Test Case .* failed", re.I)),
    (FailureClass.PYTHON_TEST_FAILURE, re.compile(r"FAILED .*::|pytest|AssertionError", re.I)),
    (FailureClass.API_CONTRACT_FAILURE, re.compile(r"contract|openapi|schema validation", re.I)),
    (FailureClass.DEPENDENCY_FAILURE, re.compile(r"Could not resolve|pip install|CocoaPods", re.I)),
    (FailureClass.SECURITY_TEST_FAILURE, re.compile(r"security|bandit|gitleaks|authz", re.I)),
    (FailureClass.DEPLOYMENT_VALIDATION_FAILURE, re.compile(r"deploy|smoke|rollback", re.I)),
]


def classify(log_text: str) -> FailureClass:
    for cls, pat in _RULES:
        if pat.search(log_text or ""):
            return cls
    return FailureClass.UNKNOWN_FAILURE


def fingerprint(workflow: str, commit: str, failure_class: FailureClass, excerpt: str) -> str:
    material = f"{workflow}|{commit}|{failure_class.value}|{(excerpt or '')[:500]}"
    return hashlib.sha256(material.encode("utf-8")).hexdigest()[:24]


MAX_ATTEMPTS_PER_FINGERPRINT = 2
