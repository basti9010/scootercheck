"""Phase 2.2C intelligent function matching tests + ground-truth metrics."""
from __future__ import annotations

import json
import time
import unittest
from pathlib import Path

import function_diff as fd
import function_matcher as fm

FIXTURE = Path(__file__).resolve().parent / "testdata" / "thumb_validation" / "meta"


def _fn(
    addr: str,
    name: str,
    size: int,
    blocks: int,
    edges: int,
    fp: str,
    *,
    calls=None,
    called_by=None,
    mnemonics=None,
    constants=None,
):
    return {
        "address": addr,
        "name": name,
        "size": size,
        "basicBlocks": blocks,
        "cfgEdges": edges,
        "calls": calls or [],
        "calledBy": called_by or [],
        "constants": constants or [],
        "strings": [],
        "mnemonics": mnemonics or ["movs", "bx"],
        "fingerprint": fp,
        "confidence": "medium",
    }


class MatcherUnitTests(unittest.TestCase):
    def test_identical_same_address(self) -> None:
        f = _fn("0x08001000", "helper", 64, 4, 5, "aaa111", mnemonics=["push", "adds", "pop"])
        out = fm.match_functions([f], [dict(f)])
        self.assertEqual(out["summary"]["matched"], 1)
        self.assertEqual(out["matches"][0]["matchConfidence"], fm.CONF_HIGH)

    def test_identical_different_address(self) -> None:
        a = _fn("0x08001000", "mul_values", 4, 1, 0, "3e00332063f582a1", mnemonics=["muls", "bx"])
        b = _fn("0x08002000", "mul_values", 4, 1, 0, "3e00332063f582a1", mnemonics=["muls", "bx"])
        out = fm.match_functions([a], [b])
        self.assertEqual(out["summary"]["matched"], 1)
        self.assertEqual(out["matches"][0]["matchMethod"], "fingerprint_exact")

    def test_generic_ghidra_name_ignored_as_identity(self) -> None:
        a = _fn("0x08001000", "FUN_08001000", 32, 3, 4, "fp_a", mnemonics=["push", "cmp", "ble", "pop"])
        b = _fn("0x08002000", "FUN_08002000", 32, 3, 4, "fp_b", mnemonics=["push", "cmp", "ble", "pop"])
        # Different fingerprints but strong structural — should still match structurally
        out = fm.match_functions([a], [b])
        matched = [m for m in out["matches"] if m.get("subject") and m.get("reference")]
        self.assertEqual(len(matched), 1)
        self.assertIn(matched[0]["matchMethod"], {"structural", "call_neighborhood"})
        self.assertNotEqual(matched[0]["matchMethod"], "name_reliable")

    def test_small_structural_change(self) -> None:
        a = _fn("0x1", "add_values", 4, 1, 0, "fp1", mnemonics=["adds", "bx"])
        b = _fn("0x2", "add_values", 6, 1, 0, "fp2", mnemonics=["adds", "adds", "bx"])
        out = fm.match_functions([a], [b])
        m = next(x for x in out["matches"] if x.get("subject") and x.get("reference"))
        self.assertIn(m["matchConfidence"], {fm.CONF_HIGH, fm.CONF_MEDIUM, fm.CONF_LOW})

    def test_ambiguous_identical_helpers(self) -> None:
        s = _fn("0x1", "helper_a", 8, 1, 0, "samefp", mnemonics=["adds", "bx"])
        r1 = _fn("0x2", "helper_b", 8, 1, 0, "samefp", mnemonics=["adds", "bx"])
        r2 = _fn("0x3", "helper_c", 8, 1, 0, "samefp", mnemonics=["adds", "bx"])
        out = fm.match_functions([s], [r1, r2])
        amb = [m for m in out["matches"] if m.get("matchConfidence") == fm.CONF_AMBIGUOUS]
        self.assertGreaterEqual(len(amb), 1)

    def test_missing_and_new_functions(self) -> None:
        sub = [
            _fn(
                "0x1",
                "new_fn",
                24,
                4,
                6,
                "n1",
                mnemonics=["push", "eors", "eors", "pop"],
                calls=["x"],
            )
        ]
        ref = [
            _fn(
                "0x2",
                "old_fn",
                8,
                1,
                0,
                "o1",
                mnemonics=["orrs", "bx"],
                calls=[],
            )
        ]
        out = fm.match_functions(sub, ref)
        self.assertGreaterEqual(out["summary"]["unmatched"], 2)

    def test_incompatible_arch_via_diff(self) -> None:
        a = {"ok": True, "processor": "ARM:LE:32:Cortex", "functions": [_fn("0x1", "A", 8, 1, 0, "x")]}
        b = {"ok": True, "processor": "x86:LE:64:default", "functions": [_fn("0x1", "A", 8, 1, 0, "x")]}
        out = fd.compare_function_analyses(a, b)
        self.assertEqual(out["summary"]["overall"], fd.STATUS_UNCOMPARABLE)

    def test_missing_reference_catalog(self) -> None:
        a = {"ok": True, "functions": [_fn("0x1", "A", 8, 1, 0, "x")]}
        out = fd.compare_function_analyses(a, None)
        self.assertEqual(out["summary"]["overall"], fd.STATUS_UNCOMPARABLE)


class GroundTruthFixtureTests(unittest.TestCase):
    """Evaluate matcher against thumb_validation ground truth."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.gt = json.loads((FIXTURE / "ground_truth.json").read_text(encoding="utf-8"))
        cls.ver_a = json.loads((FIXTURE / "version_a.functions.json").read_text(encoding="utf-8"))
        cls.ver_b = json.loads((FIXTURE / "version_b.functions.json").read_text(encoding="utf-8"))
        cls.ver_a["ok"] = True
        cls.ver_b["ok"] = True

    def test_ground_truth_metrics(self) -> None:
        # Subject = version_b, reference = version_a (as in stock compare subject vs OEM)
        t0 = time.perf_counter()
        out = fd.compare_function_analyses(self.ver_b, self.ver_a)
        elapsed_ms = (time.perf_counter() - t0) * 1000

        expected = self.gt["expectedDiff"]
        # Build name→status from pairs
        by_name: dict[str, str] = {}
        for p in out["pairs"]:
            name = (p.get("subject") or p.get("reference") or {}).get("name")
            if name:
                by_name[name] = p["status"]

        tp = fp = fn = 0
        # identical_likely should be IDENTISCH
        for name in expected["identical_likely"]:
            if by_name.get(name) == fd.STATUS_IDENTICAL:
                tp += 1
            else:
                fn += 1
                fp += 0
        # structurally_changed should be STRUKTURELL_VERAENDERT
        for name in expected["structurally_changed"]:
            st = by_name.get(name)
            if st == fd.STATUS_CHANGED:
                tp += 1
            elif st is None:
                fn += 1
            else:
                # wrong class
                fp += 1
                fn += 1
        for name in expected["added"]:
            if by_name.get(name) == fd.STATUS_ADDED:
                tp += 1
            else:
                fn += 1
        for name in expected["removed"]:
            if by_name.get(name) == fd.STATUS_REMOVED:
                tp += 1
            else:
                fn += 1

        precision = tp / max(tp + fp, 1)
        recall = tp / max(tp + fn, 1)
        ambiguous = out["summary"].get("ambiguous", 0)

        # Persist metrics in assert messages for the Abschlussbericht
        self.assertGreaterEqual(
            precision,
            0.7,
            f"precision={precision:.3f} recall={recall:.3f} tp={tp} fp={fp} fn={fn} "
            f"ambiguous={ambiguous} elapsed_ms={elapsed_ms:.1f} by_name={by_name}",
        )
        self.assertGreaterEqual(
            recall,
            0.7,
            f"precision={precision:.3f} recall={recall:.3f} tp={tp} fp={fp} fn={fn} "
            f"ambiguous={ambiguous} elapsed_ms={elapsed_ms:.1f} by_name={by_name}",
        )
        # mul_values must match across address shift
        self.assertEqual(by_name.get("mul_values"), fd.STATUS_IDENTICAL)
        self.assertLess(elapsed_ms, 500.0)

        # Stash for optional reporting
        GroundTruthFixtureTests.last_metrics = {
            "precision": precision,
            "recall": recall,
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "ambiguous": ambiguous,
            "elapsed_ms": elapsed_ms,
            "by_name": by_name,
            "summary": out["summary"],
        }


if __name__ == "__main__":
    unittest.main()
