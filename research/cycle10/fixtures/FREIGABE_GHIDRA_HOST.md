# Freigabe — what a host/CI needs for Cycle-10 Ghidra execution PASS

This Cloud Agent VM has **no** Ghidra install and must **not** download multi‑hundred‑MB Ghidra zips unless already cached and policy‑approved. To turn Cycle‑10 Agent B from `SKIPPED_NO_GHIDRA` into a real PASS, Freigabe / ops must provide:

## Minimum install

| Requirement | Notes |
|-------------|-------|
| Ghidra public release unpacked | e.g. `/opt/ghidra/ghidra_*_PUBLIC` |
| `support/analyzeHeadless` executable | Resolved via `GHIDRA_HOME` or `GHIDRA_HEADLESS` or PATH |
| JDK 17+ on PATH | OpenJDK 21 is fine; Java alone ≠ Ghidra |
| Writable project/out dirs | Runner uses `research/cycle10/fixtures/out_synthetic/` |

## Environment (host or CI secret / env)

```bash
export GHIDRA_HOME=/opt/ghidra/ghidra_12.2_PUBLIC   # or whatever version
# optional override:
# export GHIDRA_HEADLESS=$GHIDRA_HOME/support/analyzeHeadless
export GHIDRA_SCRIPT_DIR=<repo>/server/firmware-analysis/ghidra_scripts
```

## Proof command (synthetic only)

```bash
cd <repo>/research/cycle10/fixtures
./run_ghidra_headless_synthetic.sh
```

Expect: `overallStatus=PASS`, non-empty `synthetic.functions.json` + `synthetic.callgraph.json`, `sha256Binding.matches=true` for fixture `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea`.

## Explicit non-goals for Freigabe on this agent path

- Do **not** decrypt or analyze real ZT3 / Cycle-6 `FIRM.bin.enc` plaintext here
- Do **not** treat production `/health` `ghidraConfigured=true` as PASS
- Do **not** invent export JSON to green the checklist
- Large Ghidra download into this Cloud VM: only if cached + policy-safe; prefer documenting `MISSING_PREREQUISITE`

## Hetzner live path (separate from this VM)

Live Hetzner execution additionally needs deploy SSH / admin API (see `research/cycle10/CYCLE10_KICKOFF.md`). That is Agent A / deploy scope — Agent B only proves headless on synthetic when tools exist.
