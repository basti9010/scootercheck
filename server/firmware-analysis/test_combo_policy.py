#!/usr/bin/env python3
import unittest

import combo_policy


class ComboPolicyTests(unittest.TestCase):
    def test_drops_speculative_gas_brake(self) -> None:
        raw = [
            "Vermutete Soft-/Power-Kombi: Umschalten 20 ↔ 99 km/h (häufig Gas + Bremse + Power — Live-Test nötig)",
            "Board-Heuristik zt3-vcu-at32: Gas + Bremse halten und Power einschalten",
            "YARA: Soft-Unlock-typisch",
            "Live-Kombination (SN): Gas+Bremse+Power",
            "Belegt: Register 0x46 byte[0xe]=1 → 99 km/h",
        ]
        out = combo_policy.sanitize_combo_summaries(raw)
        self.assertEqual(
            out,
            [
                "Live-Kombination (SN): Gas+Bremse+Power",
                "Belegt: Register 0x46 byte[0xe]=1 → 99 km/h",
            ],
        )

    def test_sanitize_trigger(self) -> None:
        self.assertEqual(
            combo_policy.sanitize_transition_trigger("Gas + Bremse halten und Power einschalten"),
            "Aus Code nicht als Tastenfolge belegt",
        )
        self.assertEqual(
            combo_policy.sanitize_transition_trigger("Belegt: NB index 0x46"),
            "Belegt: NB index 0x46",
        )

    def test_sanitize_result_strips_board_hypothesis(self) -> None:
        result = {
            "comboSummaries": ["Panic-Heuristik g3: Extra-Taste"],
            "modeTransitions": [
                {
                    "id": "t1",
                    "title": "Einschalt-Kombi (vermutet)",
                    "trigger": "Gas + Bremse",
                    "effect": "open",
                },
                {
                    "id": "t2",
                    "title": "Zwei Limit-Welten im Code",
                    "trigger": "Einschalt-/Tastenkombi oder Panic (modellabhängig)",
                    "effect": "20↔99",
                },
            ],
            "boardPinout": {
                "id": "g3-vcu",
                "notes": "x",
                "defaultComboHypothesis": "Gas + Bremse halten und Power einschalten",
            },
        }
        out = combo_policy.sanitize_result_combos(result)
        self.assertEqual(out["comboSummaries"], [])
        self.assertTrue(all(t["id"] != "t1" for t in out["modeTransitions"]))
        dual = next(t for t in out["modeTransitions"] if t["id"] == "t2")
        self.assertEqual(dual["trigger"], "Aus Code nicht als Tastenfolge belegt")
        self.assertNotIn("defaultComboHypothesis", out["boardPinout"])


if __name__ == "__main__":
    unittest.main()
