# Cycle 10 – Access / E2E / TEA

## Access (LIVE)
| Item | Status |
|------|--------|
| SSH hetzner_scootercheck | ABSENT |
| App secrets | empty |
| GHIDRA_HOME / analyzeHeadless | ABSENT |
| Public /health | ok; decrypt/ghidra flags true; apiTokenGrantsAdmin=true |

## Full analysis path
Firmware→Upload→SHA→Job→Worker→Ghidra→JSON→Auth fetch→Report  
On this VM / without Freigabe: **NOT END_TO_END_VERIFIED**  
Local staging (C9) covered upload/SHA/job/process/auth without live Ghidra.

## TEA
SUPPORTED hook · UNSUPPORTED binary in repo · NOT_TESTED here · UNKNOWN prod success
