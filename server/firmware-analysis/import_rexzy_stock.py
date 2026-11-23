#!/usr/bin/env python3
"""Import Rexzy67/X3-Firmware Stock binaries into ScooterCheck OEM stock library."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

from stock_diff import STOCK_FW_DIR, ensure_stock_dir, list_stock_refs, register_stock_file

ARCHIVE = Path("/var/lib/scootercheck/x3-firmware-archive")
DECRYPT = Path("/opt/scootercheck/decrypt-firm.sh")

MODEL_MAP = {
    "F3-F3PRO": "f3",
    "G3": "g3",
    "GT3": "gt3",
    "ZT3": "zt3",
}


def slug_ver(ver: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", ver)


def parse_stock_path(p: Path) -> tuple[str, str, str]:
    parts = p.parts
    i = parts.index("Stock")
    folder_model = parts[i - 1]
    controller = parts[i + 1]
    model = MODEL_MAP.get(folder_model, folder_model.lower())
    ctype = "BMS" if controller.upper() == "MBS" else controller.upper()
    return folder_model, model, ctype


def main() -> None:
    ensure_stock_dir()
    registered: list[dict] = []
    skipped: list[str] = []
    errors: list[str] = []
    seen_sha: set[str] = set()

    bins = sorted(ARCHIVE.rglob("Stock/*/FIRM_*.bin"))
    print(f"found FIRM bins: {len(bins)}")
    for p in bins:
        try:
            folder_model, model, ctype = parse_stock_path(p)
        except Exception as e:
            errors.append(f"{p}: path parse {e}")
            continue
        ver = re.sub(r"^FIRM_", "", p.name)
        ver = re.sub(r"\.bin$", "", ver)
        data = p.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        if sha in seen_sha:
            skipped.append(f"dup {p}")
            continue
        seen_sha.add(sha)
        label = f"Rexzy67 Stock {folder_model} {ctype} {ver}"
        notes = f"Imported from github.com/Rexzy67/X3-Firmware path={p.relative_to(ARCHIVE)}"
        try:
            ref = register_stock_file(
                data,
                label=label,
                model=model,
                controller_type=ctype,
                version=ver,
                filename=f"rexzy_{model}_{ctype}_{slug_ver(ver)}_{sha[:12]}.bin",
                source="oem",
                region="",
                notes=notes,
            )
            registered.append(ref)
            print(f"OK {model}/{ctype}/{ver} {len(data)}B {sha[:12]}")
        except Exception as e:
            errors.append(f"{p}: {e}")

    zips = sorted(ARCHIVE.rglob("Stock/*/*.zip"))
    print(f"\nstock zips: {len(zips)}")
    extra = 0
    for z in zips:
        try:
            folder_model, model, ctype = parse_stock_path(z)
        except Exception as e:
            errors.append(f"{z}: path parse {e}")
            continue
        ver = z.stem
        firm = z.parent / f"FIRM_{ver}.bin"
        if firm.is_file():
            continue
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            try:
                with zipfile.ZipFile(z) as zf:
                    zf.extractall(td_path)
            except Exception as e:
                errors.append(f"unzip {z}: {e}")
                continue
            enc = next(td_path.rglob("*.enc"), None)
            if enc is None:
                skipped.append(f"no enc in {z}")
                continue
            out = td_path / "out.dec.bin"
            try:
                subprocess.run(
                    [str(DECRYPT), str(enc), str(out)],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
            except Exception as e:
                errors.append(f"decrypt {z}: {e}")
                continue
            if not out.is_file() or out.stat().st_size == 0:
                errors.append(f"empty decrypt {z}")
                continue
            data = out.read_bytes()
            sha = hashlib.sha256(data).hexdigest()
            if sha in seen_sha:
                skipped.append(f"dup decrypt {z}")
                continue
            seen_sha.add(sha)
            label = f"Rexzy67 Stock {folder_model} {ctype} {ver}"
            notes = f"Decrypted from ZIP {z.relative_to(ARCHIVE)} (no FIRM_ sibling)"
            ref = register_stock_file(
                data,
                label=label,
                model=model,
                controller_type=ctype,
                version=ver,
                filename=f"rexzy_{model}_{ctype}_{slug_ver(ver)}_{sha[:12]}.bin",
                source="oem",
                region="",
                notes=notes,
            )
            registered.append(ref)
            extra += 1
            print(f"OK-DEC {model}/{ctype}/{ver} {len(data)}B {sha[:12]}")

    refs = list_stock_refs()
    c = Counter((r.get("model"), r.get("controllerType")) for r in refs)
    print("\n=== SUMMARY ===")
    print("registered_this_run", len(registered), "extra_from_zip", extra)
    print("skipped", len(skipped), "errors", len(errors))
    print("stock_fw_dir", STOCK_FW_DIR)
    print("total_refs", len(refs))
    print("trusted", sum(1 for r in refs if r.get("source") in ("oem", "serial")))
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")
    for e in errors[:30]:
        print("ERR", e)
    Path("/tmp/stock_import_summary.json").write_text(
        json.dumps(
            {
                "registered": len(registered),
                "extraFromZip": extra,
                "totalRefs": len(refs),
                "byModelType": {f"{a}/{b}": n for (a, b), n in c.items()},
                "errors": errors,
                "skippedCount": len(skipped),
                "archiveFiles": sum(1 for _ in ARCHIVE.rglob("*") if _.is_file()),
            },
            indent=2,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
