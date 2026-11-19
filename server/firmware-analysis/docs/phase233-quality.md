# Phase 2.3.3 — Quality metrics & detection

## Dataflow quality (`semantic_dataflow.py`)

`compute_dataflow_quality_metrics(sdf_full)` ergänzt Summaries um:

- `dataflowExportCoverage` — GHIDRA_EXPORTED + `quality=ok` / total × 100
- `parameterRecoveryCoverage` — `parameterCount` nicht-null / total
- `memoryAccessCoverage` — reads>0 oder writes>0 / total
- `dataReferenceCoverage` — `dataReferenceCount`>0 / total
- `unresolvedDataflowCount` — `quality=missing` oder Provenance PARTIAL/NOT_AVAILABLE
- `semanticConfidenceDistribution` — Zähler nach Provenance

Enthalten in `analyze_semantic_dataflow` → `summary.dataflowQualityMetrics` und Poll-Summary.

## Activation detection (2.3.3)

Name-unabhängige Strukturpfade (≥1 starkes Signal):

- Fan-in ≥3 + Load + Conditional
- MMIO-Konstante + Caller + Conditional
- `parameterCount`≥1 + Compare + Branch + Store
- Event-Queue-ähnlich: `calledBy`≥2 + Store + Compare≥2 + Load≥1

`evaluate_detection_quality` enthält zusätzlich **specificity** = TN/(TN+FP).

## Fixtures

- `testdata/phase233/fixtures/` — ≥40 Fälle, Varianten A–G
- `testdata/phase233/ghidra_export_gt/` — 10 synthetische Export-GT-Funktionen
- `testdata/phase233/manual/annotation.json` — F3-Stratifizierung, `independence: SINGLE_ANNOTATOR_NOT_BLIND`

## API Pagination

`GET /v1/firmware/jobs/{id}/activation-forensics?offset=&limit=` schneidet nur die JSON-Antwort (`inputHandlerFindings`, conditional `findings`); Datei auf Disk bleibt vollständig.

## Tests

- `test_phase233_quality.py`
- `test_phase233_ghidra_export_gt.py`


## Benchmark snapshot (Phase 2.3.3)

### Ground truth

- 42 cases: 19 positive, 23 negative (incl. 2 `ambiguous_weak` as negative/expectAmbiguous)
- Variants A–G share the same case list

### Detection (fixture A–G)

| Variant | TP | FP | FN | TN | P | R | F1 | Spec |
|---------|----|----|----|----|---|---|----|------|
| A_named | 15 | 1 | 4 | 22 | 0.9375 | 0.7895 | 0.8571 | 0.9565 |
| B_generic | 14 | 0 | 5 | 23 | 1.0 | 0.7368 | 0.8485 | 1.0 |
| C_no_strings | 13 | 0 | 6 | 23 | 1.0 | 0.6842 | 0.8125 | 1.0 |
| D_shifted | 13 | 0 | 6 | 23 | 1.0 | 0.6842 | 0.8125 | 1.0 |
| E_anon_meta | 13 | 0 | 6 | 23 | 1.0 | 0.6842 | 0.8125 | 1.0 |
| F_generic_no_signature | 14 | 0 | 5 | 23 | 1.0 | 0.7368 | 0.8485 | 1.0 |
| G_partial_dataflow | 15 | 1 | 4 | 22 | 0.9375 | 0.7895 | 0.8571 | 0.9565 |

Trade-off vs Phase 2.3.2 (14-case GT, C–E recall 0.4167): C–E recall raised to ~0.68 with FP=0 on anonymized variants; A/G keep one FP.

### Real firmware negative control (phase232 exports, AF 2.3.3)

- F3 (181 fn): handlers 28 (INDICATIVE 10 / SPECULATIVE 18); FG=0; dataflowExportCoverage 95.58%; parameterNonZeroCoverage 0.0; conditional truncated 24/104
- G3 (220 fn): handlers 32 (INDICATIVE 13 / SPECULATIVE 19); FG=0; dataflowExportCoverage 96.82%; parameterNonZeroCoverage 0.0; conditional truncated 54/134

### Manual annotation

- 36 F3 functions; `independence: SINGLE_ANNOTATOR_NOT_BLIND`

### Python regression

- 276 passed, 5 skipped (~1.55s)

### Deploy

- `bash deploy/phase1-rollout.sh` dry-run OK; no prod changes

### JWT / pagination

- `test_phase233_jwt_artifacts.py` + restored `test_phase232_jwt_dataflow.py`
- Response key: `responsePagination`
