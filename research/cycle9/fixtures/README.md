# Cycle 9 — Ghidra headless fixtures (Agent B)

Synthetic Cortex-M Thumb only. **No** real ZT3 / encrypted FIRM plaintext.

| Artifact | Role |
|----------|------|
| `synthetic_cortex_m_thumb.bin` | Copy of Cycle-7/8 512 B IVT stub (stable SHA-256) |
| `run_ghidra_headless_synthetic.sh` | SKIP-safe headless runner + Cycle-9 proof-point JSON |
| `validate_ghidra_prereqs.py` | Preflight: fixture IVT + headless resolution + env probe (no fake exports) |

Cycle-9 proof points: Import · Architecture · Static analysis · Function detection · Control-flow · JSON export · Error handling.

```bash
./run_ghidra_headless_synthetic.sh
# With Ghidra:
# GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC \
# GHIDRA_SCRIPT_DIR=../../../server/firmware-analysis/ghidra_scripts \
# ./run_ghidra_headless_synthetic.sh
```

Exit 0 on SKIP (missing `analyzeHeadless`). Exit non-zero only when Ghidra is advertised but the run fails, or when the SKIP path finds fabricated export artifacts.

Upstream assets also live at `research/cycle8/fixtures/` and `server/firmware-analysis/ghidra_scripts/`.
