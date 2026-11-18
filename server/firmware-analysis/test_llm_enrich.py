"""Unit tests for schema-bound LLM enrichment (no live API required)."""
from __future__ import annotations

import os
import unittest
from unittest import mock

import llm_enrich


SAMPLE_C = "\n".join(
    [
        "void init(void) {",
        "  set_cap(0x1600);",
        "}",
        "void mode_switch(void) {",
        "  if (brake && throttle) { open_limit(0x6300); }",
        "}",
        "int unused(void) { return 1; }",
    ]
    + [f"/* filler {i} */" for i in range(400)]
)


class SelectSnippetTests(unittest.TestCase):
    def test_short_text_passthrough(self) -> None:
        text = "set_cap(0x1600);"
        self.assertEqual(llm_enrich.select_decompile_snippet(text), text)

    def test_prefers_speed_windows(self) -> None:
        snip = llm_enrich.select_decompile_snippet(SAMPLE_C, max_chars=800)
        self.assertIn("0x1600", snip)
        self.assertIn("0x6300", snip)
        self.assertLessEqual(len(snip), 800)


class ProviderTests(unittest.TestCase):
    def test_detect_anthropic_from_key(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"LLM_API_KEY": "sk-ant-test", "LLM_PROVIDER": "", "LLM_BASE_URL": "", "ANTHROPIC_API_KEY": "", "OPENAI_API_KEY": ""},
            clear=False,
        ):
            self.assertEqual(llm_enrich.llm_provider(), "anthropic")
            self.assertIn("anthropic.com", llm_enrich._base_url())

    def test_explicit_openai(self) -> None:
        with mock.patch.dict(os.environ, {"LLM_PROVIDER": "openai", "LLM_API_KEY": "sk-test"}, clear=False):
            self.assertEqual(llm_enrich.llm_provider(), "openai")


class EnrichMergeTests(unittest.TestCase):
    def test_noop_without_key(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"LLM_API_KEY": "", "OPENAI_API_KEY": "", "ANTHROPIC_API_KEY": ""},
            clear=False,
        ):
            # Force re-read via empty keys
            base = {"comboSummaries": ["a"], "notes": [], "sources": [], "quality": {}}
            out = llm_enrich.enrich_result(dict(base), decompiled_text=SAMPLE_C)
            self.assertEqual(out.get("comboSummaries"), ["a"])

    def test_merge_validates_and_dedupes(self) -> None:
        result = {
            "comboSummaries": ["Gas+Bremse"],
            "modeTransitions": [],
            "inputHints": [],
            "notes": [],
            "sources": ["serverDecompile"],
            "quality": {"hasDeterministicBasis": True, "llmSchemaValidated": False, "summary": "ok"},
            "speedLimits": [{"kmh": 22}],
        }
        data = {
            "comboSummaries": ["Gas+Bremse", "Power 3s"],
            "modeTransitions": [
                {
                    "id": "t1",
                    "title": "Open Cap",
                    "trigger": "Bremse+Gas",
                    "effect": "99 km/h Stufe",
                    "evidence": "open_limit(0x6300)",
                    "confidence": "high",
                },
                {
                    "id": "t1b",
                    "title": "Open Cap",
                    "trigger": "Bremse+Gas",
                    "effect": "99 km/h Stufe",
                    "evidence": "dup",
                    "confidence": "bogus",
                },
            ],
            "inputHints": [
                {
                    "id": "i1",
                    "kind": "not-a-kind",
                    "detail": "Analog Gas",
                    "evidence": "throttle",
                    "confidence": "medium",
                }
            ],
            "notes": ["nur Heuristik"],
        }
        merged = llm_enrich._merge_validated(result, data)
        self.assertEqual(merged["comboSummaries"], ["Gas+Bremse", "Power 3s"])
        self.assertEqual(len(merged["modeTransitions"]), 1)
        self.assertEqual(merged["modeTransitions"][0]["confidence"], "high")
        self.assertEqual(merged["inputHints"][0]["kind"], "unknown")
        self.assertTrue(any(n.startswith("llm:") for n in merged["notes"]))

    def test_enrich_with_mocked_chat(self) -> None:
        payload = {
            "comboSummaries": ["Test-Kombi"],
            "modeTransitions": [],
            "inputHints": [
                {
                    "id": "i1",
                    "kind": "throttle",
                    "detail": "Gas-ADC",
                    "evidence": "throttle",
                    "confidence": "low",
                }
            ],
            "notes": [],
        }
        base = {
            "comboSummaries": [],
            "modeTransitions": [],
            "inputHints": [],
            "notes": [],
            "sources": ["serverDecompile"],
            "quality": {"hasDeterministicBasis": True, "llmSchemaValidated": False, "summary": "det"},
            "speedLimits": [{"kmh": 20}],
        }
        with mock.patch.dict(os.environ, {"LLM_API_KEY": "sk-test"}, clear=False):
            with mock.patch.object(llm_enrich, "_chat", return_value=json_dumps(payload)):
                out = llm_enrich.enrich_result(dict(base), decompiled_text=SAMPLE_C)
        self.assertIn("serverLLM", out["sources"])
        self.assertTrue(out["quality"]["llmSchemaValidated"])
        self.assertEqual(out["comboSummaries"], ["Test-Kombi"])
        self.assertTrue(any("llm=schema-enriched" in n for n in out["notes"]))


def json_dumps(obj: dict) -> str:
    import json

    return json.dumps(obj)


if __name__ == "__main__":
    unittest.main()
