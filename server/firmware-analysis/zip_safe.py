"""Safe ZIP inspection/extraction helpers for firmware uploads.

Guards against zip bombs, path traversal, and symlink members while still
allowing ordinary Ninebot/Segway firmware packages.
"""
from __future__ import annotations

import io
import os
import zipfile
from pathlib import Path
from typing import Any

# Defaults can be overridden via env (deployment).
MAX_UPLOAD_BYTES = int(os.environ.get("FW_MAX_UPLOAD_BYTES", str(80 * 1024 * 1024)) or str(80 * 1024 * 1024))
MAX_UNCOMPRESSED_BYTES = int(
    os.environ.get("FW_MAX_UNCOMPRESSED_BYTES", str(256 * 1024 * 1024)) or str(256 * 1024 * 1024)
)
MAX_ZIP_ENTRIES = int(os.environ.get("FW_MAX_ZIP_ENTRIES", "256") or "256")
MAX_COMPRESSION_RATIO = float(os.environ.get("FW_MAX_COMPRESSION_RATIO", "80") or "80")
MAX_SINGLE_MEMBER_BYTES = int(
    os.environ.get("FW_MAX_SINGLE_MEMBER_BYTES", str(64 * 1024 * 1024)) or str(64 * 1024 * 1024)
)
# Soft memory budget for in-memory extract of selected members (not full archive).
MAX_EXTRACT_MEMORY_BYTES = int(
    os.environ.get("FW_MAX_EXTRACT_MEMORY_BYTES", str(96 * 1024 * 1024)) or str(96 * 1024 * 1024)
)


class ZipSafetyError(ValueError):
    """User-facing ZIP validation failure."""


def validate_upload_size(raw: bytes, *, max_bytes: int | None = None) -> None:
    limit = max_bytes if max_bytes is not None else MAX_UPLOAD_BYTES
    if not raw:
        raise ZipSafetyError("Leerer Upload.")
    if len(raw) > limit:
        raise ZipSafetyError(
            f"Upload zu groß ({len(raw)} Byte). Maximum: {limit} Byte."
        )


def inspect_zip(raw: bytes | Path, *, dest_hint: str | None = None) -> dict[str, Any]:
    """Validate ZIP structure without extracting. Returns summary dict."""
    data: bytes
    if isinstance(raw, Path):
        data = raw.read_bytes()
    else:
        data = raw
    validate_upload_size(data)

    try:
        zf = zipfile.ZipFile(io.BytesIO(data), "r")
    except zipfile.BadZipFile as e:
        raise ZipSafetyError(f"Keine gültige ZIP-Datei: {e}") from e

    with zf:
        names = zf.namelist()
        if len(names) > MAX_ZIP_ENTRIES:
            raise ZipSafetyError(
                f"Zu viele ZIP-Einträge ({len(names)}). Maximum: {MAX_ZIP_ENTRIES}."
            )

        total_uncomp = 0
        members: list[dict[str, Any]] = []
        for info in zf.infolist():
            name = info.filename or ""
            _check_member_path(name)
            if _is_symlink(info):
                raise ZipSafetyError(
                    f"Symbolische Links sind beim Entpacken verboten: {name!r}."
                )
            # Skip pure directory entries for size accounting.
            if name.endswith("/"):
                continue
            uncomp = int(info.file_size or 0)
            comp = int(info.compress_size or 0)
            if uncomp < 0 or comp < 0:
                raise ZipSafetyError(f"Ungültige Größenangabe in ZIP-Eintrag {name!r}.")
            if uncomp > MAX_SINGLE_MEMBER_BYTES:
                raise ZipSafetyError(
                    f"ZIP-Eintrag {name!r} zu groß ({uncomp} Byte). "
                    f"Maximum pro Datei: {MAX_SINGLE_MEMBER_BYTES} Byte."
                )
            total_uncomp += uncomp
            if total_uncomp > MAX_UNCOMPRESSED_BYTES:
                raise ZipSafetyError(
                    f"Entpackte Gesamtgröße überschreitet Limit "
                    f"({total_uncomp} > {MAX_UNCOMPRESSED_BYTES} Byte)."
                )
            if comp > 0 and uncomp / max(comp, 1) > MAX_COMPRESSION_RATIO:
                raise ZipSafetyError(
                    f"Auffälliges Kompressionsverhältnis bei {name!r} "
                    f"({uncomp}/{comp}). Mögliches Zip-Bomb."
                )
            members.append(
                {
                    "name": name,
                    "fileSize": uncomp,
                    "compressSize": comp,
                }
            )

        return {
            "entryCount": len(names),
            "fileCount": len(members),
            "uncompressedBytes": total_uncomp,
            "compressedBytes": len(data),
            "members": members,
            "destHint": dest_hint,
        }


def safe_extract_member(
    zf: zipfile.ZipFile,
    member_name: str,
    dest_path: Path,
    *,
    max_bytes: int | None = None,
) -> int:
    """Extract one member to dest_path with path + size guards. Returns bytes written."""
    _check_member_path(member_name)
    try:
        info = zf.getinfo(member_name)
    except KeyError as e:
        raise ZipSafetyError(f"ZIP-Eintrag nicht gefunden: {member_name!r}") from e
    if _is_symlink(info):
        raise ZipSafetyError(f"Symbolische Links sind verboten: {member_name!r}.")

    limit = max_bytes if max_bytes is not None else MAX_SINGLE_MEMBER_BYTES
    written = 0
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    with zf.open(info, "r") as src, dest_path.open("wb") as dst:
        while True:
            chunk = src.read(1 << 20)
            if not chunk:
                break
            written += len(chunk)
            if written > limit:
                dest_path.unlink(missing_ok=True)
                raise ZipSafetyError(
                    f"Entpackte Datei überschreitet Limit ({limit} Byte): {member_name!r}."
                )
            if written > MAX_EXTRACT_MEMORY_BYTES:
                dest_path.unlink(missing_ok=True)
                raise ZipSafetyError(
                    f"Arbeitsspeicher-Budget für Extraktion überschritten ({MAX_EXTRACT_MEMORY_BYTES} Byte)."
                )
            dst.write(chunk)
    return written


def _check_member_path(name: str) -> None:
    if not name or name.strip() != name:
        # Allow normal paths; reject empty / whitespace-only
        if not name:
            raise ZipSafetyError("Leerer ZIP-Eintragsname.")
    # Null bytes
    if "\x00" in name:
        raise ZipSafetyError(f"Ungültiger ZIP-Pfad (Nullbyte): {name!r}")
    # Absolute / drive paths
    if name.startswith("/") or name.startswith("\\") or (len(name) >= 2 and name[1] == ":"):
        raise ZipSafetyError(f"Absoluter ZIP-Pfad verboten: {name!r}")
    # Backslash separators are never needed for firmware packs; reject so
    # Windows-style "..\\.." names cannot bypass Path.parts on POSIX.
    if "\\" in name:
        raise ZipSafetyError(f"Backslash in ZIP-Pfad verboten: {name!r}")
    parts = Path(name).parts
    if any(p == ".." for p in parts):
        raise ZipSafetyError(f"Path-Traversal in ZIP-Pfad verboten: {name!r}")


def _is_symlink(info: zipfile.ZipInfo) -> bool:
    # Unix symlink: external_attr high bytes contain mode; S_IFLNK = 0o120000
    mode = (info.external_attr >> 16) & 0o170000
    if mode == 0o120000:
        return True
    # Some archives mark create_system=3 (Unix) with symlink flag in header
    if getattr(info, "create_system", None) == 3 and mode == 0o120000:
        return True
    return False
