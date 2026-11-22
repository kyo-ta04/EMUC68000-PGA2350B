#!/usr/bin/env python3
"""M2 verification for the MS-BASIC 68K port.

Assembles msbasic68k.asm with asm68k-py and runs it in the Musashi
sim (emu) with a CR-terminated input script that exercises program
storage, LIST detokenization, RUN, line replace/delete, direct
PRINT, and NEW:

  20 PRINT "WORLD"      (entered out of order)
  10 PRINT "HELLO"
  30 END
  LIST                  -> 10 HELLO / 20 WORLD / 30 END, in order
  RUN                   -> HELLO, WORLD, READY.
  20 PRINT "EARTH"      (replace)
  LIST                  -> 20 now says EARTH
  20                    (delete by bare line number)
  LIST                  -> only 10 and 30 remain
  PRINT "DIRECT"        -> DIRECT
  NEW
  LIST                  -> nothing, straight to READY.
  PRINT "ZZEND"         (unique end marker for --until)

Checks are ordered substring searches over the transcript, so each
stage must appear after the previous one.  Exit status 0 = all PASS.
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
SCRIPT = HERE / "m2.script"
OUT = HERE / "m2.out"

LINES = [
    '20 PRINT "WORLD"',
    '10 PRINT "HELLO"',
    '30 END',
    'LIST',
    'RUN',
    '20 PRINT "EARTH"',
    'LIST',
    '20',
    'LIST',
    'PRINT "DIRECT"',
    'NEW',
    'LIST',
    'PRINT "ZZEND"',
]


def main() -> int:
    r = subprocess.run(
        [sys.executable, str(ASM68K), str(SRC), "--bin", str(BIN),
         "-o", str(HERE / "msbasic68k.c")],
        capture_output=True, text=True)
    print("asm68k:", (r.stdout + r.stderr).strip())
    if r.returncode != 0:
        print("FAIL: assembly error")
        return 1

    SCRIPT.write_bytes("".join(l + "\r" for l in LINES).encode("ascii"))
    cmd = [EMU, "--image", str(BIN),
           "--masters", str(SIM / "masters"),
           "--script", str(SCRIPT), "--out", str(OUT),
           "--until", "ZZEND",
           "--maxcycles", "100000000"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    print("emu:", r.stdout.strip(), f"(rc={r.returncode})")
    tx = OUT.read_bytes().decode("latin-1")

    checks = []

    def check(name, ok):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name)

    def find_from(name, needle, start):
        i = tx.find(needle, start)
        check(name, i >= start)
        return i + len(needle) if i >= 0 else start

    check("banner appears", tx.find("### COMMODORE BASIC ###") >= 0)

    pos = 0
    pos = find_from("LIST #1: lines stored and sorted",
                    '10 PRINT "HELLO"\r\n20 PRINT "WORLD"\r\n30 END', pos)
    pos = find_from("RUN: HELLO then WORLD then READY.",
                    "HELLO\r\nWORLD\r\n\r\nREADY.", pos)
    pos = find_from("LIST #2: line 20 replaced by EARTH version",
                    '10 PRINT "HELLO"\r\n20 PRINT "EARTH"\r\n30 END', pos)

    # After deletion: the third LIST must show 10 and 30 only.
    i_list3 = tx.find("LIST\r\n", pos)
    check("LIST #3 echo found", i_list3 >= pos)
    seg_start = i_list3 if i_list3 >= 0 else pos
    i_direct = tx.find('PRINT "DIRECT"', seg_start)
    seg = tx[seg_start:i_direct] if i_direct >= 0 else tx[seg_start:]
    check("LIST #3: 10 and 30 remain, adjacent",
          '10 PRINT "HELLO"\r\n30 END' in seg)
    check("LIST #3: EARTH line gone", "EARTH" not in seg)
    check("LIST #3: no line 20 left", "20 PRINT" not in seg)
    pos = i_direct if i_direct >= 0 else pos

    pos = find_from("direct PRINT \"DIRECT\" prints DIRECT",
                    'PRINT "DIRECT"\r\nDIRECT\r\n', pos)
    i_new = tx.find("NEW\r\n", pos)
    check("NEW echo found", i_new >= pos)
    pos = find_from("LIST after NEW is empty (straight to READY.)",
                    "LIST\r\n\r\nREADY.", i_new if i_new >= 0 else pos)
    pos = find_from("final marker ZZEND printed, then READY.",
                    "ZZEND\r\n\r\nREADY.", pos)
    check("emu exit code 0 (until-string seen)", r.returncode == 0)

    ok = all(v for _, v in checks)
    print("M2:", "PASS" if ok else "FAIL")
    print("--- transcript (escaped) ---")
    print(tx.replace("\r", "\\r").replace("\n", "\\n\n"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
