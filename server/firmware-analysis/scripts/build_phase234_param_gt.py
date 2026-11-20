#!/usr/bin/env python3
"""Build Phase 2.3.4 controlled Thumb parameter-GT firmware (clang/LLVM)."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "testdata" / "phase234" / "param_gt" / "src" / "param_gt.c"
OUT_DIR = ROOT / "testdata" / "phase234" / "param_gt" / "bin"
BASE = 0x08000000


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    clang = shutil.which("clang")
    objcopy = shutil.which("llvm-objcopy") or shutil.which("objcopy")
    if not clang:
        print("clang not found", file=sys.stderr)
        return 2
    elf = OUT_DIR / "param_gt.elf"
    bin_path = OUT_DIR / "param_gt.bin"
    cmd = [
        clang,
        "-target",
        "thumbv7m-none-eabi",
        "-mthumb",
        "-nostdlib",
        "-ffreestanding",
        "-fno-builtin",
        "-Os",
        "-Wl,--section-start=.text=0x08000000",
        "-o",
        str(elf),
        str(SRC),
    ]
    print("+", " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        # Fallback without section start (still useful for Ghidra with -loader)
        cmd2 = [
            clang,
            "-target",
            "thumbv7m-none-eabi",
            "-mthumb",
            "-nostdlib",
            "-ffreestanding",
            "-fno-builtin",
            "-c",
            "-o",
            str(OUT_DIR / "param_gt.o"),
            str(SRC),
        ]
        print("+", " ".join(cmd2))
        r2 = subprocess.run(cmd2, capture_output=True, text=True)
        if r2.returncode != 0:
            print(r.stderr or r.stdout)
            print(r2.stderr or r2.stdout)
            return r2.returncode
        print("object-only build (param_gt.o); ELF link failed:")
        print(r.stderr or r.stdout)
        return 0
    if objcopy:
        r = subprocess.run([objcopy, "-O", "binary", str(elf), str(bin_path)], capture_output=True, text=True)
        if r.returncode == 0:
            print("wrote", bin_path, "size", bin_path.stat().st_size)
        else:
            print("objcopy skipped (host tool may lack ARM):", (r.stderr or "").strip()[:200])
            print("ELF available:", elf, "size", elf.stat().st_size)
    else:
        print("objcopy missing; ELF only:", elf)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
