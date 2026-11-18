#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

from stock_diff import _filter_refs, _load_refs

ARCHIVE = Path("/var/lib/scootercheck/x3-firmware-archive")
MANIFEST = Path("/var/lib/scootercheck/stock-fw/manifest.json")
MODEL_MAP = {"F3-F3PRO": "f3", "G3": "g3", "GT3": "gt3", "ZT3": "zt3"}


def main() -> None:
    idx: dict[str, set[tuple[str, str, str, str]]] = defaultdict(set)
    for p in ARCHIVE.rglob("Stock/*/FIRM_*.bin"):
        parts = p.parts
        i = parts.index("Stock")
        folder = parts[i - 1]
        model = MODEL_MAP.get(folder, folder.lower())
        ctype = parts[i + 1].upper()
        if ctype == "MBS":
            ctype = "BMS"
        ver = re.sub(r"^FIRM_", "", p.name).removesuffix(".bin")
        sha = hashlib.sha256(p.read_bytes()).hexdigest()
        idx[sha].add((model, ctype, ver, str(p.relative_to(ARCHIVE))))

    entries = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for e in entries:
        sha = e.get("sha256")
        aliases = sorted(idx.get(sha) or [])
        if not aliases:
            continue
        models = sorted({a[0] for a in aliases})
        ctypes = sorted({a[1] for a in aliases})
        vers = sorted({a[2] for a in aliases})
        ctype = ctypes[0] if len(ctypes) == 1 else e.get("controllerType")
        e["model"] = models[0]
        e["controllerType"] = ctype
        e["version"] = vers[0] if len(vers) == 1 else e.get("version")
        model_label = "/".join(models)
        ver_label = vers[0] if len(vers) == 1 else "|".join(vers)
        e["label"] = f"Rexzy67 Stock {model_label} {ctype} {ver_label}"
        paths = "; ".join(a[3] for a in aliases)
        e["notes"] = f"OEM from Rexzy67/X3-Firmware; models={','.join(models)}; paths={paths}"
        e["models"] = models

    MANIFEST.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    multi = [e for e in entries if len(e.get("models") or []) > 1]
    print("updated", len(entries), "multi-model", len(multi))
    for e in multi[:20]:
        print(" ", e["label"], e["sha256"][:12])

    refs = _load_refs()
    g3_ble = _filter_refs(refs, models=["g3"], controller_type="BLE")
    g3_vcu = _filter_refs(refs, models=["g3"], controller_type="VCU")
    print("g3 BLE candidates", len(g3_ble))
    print("g3 VCU candidates", len(g3_vcu))


if __name__ == "__main__":
    main()
