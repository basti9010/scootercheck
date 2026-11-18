#!/usr/bin/env python3
"""Crawl public OEM stock firmware mirrors and store them chronologically.

Sources:
  - https://firmware.scooterhacking.org/  (classic Ninebot / Xiaomi)
  - https://github.com/Rexzy67/X3-Firmware (G3 / F3 / GT3 / ZT3 Stock)

Layout under STOCK_ARCHIVE_DIR (default: ./stock-archive):
  {model}/{component}/{YYYY-MM-DD}_{version}.bin
  index.json  — full chronological catalog (newest first per model/component)
  latest.json — newest file per model/component

Optional: --register writes trusted OEM refs into STOCK_FW_DIR via stock_diff.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

UA = {"User-Agent": "ScooterCheck-StockSync/1.0 (+https://github.com/basti9010/scootercheck)"}
SH_BASE = "https://firmware.scooterhacking.org"
REXZY_API = "https://api.github.com/repos/Rexzy67/X3-Firmware/git/trees/main?recursive=1"
REXZY_RAW = "https://raw.githubusercontent.com/Rexzy67/X3-Firmware/main"

# ScooterHacking Utility "Supported Models" ↔ mirror folder IDs
SH_MODELS = [
    "1s",
    "d",
    "e",
    "esx",
    "f",
    "f2",
    "g2",
    "lite",
    "m365",
    "max",
    "mi3",
    "pro",
    "pro2",
    "t15",
]
SH_NESTED = {
    "d": ["d18", "d28"],
}
REXZY_MODEL_MAP = {
    "F3-F3PRO": "f3",
    "G3": "g3",
    "GT3": "gt3",
    "ZT3": "zt3",
}
COMPONENTS = ("BLE", "BMS", "BMS2", "DRV", "MCU", "VCU", "DASH")


def archive_root() -> Path:
    return Path(os.environ.get("STOCK_ARCHIVE_DIR", Path(__file__).resolve().parent / "stock-archive"))


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fetch_bytes(url: str, timeout: int = 60) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def fetch_text(url: str, timeout: int = 45) -> str:
    return fetch_bytes(url, timeout=timeout).decode("utf-8", "replace")


def fetch_json(url: str, timeout: int = 60) -> Any:
    return json.loads(fetch_text(url, timeout=timeout))


def parse_apache_index(url: str) -> list[dict[str, Any]]:
    try:
        text = fetch_text(url)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return []
        raise
    rows: list[dict[str, Any]] = []
    for m in re.finditer(
        r'href="([^"?][^"]*)".*?</a></td><td class="indexcollastmod">\s*([^<]*?)\s*</td>'
        r'<td class="indexcolsize">\s*([^<]*?)\s*</td>',
        text,
        re.S,
    ):
        name = urllib.parse.unquote(m.group(1))
        if name in ("/", "../") or name.startswith("?") or "github" in name or "directory-listing" in name:
            continue
        rows.append(
            {
                "name": name.rstrip("/"),
                "modified": m.group(2).strip(),
                "size": m.group(3).strip(),
                "is_dir": name.endswith("/"),
            }
        )
    return rows


def version_from_filename(name: str) -> str:
    stem = Path(name).stem
    stem = re.sub(r"\s*\(Compat\)\s*", "", stem, flags=re.I)
    stem = stem.replace("%20", " ").strip()
    # DRV173 / BLE117 style → dotted
    m = re.fullmatch(r"(DRV|BLE|BMS|ESC|MCU|VCU)(\d)(\d)(\d)", stem, flags=re.I)
    if m:
        return f"{m.group(2)}.{m.group(3)}.{m.group(4)}"
    if stem.upper().startswith("FIRM_"):
        stem = stem[5:]
    return stem


def date_slug(modified: str) -> str:
    # "2025-04-06 02:35" or empty
    if modified and re.match(r"\d{4}-\d{2}-\d{2}", modified):
        return modified[:10]
    return "unknown-date"


def safe_filename(version: str, modified: str, sha12: str) -> str:
    ver = re.sub(r"[^A-Za-z0-9._+-]+", "_", version).strip("_") or "unknown"
    return f"{date_slug(modified)}_{ver}_{sha12}.bin"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_file(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_bytes() == data:
        return
    path.write_bytes(data)


def collect_sh_listings() -> list[dict[str, Any]]:
    jobs: list[dict[str, Any]] = []
    for model in SH_MODELS:
        base = f"{SH_BASE}/{model}/"
        top = parse_apache_index(base)
        if not top:
            continue
        # nested d18/d28
        nested = SH_NESTED.get(model, [])
        targets: list[tuple[str, str]] = []
        for row in top:
            if row["is_dir"] and row["name"] in COMPONENTS:
                targets.append((model, row["name"]))
            elif row["is_dir"] and row["name"] in nested:
                sub = parse_apache_index(f"{SH_BASE}/{model}/{row['name']}/")
                for s in sub:
                    if s["is_dir"] and s["name"] in COMPONENTS:
                        targets.append((f"{model}/{row['name']}", s["name"]))
        for model_path, comp in targets:
            listing = parse_apache_index(f"{SH_BASE}/{model_path}/{comp}/")
            bins = [
                r
                for r in listing
                if (not r["is_dir"])
                and r["name"].lower().endswith(".bin")
                and not r["name"].lower().endswith(".bin.enc")
            ]
            for row in bins:
                url = f"{SH_BASE}/{model_path}/{comp}/{urllib.parse.quote(row['name'])}"
                # normalize model id: d/d18 → d18
                model_id = model_path.split("/")[-1]
                jobs.append(
                    {
                        "source": "scooterhacking",
                        "model": model_id,
                        "component": comp,
                        "filename": row["name"],
                        "version": version_from_filename(row["name"]),
                        "modified": row["modified"],
                        "url": url,
                    }
                )
    return jobs


def collect_rexzy_listings() -> list[dict[str, Any]]:
    tree = fetch_json(REXZY_API)
    jobs: list[dict[str, Any]] = []
    for node in tree.get("tree", []):
        if node.get("type") != "blob":
            continue
        path = node["path"]
        if "/Stock/" not in path or not path.endswith(".bin"):
            continue
        if not Path(path).name.upper().startswith("FIRM_"):
            continue
        parts = path.split("/")
        try:
            i = parts.index("Stock")
            folder = parts[i - 1]
            comp = parts[i + 1].upper()
            if comp == "MBS":
                comp = "BMS"
        except (ValueError, IndexError):
            continue
        model = REXZY_MODEL_MAP.get(folder, folder.lower())
        fname = parts[-1]
        jobs.append(
            {
                "source": "rexzy67",
                "model": model,
                "component": comp,
                "filename": fname,
                "version": version_from_filename(fname),
                "modified": "",  # filled after download via missing; keep empty
                "url": f"{REXZY_RAW}/{urllib.parse.quote(path)}",
                "gitPath": path,
            }
        )
    return jobs


def download_jobs(jobs: list[dict[str, Any]], root: Path, limit: int | None = None) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    total = len(jobs) if limit is None else min(limit, len(jobs))
    for idx, job in enumerate(jobs[:total], start=1):
        url = job["url"]
        print(f"[{idx}/{total}] {job['model']}/{job['component']} {job['filename']}")
        try:
            data = fetch_bytes(url)
        except Exception as exc:  # noqa: BLE001
            print(f"  ERR {exc}")
            continue
        digest = sha256(data)
        out_name = safe_filename(job["version"], job.get("modified") or "", digest[:12])
        rel = Path(job["model"]) / job["component"] / out_name
        dest = root / rel
        write_file(dest, data)
        entries.append(
            {
                **job,
                "sha256": digest,
                "byteCount": len(data),
                "archivePath": str(rel).replace("\\", "/"),
                "downloadedAt": now_iso(),
            }
        )
    return entries


def build_index(entries: list[dict[str, Any]]) -> dict[str, Any]:
    # newest first: prefer modified date, then version string
    def sort_key(e: dict[str, Any]) -> tuple:
        return (e.get("modified") or "", e.get("version") or "", e.get("filename") or "")

    by_key: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for e in entries:
        by_key[f"{e['model']}/{e['component']}"].append(e)
    chronological: dict[str, list[dict[str, Any]]] = {}
    latest: dict[str, dict[str, Any]] = {}
    for key, items in sorted(by_key.items()):
        ordered = sorted(items, key=sort_key, reverse=True)
        chronological[key] = ordered
        latest[key] = ordered[0]
    return {
        "schemaVersion": 1,
        "updatedAt": now_iso(),
        "sourceNote": (
            "Chronological OEM stock archive. ScooterHacking firmware mirror + "
            "Rexzy67/X3-Firmware Stock trees. Newest first per model/component."
        ),
        "count": len(entries),
        "chronological": chronological,
        "latest": latest,
    }


def catalog_versions_from_latest(latest: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Map archive latest versions into catalogs/stock-firmware.json family keys."""
    family_map = {
        "g3": "maxG3",
        "max": "maxG30Family",
        "g2": "maxG30Family",
        "zt3": "zt3Pro",
        "f3": "ninebotF3",
        "gt3": "gt3",
        "f": "ninebotF",
        "f2": "ninebotF",
        "e": "ninebotE",
        "esx": "ninebotEsx",
        "d18": "ninebotD",
        "d28": "ninebotD",
        "t15": "airT15",
        "m365": "xiaomiClassic",
        "pro2": "xiaomiClassic",
        "pro": "xiaomiClassic",
        "1s": "xiaomiClassic",
        "lite": "xiaomiClassic",
        "mi3": "xiaomiRecent",
    }
    families: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))
    for key, e in latest.items():
        model, comp = key.split("/", 1)
        fam = family_map.get(model)
        if not fam:
            continue
        slot = {
            "DRV": "mcu",
            "MCU": "mcu",
            "VCU": "vcu",
            "BLE": "ble",
            "BMS": "bms",
            "BMS2": "bms",
            "DASH": "ble",
        }.get(comp.upper())
        if not slot:
            continue
        families[fam][slot].add(e["version"])

    out_families: dict[str, dict[str, list[str]]] = {}
    for fam, slots in families.items():
        out_families[fam] = {k: sorted(v) for k, v in slots.items()}
    return {
        "schemaVersion": 1,
        "updatedAt": now_iso()[:10],
        "sourceNote": (
            "Offline-Basis aus sync_stock_firmwares.py (ScooterHacking + Rexzy67). "
            "Chronologisches Archiv: server/firmware-analysis/stock-archive/"
        ),
        "families": out_families,
    }


def register_entries(entries: list[dict[str, Any]]) -> int:
    from stock_diff import ensure_stock_dir, register_stock_file

    ensure_stock_dir()
    n = 0
    for e in entries:
        data = (archive_root() / e["archivePath"]).read_bytes()
        register_stock_file(
            data,
            label=f"OEM {e['model'].upper()} {e['component']} {e['version']}",
            model=e["model"],
            controller_type=e["component"],
            version=e["version"],
            source="oem",
            notes=f"Synced from {e['source']} url={e['url']}",
        )
        n += 1
    return n


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latest-only", action="store_true", help="Download only newest file per model/component")
    parser.add_argument("--register", action="store_true", help="Also register into STOCK_FW_DIR")
    parser.add_argument("--limit", type=int, default=None, help="Max downloads (debug)")
    parser.add_argument("--skip-download", action="store_true", help="Rebuild index from existing archive only")
    parser.add_argument("--write-catalog", type=Path, default=None, help="Write catalogs/stock-firmware.json")
    args = parser.parse_args()

    root = archive_root()
    root.mkdir(parents=True, exist_ok=True)

    if args.skip_download:
        # rebuild from existing files + previous index if present
        index_path = root / "index.json"
        if not index_path.is_file():
            print("No index.json to rebuild", file=sys.stderr)
            return 1
        index = json.loads(index_path.read_text(encoding="utf-8"))
        entries = []
        for items in index.get("chronological", {}).values():
            entries.extend(items)
    else:
        print("Collecting ScooterHacking listings…")
        jobs = collect_sh_listings()
        print(f"  SH jobs: {len(jobs)}")
        print("Collecting Rexzy67 Stock listings…")
        try:
            rex = collect_rexzy_listings()
            print(f"  Rexzy jobs: {len(rex)}")
            jobs.extend(rex)
        except Exception as exc:  # noqa: BLE001
            print(f"  Rexzy skipped: {exc}")

        if args.latest_only:
            best: dict[str, dict[str, Any]] = {}
            for job in jobs:
                key = f"{job['model']}/{job['component']}"
                prev = best.get(key)
                if prev is None or (job.get("modified") or "", job["version"]) > (
                    prev.get("modified") or "",
                    prev["version"],
                ):
                    best[key] = job
            jobs = list(best.values())
            print(f"  latest-only → {len(jobs)} jobs")

        entries = download_jobs(jobs, root, limit=args.limit)

    index = build_index(entries)
    (root / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (root / "latest.json").write_text(
        json.dumps({"updatedAt": index["updatedAt"], "latest": index["latest"]}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Archive entries: {len(entries)} → {root}")

    catalog_path = args.write_catalog
    if catalog_path is None:
        catalog_path = Path(__file__).resolve().parents[2] / "catalogs" / "stock-firmware.json"
    catalog = catalog_versions_from_latest(index["latest"])
    # merge with existing catalog versions so we never drop known entries
    if catalog_path.is_file():
        try:
            old = json.loads(catalog_path.read_text(encoding="utf-8"))
            for fam, slots in (old.get("families") or {}).items():
                catalog["families"].setdefault(fam, {})
                for slot, vers in slots.items():
                    merged = set(catalog["families"][fam].get(slot, [])) | set(vers)
                    catalog["families"][fam][slot] = sorted(merged)
        except json.JSONDecodeError:
            pass
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote catalog {catalog_path}")

    if args.register:
        n = register_entries(entries)
        print(f"Registered {n} OEM refs into STOCK_FW_DIR")

    # summary of newest per model
    print("\n=== NEWEST OEM FIRMWARES ===")
    for key, e in sorted(index["latest"].items()):
        print(f"{key:18} {e['version']:16} {e.get('modified') or '-':16} {e['source']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
