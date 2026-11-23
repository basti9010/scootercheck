# Agent A ingest + PM wire

Source: [Server Diagnostics](bc-58703370-a4b0-54c5-bc6a-75fbed37d6ee)  
Branch: `cursor/server-diagnostics-agent-a-b100` @ `fecf9b9`

## Merged
`diagnostics_models.py` · `diagnostics_status.py` · `diagnostics_routes.py`  
PM: `APP.include_router(...)` in `app.py`; hooked `diagnose_tea` + `run_ghidra_diagnostics_selftest`.  
Auth: true admin only (JWT admin / ADMIN_API_TOKEN); refuse open + shared-token-admin.

## Tests
`test_diagnostics_routes` + tea + ghidra → **32 OK**
