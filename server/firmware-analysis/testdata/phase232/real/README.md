# Phase 2.3.2 — Live Ghidra dataflow exports (isolated)

Community stock VCU binaries analyzed with Ghidra 12.2 headless on an isolated `/tmp` tree (no production job mutation).

| Firmware | SHA-256 | Functions | Dataflow ok/partial/missing | Coverage |
|---|---|---|---|---|
| F3 VCU 1.5.8 | `895e0642…a35badc4` | 181 | 173 / 7 / 1 | 95.58% exported |
| G3 VCU 1.5.13 | `1f1e05eb…093b108` | 220 | 213 / 7 / 0 | 96.82% exported |

- Processor: `ARM:LE:32:Cortex`
- Profile: `2.2G.1` / hash `c0f507820a1457a1af98c2a66352db531f2f4ad1bcf72bc32c58e307e3f41de7`
- Scripts: SeedCortexMEntryPoints + ExportFunctionAnalysis + ExportCallGraph + ExportDataFlowSummary
- F3 reproducibility: two runs → identical normalized dataflow SHA-256 `038d7cf5…13b3b076`
- Community origin — **not** OEM-verified ground truth
- See `run_meta.json` and `isolated_e2e_result.json`
