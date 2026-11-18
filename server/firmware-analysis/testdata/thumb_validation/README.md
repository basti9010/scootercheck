# Controlled ARM/Thumb validation firmwares (Phase 2.2A)

Synthetic Cortex-M Thumb images for Ghidra headless / FunctionDiff validation.
No scooter logic. Built with a Python Thumb emitter (see `meta/ground_truth.json`).

- `bin/version_a.bin` / `bin/version_b.bin` — base `0x08000000`, processor `ARM:LE:32:Cortex`
- Expected diffs documented in `meta/ground_truth.json`

Automatic detection (Phase 2.2B): `SeedCortexMEntryPoints.java` seeds Reset from the Cortex-M IVT,
sets Thumb context, and discovers callees via literal Thumb pointers / call following — no manual
address list. Optional control script: `CreateKnownThumbFunctions.java` with `addr:name` pairs from
ground truth (validation only).
