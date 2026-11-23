# Phase 2.3.1 — Semantic Input Analysis & Evidence Quality

## Ziel

Praxistauglichkeit der Activation Forensics Engine an realen Ghidra-Exporten prüfen und Erkennungsqualität verbessern (name-unabhängig, Datenfluss, Conditional-Logic-Klassen, Evidenzaggregation).

## Harte Grenzen

* Keine Rekonstruktion / Ausgabe von Aktivierungs- oder Umgehungssequenzen.
* Keine Precision/Recall für reale Firmware ohne unabhängige Ground Truth.
* Community-Referenzen ≠ OEM-verifiziert.
* Kein Produktivdeploy ohne Freigabe; Dry-Run über `deploy/phase1-rollout.sh`.

## Neue Module

| Komponente | Datei |
|---|---|
| Semantic Data Flow | `semantic_dataflow.py` |
| Ghidra Export | `ghidra_scripts/ExportDataFlowSummary.java` → `*.dataflow.json` |
| Activation Forensics 2.3.1 | `activation_forensics.py` (SCHEMA 2, PHASE `2.3.1`) |
| Tests | `test_phase231_semantic.py`, Fixtures unter `testdata/phase231/` |

## API (abwärtskompatibel)

Poll-Felder (kompakt): `semanticDataFlow`, `inputDetectionQuality`, `conditionalLogicQuality`, `activationEvidenceDistribution`, `evidenceGraphQuality`, `analysisLimitations`.

Artefakte (JWT/Ownership):

* `GET /v1/firmware/jobs/{id}/activation-forensics`
* `GET /v1/firmware/jobs/{id}/semantic-dataflow`

## Conditional-Logic-Klassen

`CONDITIONAL_LOGIC_ONLY` · `INPUT_RELATED_CONDITIONAL_LOGIC` · `STATE_RELATED_CONDITIONAL_LOGIC` · `FEATURE_GATE_CANDIDATE` · `NOT_CLASSIFIABLE`

Branches allein erzeugen kein Feature Gate.

## Evidenzaggregation

Zähler: `staticConfirmedCount`, `indicativeCount`, `speculativeCount`, `unknownCount`, `ambiguousCount`.  
Gemischte STATIC_CONFIRMED-Funde → Gesamt `INDICATIVE` (kein pauschales STATIC_CONFIRMED).

## Real-Firmware Negative Control

F3 VCU 1.5.8 / G3 VCU 1.5.13 (Community-Referenzen): strukturelle FUN_*-Kandidaten als `SPECULATIVE`/`weakCandidate`; Feature-Gate-Kandidaten = 0 ohne semantische Namen.
