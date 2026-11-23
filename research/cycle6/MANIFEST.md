# Cycle 6 Firmware Research Lab – Manifest

**Korrektur:** Es liegen **zwei** Untersuchungsdateien vor (nicht drei).  
Kein REPORT_C.

| ID | Upload-Name | Arbeitsverzeichnis | ZIP SHA-256 |
|----|-------------|-------------------|-------------|
| **A** | `ZT3_VCU_48KMH_5d51.zip` | `file_a_zt3_vcu_48kmh/` | `64d46af6f156ae6a8a09e4b04b80a55fd1aecc16433f839f1d19682f8397bcec` |
| **B** | `ZT3_________panicsystem_9646.zip` | `file_b_zt3_panicsystem/` | `6bff28e813c54837d3bb3ac09e8b4721eb75c76529728f0b8c680b4879adbc40` |

Originale unter `uploads/` unverändert. Arbeitskopien: `original.zip` (gitignored).

## Inner payloads

| ID | Member | Size | SHA-256 | MD5 (matches info.json) |
|----|--------|------|---------|-------------------------|
| A | FIRM.bin.enc | 58504 | `a5b0e026…f7459d` | `59857e768098530715639e011bbfa36b` |
| A | info.json | 302 | `a70d73ce…f20bc2` | — |
| B | FIRM.bin.enc | 58504 | `02e46e8a…472ebc` | `9235a01f1b022bfe9197ed08739de60a` |
| B | info.json | 302 | `db49e0eb…f1b8c4a` | — |

## Encrypted payload relationship (CONFIRMED)

- Gleiche Größe 58504  
- Identischer Prefix **2008** Bytes  
- Danach divergierend: **56288** unterschiedliche Bytes  
- Entropie A≈7.997 / B≈7.997 → Ciphertext-Charakter  
- `identical=false`
