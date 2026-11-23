# Cycle 7 Agent C — Ghidra Integration Design

**Status:** design + synthetic fixture (no production decrypt, no activation reconstruction)  
**Branch context:** `cursor/server-fw-analysis-c7-b100`  
**Sources read via `git show`:** `origin/cursor/unified-investigation-flow-b100:server/firmware-analysis/`  
**Runner Ghidra availability:** **NOT AVAILABLE** (`GHIDRA_HOME` unset, `analyzeHeadless` not on PATH / `/opt/ghidra`)

---

## 1. Goal

Define how headless Ghidra plugs into ScooterCheck firmware analysis for Cycle 7, with a **tiny synthetic Cortex-M Thumb blob** suitable for import/export smoke tests. Align export JSON with iOS `FirmwareDeepAnalysisModels` and server `ExportFunctionAnalysis` / `function_analysis.py`.

### Hard bans (this cycle)

| Ban | Rationale |
|-----|-----------|
| No tuning / activation-sequence reconstruction | Out of scope for Agent C; Activation Forensics is a separate Phase-2.3 surface |
| No decrypt of Cycle-6 `FIRM.bin.enc` | Ciphertext-only research; synthetic plaintext only |

---

## 2. Server surface (unified-investigation-flow)

### 2.1 Python driver

| File | Role |
|------|------|
| `ghidra_decompile.py` | Resolves `analyzeHeadless` via `GHIDRA_HEADLESS` → `GHIDRA_HOME/support/analyzeHeadless` → nested `ghidra_*` → PATH → `/opt/ghidra/ghidra_*/…`; runs BinaryLoader import + postScripts |
| `function_analysis.py` | Loads `.functions.json` / `.callgraph.json`; builds poll-safe `FirmwareFunctionAnalysisSummary` |
| `ghidra_reproducibility.py` | Semantic hash / multi-run stability |
| `cortex_m_ivt.py` | IVT SP/Reset heuristics (`likely`, `resetFileOffset`, Thumb bit) |
| `analysis_profile.py` | Versioned profile + `analysisProfileHash` embedded into exports |

Default import knobs (when identify does not override):

- **Processor:** `ARM:LE:32:Cortex`
- **Loader:** `BinaryLoader`
- **Base:** `0x08000000` (`-loader-baseAddr`)
- **Pre-script:** `SeedCortexMEntryPoints.java` (unless `GHIDRA_SEED_IVT=0`)
- **Timeout:** ≥ 600 s production; research smoke uses 180 s

### 2.2 Ghidra scripts (`ghidra_scripts/`)

| Script | Phase | Output |
|--------|-------|--------|
| `SeedCortexMEntryPoints.java` | `-preScript` | Creates Thumb functions from IVT + call/literal follow |
| `ExportAllDecompiled.java` | `-postScript` | Single `.c` decompilation dump |
| `ExportSpeedXrefs.java` | `-postScript` | `.speeds.json` |
| `ExportLimitFunctions.java` | `-postScript` | `.limits.c` |
| `ExportFunctionAnalysis.java` | `-postScript` | `.functions.json` (**canonical function inventory**) |
| `ExportCallGraph.java` | `-postScript` | `.callgraph.json` |
| `ExportDataFlowSummary.java` | `-postScript` | `.dataflow.json` (Phase 2.3.1) |
| `CreateKnownThumbFunctions.java` | optional | Named Thumb seed helpers |

Headless command shape (from `run_ghidra_decompile`):

```text
analyzeHeadless <projDir> ScooterCheckFW \
  -import <plaintext.bin> \
  -processor ARM:LE:32:Cortex -cspec default \
  -loader BinaryLoader -loader-baseAddr 0x08000000 \
  -scriptPath <ghidra_scripts> \
  [-preScript SeedCortexMEntryPoints.java] \
  -postScript ExportAllDecompiled.java <out.c> \
  -postScript ExportSpeedXrefs.java <out.speeds.json> \
  -postScript ExportLimitFunctions.java <out.limits.c> \
  -postScript ExportFunctionAnalysis.java <out.functions.json> \
  -postScript ExportCallGraph.java <out.callgraph.json> \
  [-postScript ExportDataFlowSummary.java <out.dataflow.json>] \
  -deleteProject
```

---

## 3. Synthetic fixture

| Artifact | Path |
|----------|------|
| Blob | `research/cycle7/fixtures/synthetic_cortex_m_thumb.bin` |
| Runner | `research/cycle7/fixtures/run_ghidra_headless_synthetic.sh` |

### 3.1 Blob layout (512 bytes — **not** scooter FW)

| Offset | Content |
|--------|---------|
| `0x00` | IVT word 0: initial SP `0x20020000` (SRAM window) |
| `0x04` | IVT word 1: Reset `0x08000101` (VA `0x08000100` + Thumb bit) |
| `0x08` | NMI → `0x08000111` |
| `0x0C` | HardFault → `0x08000119` |
| `0x10`…`0x3F` | Remaining system vectors zeroed |
| `0x100` | `reset_handler`: Thumb `nop; nop; nop; bx lr` (`00 BF` ×3, `70 47`) |
| `0x110` | NMI stub: `nop; bx lr` |
| `0x118` | HardFault stub: `nop; nop; bx lr` |
| `0x180` | ASCII marker `SYNTH_C7_NOT_SCOOTER_FW\0` |

- **SHA-256:** `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea` (stable content hash of this fixture)
- **Size:** 512 bytes  
- Compact image (`< 0x400`) → `SeedCortexMEntryPoints` trusts Reset primarily (matches server script `compactImage` path).

### 3.2 Runner behaviour

```bash
./research/cycle7/fixtures/run_ghidra_headless_synthetic.sh
```

1. Resolve headless like `ghidra_decompile._headless_bin()`.
2. **If missing:** print `SKIP: Ghidra headless not available …` and **exit 0**.
3. **If present:** BinaryLoader import at `0x08000000`; if `GHIDRA_SCRIPT_DIR` points at `ghidra_scripts`, also run `SeedCortexMEntryPoints` + `ExportAllDecompiled` + `ExportFunctionAnalysis`.
4. Writes under `research/cycle7/fixtures/out_synthetic/` (gitignored recommended).

**This runner Ghidra check:** SKIP (not installed).

---

## 4. Expected JSON finding schema

Two layers: (A) full Ghidra export artifact, (B) poll / iOS `FirmwareDeepAnalysisResult` summary. Cycle-7 consumers should treat (A) as the source of truth for function-level findings and map into (B).

### 4.A `ExportFunctionAnalysis` → `.functions.json`

Produced by `ExportFunctionAnalysis.java` (`schemaVersion: 1`, `featuresVersion: 3`).

```json
{
  "schemaVersion": 1,
  "featuresVersion": 3,
  "program": "synthetic_cortex_m_thumb.bin",
  "processor": "ARM:LE:32:Cortex",
  "imageBase": "00000000",
  "actualImageBase": "00000000",
  "requestedLoaderBase": "0x08000000",
  "memoryBlockStart": "08000000",
  "resetHandlerAddress": "0x08000100",
  "firmwareFileOffset": 256,
  "functions": [
    {
      "address": "08000100",
      "name": "reset_handler",
      "size": 8,
      "basicBlocks": 1,
      "cfgEdges": 0,
      "calls": [],
      "calledBy": [],
      "constants": [],
      "strings": [],
      "mnemonics": ["nop", "nop", "nop", "bx"],
      "branchMnemonicCount": 1,
      "parameterCount": 0,
      "memoryReadCount": 0,
      "memoryWriteCount": 0,
      "compareOpCount": 0,
      "dataReferenceCount": 0,
      "fingerprint": "<sha-like hex>",
      "confidence": "medium",
      "processor": "ARM:LE:32:Cortex",
      "quality": "cfg-ok"
    }
  ],
  "functionCount": 1,
  "truncated": false,
  "truncatedSkipped": 0,
  "maxFunctions": 2500,
  "analysisProfile": {
    "analysisProfileVersion": "…",
    "analysisProfileHash": "…",
    "processorArchitecture": "ARM:LE:32:Cortex",
    "requestedLoaderBase": "0x08000000",
    "seedCortexMEntryPoints": true
  }
}
```

Notes:

- `analysisProfile` may be injected post-export by `ghidra_decompile.py` (summarize_profile_for_poll).
- Fingerprint semantics are stable under `analyzerCompat` / features that are marked non-fingerprint (`branchMnemonicCount`, memory/compare/dataflow counts).
- Address strings are Ghidra-style (often without `0x` prefix for function `address`).

### 4.B Call graph `.callgraph.json` (companion)

`ExportCallGraph.java` uses `schemaVersion: 2`, `featuresVersion: 2`:

```json
{
  "schemaVersion": 2,
  "featuresVersion": 2,
  "program": "…",
  "edges": [
    {
      "from": "08000100",
      "to": "08000110",
      "fromName": "reset_handler",
      "toName": "…",
      "kind": "DIRECT_CALL",
      "evidence": "static"
    }
  ],
  "edgeCount": 0,
  "functionCount": 1,
  "truncated": false
}
```

Kinds: `DIRECT_CALL`, `INDIRECT_CALL`, `INTERNAL_BRANCH`, `TAIL_CALL`, `UNRESOLVED_CALL`, `UNKNOWN_CONTROL_FLOW`.

### 4.C Poll / iOS mapping (`FirmwareDeepAnalysisModels`)

| Export / server field | iOS model |
|----------------------|-----------|
| `function_analysis.summarize_for_poll` | `FirmwareFunctionAnalysisSummary` (`ok`, `functionCount`, `truncated`, `processor`, `notes`, `analysisLimitations`, `sampleFunctions`) |
| sample fn `{address,name,size,basicBlocks,fingerprint,confidence}` | `FirmwareFunctionBrief` |
| address layout fields | `FirmwareGhidraAddressLayout` |
| profile hash / knobs | `FirmwareAnalysisProfile` / `analysisProfileHash` |
| IVT heuristic (`cortex_m_ivt.parse_ivt`) | `FirmwareCortexMIvt` |
| reproducibility | `FirmwareGhidraReproducibility` |
| deep result envelope | `FirmwareDeepAnalysisResult` (`schemaVersion`, `sources`, `subjectSHA256`, `functionAnalysis`, `callGraph`, `ghidraAddressLayout`, …) |

`FirmwareDeepAnalysisResult.currentSchemaVersion = 1`. Ghidra is one of several `sources`; findings must remain schema-valid — freestyle decompiler prose is not a finding.

#### Classified / speed findings (orthogonal to function export)

When Ghidra speed xrefs / limit scripts feed the pipeline, app findings stay:

```json
{
  "id": "speed-…",
  "kmh": 22.0,
  "packedU16": 8704,
  "role": "legalCap",
  "evidence": "…",
  "source": "ghidraServer",
  "confidence": "medium"
}
```

(`FirmwareSpeedLimitFinding` — **not** reconstructed from Cycle-6 ciphertext in this agent.)

### 4.D Minimal Cycle-7 “finding” envelope (research)

For Agent C / synthesis, prefer this thin wrapper around a successful synthetic export:

```json
{
  "schemaVersion": 1,
  "kind": "ghidraFunctionAnalysis",
  "subjectSHA256": "3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea",
  "subject": "synthetic_cortex_m_thumb.bin",
  "processor": "ARM:LE:32:Cortex",
  "requestedLoaderBase": "0x08000000",
  "ghidraAvailable": false,
  "status": "SKIPPED_NO_GHIDRA",
  "functionAnalysis": null,
  "notes": [
    "Fixture present; headless not configured on runner.",
    "No Cycle-6 enc decrypt attempted.",
    "No activation/tuning sequence reconstruction."
  ],
  "caveats": [
    "Synthetic blob only — not vehicle firmware evidence."
  ]
}
```

When Ghidra runs successfully, set `ghidraAvailable: true`, `status: "OK"`, and embed the loaded `function_analysis.load_function_analysis(...)` object (or poll summary) under `functionAnalysis`.

---

## 5. Integration checklist (Cycle 7 → server)

1. Keep synthetic fixture + SKIP-safe script in `research/cycle7/fixtures/`.
2. On a host with Ghidra:  
   `GHIDRA_HOME=… GHIDRA_SCRIPT_DIR=server/firmware-analysis/ghidra_scripts ./run_ghidra_headless_synthetic.sh`
3. Assert: non-empty `.functions.json` with `schemaVersion`/`functions`; Reset near `0x08000100`; marker string optional.
4. Wire CI: script exit 0 on SKIP; fail only when Ghidra is advertised (`GHIDRA_HOME` set) but headless fails.
5. Do **not** point this smoke at Cycle-6 `uploads/` / `FIRM.bin.enc`.

---

## 6. Deliverables

| Path | Purpose |
|------|---------|
| `research/cycle7/agent_c/REPORT_GHIDRA_INTEGRATION.md` | This design |
| `research/cycle7/fixtures/synthetic_cortex_m_thumb.bin` | 512 B Cortex-M Thumb IVT stub |
| `research/cycle7/fixtures/run_ghidra_headless_synthetic.sh` | Headless import (+ optional export) or SKIP exit 0 |

**Ghidra on this runner:** unavailable (SKIP path verified).
