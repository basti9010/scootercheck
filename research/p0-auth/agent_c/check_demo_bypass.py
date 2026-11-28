#!/usr/bin/env python3
"""Regression: DemoAuthBootstrap / authGateEnabled=false must not exist on recovery tree.

Run from repo root: python3 research/p0-auth/agent_c/check_demo_bypass.py
Exit 0 = clean, 1 = bypass artifacts found.
Never prints credential values.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / "ios" / "ScooterCheck" / "ScooterCheck"

FAILURES: list[str] = []


def fail(msg: str) -> None:
    FAILURES.append(msg)


def main() -> int:
    demo = IOS / "Auth" / "DemoAuthBootstrap.swift"
    if demo.exists():
        fail(f"DemoAuthBootstrap.swift present at {demo.relative_to(ROOT)}")

    flags = IOS / "AppFeatureFlags.swift"
    if flags.exists():
        src = flags.read_text(encoding="utf-8")
        if "authGateEnabled = false" in src:
            fail("AppFeatureFlags.authGateEnabled = false")
        if "DemoAuthBootstrap" in src:
            fail("AppFeatureFlags references DemoAuthBootstrap")

    app = IOS / "ScooterCheckApp.swift"
    if app.exists():
        src = app.read_text(encoding="utf-8")
        if "DemoAuthBootstrap" in src:
            fail("ScooterCheckApp calls DemoAuthBootstrap")
        if "AuthGateView" not in src:
            fail("ScooterCheckApp missing AuthGateView root")

    # Sweep Auth sources for demo bootstrap type
    auth_dir = IOS / "Auth"
    if auth_dir.is_dir():
        for path in auth_dir.glob("*.swift"):
            text = path.read_text(encoding="utf-8", errors="replace")
            if "enum DemoAuthBootstrap" in text or "struct DemoAuthBootstrap" in text:
                fail(f"DemoAuthBootstrap type in {path.relative_to(ROOT)}")

    if FAILURES:
        print("FAIL: demo / auth-gate bypass artifacts detected:")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("OK: no DemoAuthBootstrap; auth gate not disabled on this tree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
