# Cycle 9 – E2E / TEA / ZT3 (Phases 4–6)

Stand: 2026-11-23 Europe/Berlin  
Tip: `cursor/prod-pipeline-forensic-c9-b100`

## Synthetic local E2E (FastAPI TestClient)

Stations exercised locally (JWT staging, Ghidra disabled, DECRYPT_CMD unset):

| # | Station | Result |
|---|---------|--------|
| 1 | API upload | PASS (`test_cycle9_server_validation`) |
| 2 | SHA-256 | PASS (server wins over client meta) |
| 3 | Job create | PASS |
| 4 | Background `process_job` | PASS |
| 5 | Ghidra Headless | SKIP / blocked path PASS (RAW4TFT UnboundLocal fixed) |
| 6 | Result generation | PASS |
| 7 | Auth result fetch | PASS (owner 200 / foreign 404) |
| 8 | InvestigationStore (iOS) | OFFLINE unit/integration PASS; live service **NOT RUN** |

**END_TO_END_VERIFIED (full stack incl. live Ghidra + iOS against prod): NO**

## NinebotTEA

| Item | Grade |
|------|-------|
| DECRYPT_CMD hook | SUPPORTED |
| Wrapper in-tree | SUPPORTED |
| Binary/keys in repo / Cloud VM | UNSUPPORTED / absent |
| Live decrypt | NOT_TESTED |
| Prod `/health` decryptConfigured | true → UNKNOWN success |

No key recovery. No vehicle writes.

## Cycle 6 ZT3 packs (read-only)

File A `ZT3_VCU_48KMH_5d51.zip` · File B `ZT3_________panicsystem_9646.zip`  
CONFIRMED from Cycle 6: container schema, hashes, shared 2008-byte prefix, high entropy.  
Cycle 9: **no decrypt**; analysis remains CONFIRMED container / INCOMPLETE plaintext ISA.

## CI note

C8 tip `d411896` Actions run 45258903038 ended **cancelled** (not a verified green Hub build).  
C7 `b60df88` remains **354/0 SUCCESS**. C9 tip CI pending after security merge.
