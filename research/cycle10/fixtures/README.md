# Cycle 10 — Ghidra headless execution fixtures (Agent B)

Synthetic Cortex-M Thumb only. **No** real ZT3 / encrypted FIRM plaintext.

| Artifact | Role |
|----------|------|
| `synthetic_cortex_m_thumb.bin` | Copy of Cycle-7/8/9 512 B IVT stub (stable SHA-256) |
| `run_ghidra_headless_synthetic.sh` | SKIP-safe headless runner + Cycle-10 nine-point proof JSON |
| `validate_ghidra_prereqs.py` | Preflight: fixture IVT + headless resolution + SHA-256 bind + env probe |
| `FREIGABE_GHIDRA_HOST.md` | What Freigabe / host / CI need for a real execution pass |

Cycle-10 proof points: **Install · Import · Architecture · Static analysis · Functions · CFG · JSON export · Persist results · SHA-256 binding**.

```bash
./run_ghidra_headless_synthetic.sh
# With Ghidra:
# GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC \
# GHIDRA_SCRIPT_DIR=../../../server/firmware-analysis/ghidra_scripts \
# ./run_ghidra_headless_synthetic.sh
```

Exit 0 on SKIP (`MISSING_PREREQUISITE`). Exit non-zero only when Ghidra is advertised but the run fails, or when the SKIP path finds fabricated export artifacts.

**Never** treat `ghidraConfigured=true` (public `/health`) as execution proof.  
**Never** fabricate `.functions.json` / `.callgraph.json` / `.dec.c`.

Upstream assets: `research/cycle9/fixtures/`, `research/cycle8/fixtures/`, `server/firmware-analysis/ghidra_scripts/`.
