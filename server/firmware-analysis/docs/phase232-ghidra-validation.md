# Phase 2.3.2 — Ghidra validation (Fixtures)

Kontrollierte Fixture-Suite unter `testdata/phase232/fixtures/`:

- **Ein** `ground_truth.json` mit `cases[]` (`id`, `addressA`, `addressD`, `expectDetect`) für alle Varianten.
- Varianten **A–E** mit identischer Programmstruktur (Mnemonics, Calls, CFG).
- Metriken: Precision/Recall, **TN**, **F1** (`evaluate_detection_quality`) — nur für Fixtures.
- **Dataflow-Provenance**: `GHIDRA_EXPORTED` | `MNEMONIC_DERIVED` | `PARTIAL` | `NOT_AVAILABLE`.
- **Truncation**: `resultLimits` in Activation-Forensics, Conditional Logic und Evidence Graph.

Tests: `test_phase232_validation.py`