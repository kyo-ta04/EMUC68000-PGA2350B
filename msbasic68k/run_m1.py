#!/usr/bin/env python3
"""M1 verification for the MS-BASIC 68K port.

Assembles msbasic68k.asm with asm68k-py, runs it in the Musashi sim
(emu) with the input script:  <empty line> -> NEW -> FOO, all lines
terminated by CR (the sim's line discipline is CR, not LF).

Exit conditions checked on the transcript:
  1. banner "### COMMODORE BASIC ###" appears
  2. "61440 BYTES FREE" appears (MEMSIZ $02F000 - TXTTAB $020000)
  3. "READY." appears at least 3 times (initial, after NEW,
     after the error).  M8: an empty line no longer reprints
     READY. -- it is typed only at the READY entry, as in the
     original (through M7 a blank line reprinted it).
  4. input echo: "NEW" and "FOO" come back followed by CRLF
  5. NEW is followed by a fresh "READY."
  6. FOO produces "?SN ERROR" and then "READY." again
  7. emu exits 0 (the --until string was seen)
Prints PASS/FAIL per check and overall; exit status 0 = all PASS.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SIM = Path.home() / "workspace/mc68000-selfhost/sim"
EMU = os.environ.get("MSB_EMU", str(SIM / "emu"))
ASM68K = Path.home() / "workspace/mc68000-selfhost/asm68k-py/asm68k.py"

SRC = HERE / "msbasic68k.asm"
BIN = HERE / "msbasic68k.bin"
SCRIPT = HERE / "m1.script"
OUT = HERE / "m1.out"


def main() -> int:
    r = subprocess.run(
        [sys.executable, str(ASM68K), str(SRC), "--bin", str(BIN),
         "-o", str(HERE / "msbasic68k.c")],
        capture_output=True, text=True)
    print("asm68k:", (r.stdout + r.stderr).strip())
    if r.returncode != 0:
        print("FAIL: assembly error")
        return 1

    SCRIPT.write_bytes(b"\rNEW\rFOO\r")
    cmd = [EMU, "--image", str(BIN),
           "--masters", str(SIM / "masters"),
           "--script", str(SCRIPT), "--out", str(OUT),
           "--until", "?SN ERROR",
           "--maxcycles", "50000000"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    print("emu:", r.stdout.strip(), f"(rc={r.returncode})")
    tx = OUT.read_bytes().decode("latin-1")

    checks = []

    def check(name, ok):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name)

    i_banner = tx.find("### COMMODORE BASIC ###")
    check("banner appears", i_banner >= 0)
    i_free = tx.find("61440 BYTES FREE")
    check("BYTES FREE (61440, computed MEMSIZ-TXTTAB) appears",
          i_free > i_banner >= 0)
    n_ready = tx.count("READY.")
    check(f"READY. appears >= 3 times (got {n_ready})", n_ready >= 3)
    i_new = tx.find("NEW\r\n")
    check("echo of NEW line", i_new > i_free)
    check("READY. again after NEW",
          i_new >= 0 and tx.find("READY.", i_new) > i_new)
    i_foo = tx.find("FOO\r\n")
    check("echo of FOO line", i_foo > i_new)
    i_err = tx.find("?SN ERROR")
    check("?SN ERROR after FOO", i_err > i_foo >= 0)
    check("READY. again after ?SN ERROR",
          i_err >= 0 and tx.find("READY.", i_err) > i_err)
    check("emu exit code 0 (until-string seen)", r.returncode == 0)

    ok = all(v for _, v in checks)
    print("M1:", "PASS" if ok else "FAIL")
    print("--- transcript (escaped) ---")
    print(tx.replace("\r", "\\r").replace("\n", "\\n\n"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
