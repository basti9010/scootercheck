# Phase 2.3 — Activation Forensics

## Ziel

Statische forensische Erkennung **technischer Hinweise** auf Eingabeverarbeitung und undokumentierte Programmstrukturen in Firmwareexporten.

**Nicht** Ziel: Rekonstruktion oder Ausgabe nutzbarer Aktivierungs-/Umgehungssequenzen, Brute-Force, Fahrzeugtests.

## Architektur

Baut auf vorhandenen Komponenten auf (keine zweite RE-Pipeline):

- Ghidra `ExportFunctionAnalysis` / `ExportCallGraph`
- `input_behavior.py`, `function_matcher.py`, `function_diff.py`
- `fsm_runtime.py` (nur kontrollierte Unicorn-Suite)
- `analysis_profile.py` / Referenzkataloge

Neue Engine: `activation_forensics.py`

## Evidenzstufen

| Stufe | Bedeutung |
|---|---|
| `STATIC_CONFIRMED` | Konkrete Codeeigenschaft nachgewiesen — **kein** Fahrzeugbeweis |
| `INDICATIVE` | Mehrere unabhängige Hinweise |
| `SPECULATIVE` | Schwache / namensbasierte Hinweise |
| `UNKNOWN` | Nicht bewertbar |

## API

Poll (kompakt): `activationForensics`, `inputHandlerFindings`, `undocumentedLogic`, `conditionalLogicFindings`, `activationEvidenceGraph`, `analysisLimitations`

Artefakt (JWT/Ownership): `GET /v1/firmware/jobs/{id}/activation-forensics`

## Fixtures

`testdata/phase23/` — harmlose synthetische ARM-Funktionsexporte + Ground Truth. Metriken gelten **nur** für Fixtures.

## Deploy

Dateien in `deploy/phase1-rollout.sh` ergänzt. Kein Produktivdeploy ohne Freigabe.
