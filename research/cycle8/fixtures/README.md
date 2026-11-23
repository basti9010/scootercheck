# Cycle 8 — Ghidra headless fixtures (Agent B)

Synthetic Cortex-M Thumb only. **No** real ZT3 / encrypted FIRM plaintext.

| Artifact | Role |
|----------|------|
| `synthetic_cortex_m_thumb.bin` | Copy of Cycle-7 512 B IVT stub (stable SHA-256) |
| `run_ghidra_headless_synthetic.sh` | SKIP-safe headless runner + proof-point JSON |
| `validate_ghidra_prereqs.py` | Preflight: fixture IVT + headless resolution (no fake exports) |

```bash
./run_ghidra_headless_synthetic.sh
# With Ghidra:
# GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC \
# GHIDRA_SCRIPT_DIR=../../../server/firmware-analysis/ghidra_scripts \
# ./run_ghidra_headless_synthetic.sh
```

Exit 0 on SKIP (missing `analyzeHeadless`). Exit non-zero only when Ghidra is advertised but the run fails.
