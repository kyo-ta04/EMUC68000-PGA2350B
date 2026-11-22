#!/usr/bin/env python3
"""M7 verification: EXT1 (extension phase, batch 1) for the
MS-BASIC 68K port -- &H literals, a live USR, DEEK/DOKE/
LEEK/LOKE, INSTR and ELSE, in MS Extended BASIC form.

Gates, in order:
  1. build.py builds all four flavours; the FAITHFUL flavours
     keep their byte-identity gate inside build.py (sim 15496
     bytes / BSD sum 23356, hw 15504 / 58202 -- the reference
     values after the 2026-11-22 FCOMP/PERFORM2 fidelity
     fixes; the post-M8 pin was 15492/32410 and 15500/17566).
     The EXT sizes and sums are recorded and printed.
  2. Branch checkers on both EXT listings ("0 bad").
  3. EXT-SIM spec session (this file's SESSION): byte-exact
     response regions, 68K-only like run_break.py -- the new
     features have no CBM golden.  Includes the CTRL-C break
     session (the EXT FETCH/IF parts must not break BRKCHK).
  4. EXT-SIM ASCIIART: the picture must equal the CBM golden
     byte for byte (the extension must not perturb the core).
  5. EXT-HW: composite boot (vector stub + image at $30000,
     run_hw.py style) under BOTH emu and emu_strict: banner,
     40960 BYTES FREE, an EXT smoke set, ASCIIART == golden.
  6. Faithful regression: run_break.py as a subprocess (it
     cascades run_m5d.py's 116/118-with-2-known-ulp gate and
     run_hw.py).
  7. EXT-flavour regression: the existing suite must pass
     against the EXT source too.  run_m5d.py (which cascades
     run_m1.py..run_m5c.py) assembles msbasic68k.asm by name,
     so the EXT combined source is swapped in under that name
     for the run and the faithful build is restored after.

This script honours MSB_EMU for its own sim sessions.
Exit status 0 = PASS.
"""
import os
import struct
import subprocess
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SIM = Path.home() / "workspace/mc68000-selfhost/sim"
EMU = os.environ.get("MSB_EMU", str(SIM / "emu"))
EMU_STRICT = str(SIM / "emu_strict")

EXT_BIN = HERE / "msbasic68k-ext.bin"
EXT_LST = HERE / "msbasic68k-ext.lst"
HWEXT_BIN = HERE / "msbasic68k-hw-ext.bin"
HWEXT_LST = HERE / "msbasic68k-hw-ext.lst"
COMPOSITE = HERE / "msbasic68k-hw-ext-composite.bin"

BAS = ROOT / "research" / "mez6502" / "ASCIIART.BAS"
GOLDEN_PATH = ROOT / "golden" / "asciiart-output.txt"
GOLDEN_LEN = 2025
GOLDEN_SUM16 = 25584
GOLDEN_CRC32 = 0x0D6D8795

ENDMARK = 'PRINT "ZZX1";"END"'  # split so the echo alone
                                # cannot trip the emu's --until

FC_R = "?FC ERROR\r\n\r\nREADY.\r\n"
SN_R = "?SN ERROR\r\n\r\nREADY.\r\n"
IQ_R = "?IQ ERROR\r\n\r\nREADY.\r\n"
TM_R = "?TM ERROR\r\n\r\nREADY.\r\n"


def num(v):
    """The region for a direct PRINT of one number."""
    return f" {v} \r\n\r\nREADY.\r\n"


# Entries: ("L", text, "", None)                 stored line
#          ("C", text, data, expected-or-None)   direct line;
#          data = extra bytes fed right after text+"\r"
SESSION = [
    # ---- USR: unset vector -> ?FC (must precede any setup) ----
    ("C", "PRINT USR(0)", "", FC_R),
    ("C", "PRINT USR(1+2)", "", FC_R),
    # ---- &H literals ----
    ("C", "PRINT &H0", "", num(0)),
    ("C", "PRINT &HFF", "", num(255)),
    ("C", "PRINT &H1234", "", num(4660)),
    ("C", "PRINT &H7FFF", "", num(32767)),
    ("C", "PRINT &H8000", "", num(32768)),      # unsigned, not -32768
    ("C", "PRINT &HFFFF", "", num(65535)),
    ("C", "PRINT &H10000", "", num(65536)),
    ("C", "PRINT &H30000", "", num(196608)),
    ("C", "PRINT &HFFFFFFFF-4294967295", "", num(0)),
    ("C", "PRINT &H80000000/2147483648", "", num(1)),
    ("C", "PRINT &HDEF", "", num(3567)),        # CRUNCH trap: DEF
    ("C", "PRINT &HDEAD", "", num(57005)),
    ("C", "PRINT &H10+&H20", "", num(48)),
    ("C", "PRINT &HA-10", "", num(0)),
    ("C", "PRINT &H", "", SN_R),                # no digits
    ("C", "PRINT &H123456789", "", SN_R),       # 9 digits
    # ---- DEEK/DOKE/LEEK/LOKE (logical page, $9000 = 36864) ----
    ("C", "DOKE 36864,4660: PRINT DEEK(36864)", "", num(4660)),
    ("C", "PRINT PEEK(36864); PEEK(36865)", "",
     " 18  52 \r\n\r\nREADY.\r\n"),              # big-endian $12,$34
    ("C", "DOKE 36865,43981: PRINT DEEK(36865)", "", num(43981)),
    ("C", "PRINT PEEK(36865); PEEK(36866)", "",
     " 171  205 \r\n\r\nREADY.\r\n"),           # odd addr, $AB,$CD
    ("C", "DOKE 36864,65535: PRINT DEEK(36864)", "", num(65535)),
    ("C", "LOKE 36864,305419896: PRINT LEEK(36864)", "",
     num(305419896)),                           # $12345678
    ("C", "PRINT PEEK(36866); PEEK(36867)", "",
     " 86  120 \r\n\r\nREADY.\r\n"),            # $56,$78
    ("C", "LOKE 36865,4294967295: PRINT LEEK(36865)-4294967295",
     "", num(0)),                               # odd addr, $FFFFFFFF
    ("C", "PRINT DEEK(36865); DEEK(36867)", "",
     " 65535  65535 \r\n\r\nREADY.\r\n"),
    ("C", "LOKE 36864,0: PRINT LEEK(36864)", "", num(0)),
    ("C", "DOKE 36864,65536", "", IQ_R),
    ("C", "DOKE 36864,-1", "", IQ_R),
    ("C", "LOKE 36864,-1", "", IQ_R),
    ("C", "PRINT DEEK(65536)", "", IQ_R),       # GETADR range (PEEK's)
    ("C", "PRINT DEEK(-1)", "", IQ_R),
    ("C", "PRINT LEEK(36864)", "", num(0)),     # still 0 after errors
    # ---- INSTR ----
    ("C", 'PRINT INSTR("HELLO","LL")', "", num(3)),
    ("C", 'PRINT INSTR("HELLO","X")', "", num(0)),
    ("C", 'PRINT INSTR(2,"HELLO","L")', "", num(3)),
    ("C", 'PRINT INSTR(4,"HELLO","L")', "", num(4)),
    ("C", 'PRINT INSTR(5,"HELLO","L")', "", num(0)),
    ("C", 'PRINT INSTR(6,"HELLO","L")', "", num(0)),
    ("C", 'PRINT INSTR("HELLO","")', "", num(1)),
    ("C", 'PRINT INSTR(3,"HELLO","")', "", num(3)),
    ("C", 'PRINT INSTR("","X")', "", num(0)),
    ("C", 'PRINT INSTR("","")', "", num(0)),
    ("C", 'PRINT INSTR("AAAA","AA")', "", num(1)),
    ("C", 'PRINT INSTR(2,"AAAA","AA")', "", num(2)),
    ("C", 'PRINT INSTR(3,"AAAA","AA")', "", num(3)),
    ("C", 'PRINT INSTR(4,"AAAA","AA")', "", num(0)),
    ("C", 'PRINT INSTR(0,"A","A")', "", FC_R),
    ("C", 'PRINT INSTR(-1,"A","A")', "", FC_R),
    ("C", 'PRINT INSTR("HELLO",5)', "", TM_R),
    ("C", 'PRINT INSTR(5,"HELLO")', "", SN_R),  # missing 3rd argument
    ("C", 'A$="COMPUTER": PRINT INSTR(A$,"PUT")', "", num(4)),
    ("C", 'PRINT INSTR("X"+"HELLO","LL")', "", num(4)),
    ("C", 'PRINT INSTR(LEFT$("HELLO",4),"LL")', "", num(3)),
    ("C", 'B$="LL": PRINT INSTR("HELLO",B$)', "", num(3)),
    ("C", 'PRINT INSTR("HELLO","LL")*10', "", num(30)),
    # ---- USR: identity routine at logical $6000, vector $334 ----
    ("C", "POKE 24576,78: POKE 24577,117", "", "\r\nREADY.\r\n"),
    ("C", "POKE 820,96: POKE 821,0", "", "\r\nREADY.\r\n"),
    ("C", "PRINT USR(5)", "", num(5)),
    ("C", "PRINT USR(-3)", "", "-3 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT USR(1.5)", "", " 1.5 \r\n\r\nREADY.\r\n"),
    ("L", "10 PRINT USR(7)", "", None),
    ("C", "RUN", "", num(7)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- USR: constant-2.0 routine (overwrites $6000) ----
    ("L", "10 FOR I=0 TO 31: READ B: POKE 24576+I,B: NEXT I",
     "", None),
    ("L", "20 DATA 16,188,0,130,17,124,0,128,0,1,66,40,0,2,"
          "66,40,0,3,66,40,0,4,66,40,0,5,66,40,0,6,78,117",
     "", None),
    ("C", "RUN", "", "\r\nREADY.\r\n"),
    ("C", "PRINT USR(0)", "", num(2)),
    ("C", "PRINT USR(99)", "", num(2)),
    ("C", 'PRINT USR("A")', "", TM_R),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: basic true/false with ':' sequences ----
    ("L", "10 A=5", "", None),
    ("L", '20 IF A=5 THEN PRINT "T1" ELSE PRINT "F1"', "", None),
    ("L", '30 IF A=6 THEN PRINT "T2" ELSE PRINT "F2"', "", None),
    ("L", '40 PRINT "DONE"', "", None),
    ("C", "RUN", "", "T1\r\nF2\r\nDONE\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: line-number forms, both directions ----
    ("L", "10 A=0", "", None),
    ("L", "20 IF A THEN 100 ELSE 200", "", None),
    ("L", '30 PRINT "BAD"', "", None),
    ("L", "40 END", "", None),
    ("L", '100 PRINT "TRUE-LINE"', "", None),
    ("L", "110 END", "", None),
    ("L", '200 PRINT "FALSE-LINE"', "", None),
    ("C", "RUN", "", "FALSE-LINE\r\n\r\nREADY.\r\n"),
    ("L", "10 A=1", "", None),   # M8: stored line, no READY.
    ("C", "RUN", "", "TRUE-LINE\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: THEN line number + ELSE statement ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN 100 ELSE PRINT "E"', "", None),
    ("L", "30 END", "", None),
    ("L", '100 PRINT "G100"', "", None),
    ("C", "RUN", "", "G100\r\n\r\nREADY.\r\n"),
    ("L", "10 A=0", "", None),   # M8: stored line, no READY.
    ("C", "RUN", "", "E\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: nesting, inner (true outer, false inner) ----
    ("L", "10 A=1: B=0", "", None),
    ("L", '20 IF A THEN IF B THEN PRINT "X" ELSE PRINT "INNER"',
     "", None),
    ("L", '30 PRINT "AFTER"', "", None),
    ("C", "RUN", "", "INNER\r\nAFTER\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: nesting, outer false (depth counting) ----
    ("L", "10 A=0: B=1", "", None),
    ("L", '20 IF A THEN IF B THEN PRINT "X" ELSE PRINT "INNER"'
          ' ELSE PRINT "OUTER"', "", None),
    ("L", '30 PRINT "AFTER"', "", None),
    ("C", "RUN", "", "OUTER\r\nAFTER\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: true path runs ':' sequence, ELSE skipped ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN PRINT "T": PRINT "T2" ELSE PRINT "F"',
     "", None),
    ("L", '30 PRINT "NEXT"', "", None),
    ("C", "RUN", "", "T\r\nT2\r\nNEXT\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: PRINT ';' directly before ELSE (quiet end) ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN PRINT "S"; ELSE PRINT "F"', "", None),
    ("L", '30 PRINT "NEXT"', "", None),
    ("C", "RUN", "", "SNEXT\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: PRINT ',' (zone) directly before ELSE ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN PRINT "Z", ELSE PRINT "F"', "", None),
    ("L", '30 PRINT "N"', "", None),
    ("C", "RUN", "", "Z         N\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: DATA payload must not be misread as ELSE ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN DATA ELSE: PRINT "REAL" ELSE PRINT "FAKE"',
     "", None),
    ("C", "RUN", "", "FAKE\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: string payload must not be misread ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN PRINT "ELSE" ELSE PRINT "REAL2"', "", None),
    ("C", "RUN", "", "REAL2\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: REM swallows the rest (no ELSE found) ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN REM ELSE PRINT "X"', "", None),
    ("L", '30 PRINT "Y"', "", None),
    ("C", "RUN", "", "Y\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: no ELSE present -- faithful false path ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN PRINT "NO"', "", None),
    ("L", '30 PRINT "YES"', "", None),
    ("C", "RUN", "", "YES\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: THEN omitted (IF c GOTO n ELSE ...) ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A GOTO 100 ELSE PRINT "E2"', "", None),
    ("L", "30 END", "", None),
    ("L", '100 PRINT "G"', "", None),
    ("C", "RUN", "", "E2\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: direct mode ----
    ("C", 'IF 0 THEN PRINT 1 ELSE PRINT 2', "", num(2)),
    ("C", 'IF 1 THEN PRINT 1 ELSE PRINT 2', "", num(1)),
    # ---- CTRL-C break still works (run_break session A) ----
    ("C", "NEW", "", None),
    ("L", "10 GET A$", "", None),
    ("L", "20 GOTO 10", "", None),
    ("C", "RUN", "Z\x03", "\r\nBREAK IN  10\r\nREADY.\r\n"),
]


def fed_bytes(entry):
    if entry[0] == "L":
        return entry[1] + "\r"
    return entry[1] + "\r" + entry[2]


def regions68(tx: str, entries):
    """Per-entry response regions, run_break.py's convention."""
    res = []
    pos = 0
    for e in entries:
        echo = e[1] + "\r\n"
        i = tx.find(echo, pos)
        if i < 0:
            res.append(None)
            continue
        start = i + len(echo)
        if e[0] == "L":
            res.append("")
            pos = start
            continue
        j = tx.find("READY.\r\n", start)
        if j < 0:
            res.append(None)
            pos = start
            continue
        res.append(tx[start:j + len("READY.\r\n")])
        pos = j + len("READY.\r\n")
    return res


def bsd_sum(data: bytes) -> int:
    s = 0
    for b in data:
        s = ((s >> 1) | ((s & 1) << 15)) & 0xFFFF
        s = (s + b) & 0xFFFF
    return s


def sum16(data: bytes) -> int:
    s = 0
    for b in data:
        s = (s + b) & 0xFFFF
    return s


def run_session(emu, image, entries, script, out, tag, check,
                until="ZZX1END", maxcycles=1_000_000_000):
    script.write_bytes(
        "".join(fed_bytes(e) for e in entries).encode("latin-1"))
    cmd = [emu, "--image", str(image),
           "--masters", str(SIM / "masters"),
           "--script", str(script), "--out", str(out),
           "--until", until, "--settle", "2000000",
           "--maxcycles", str(maxcycles)]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=1800)
    print(f"emu[{tag}]:", r.stdout.strip(), f"(rc={r.returncode})")
    check(f"{tag}: emu exit code 0 (until-string seen)",
          r.returncode == 0)
    return out.read_bytes().decode("latin-1")


def asciiart_check(emu, image, tag, check):
    prog = [ln for ln in BAS.read_text().splitlines() if ln.strip()]
    lines = prog + ["RUN", 'PRINT "ZZX1";"END"']
    script = HERE / f"ext1-{tag}-art.script"
    out = HERE / f"ext1-{tag}-art.out"
    txb = run_session(emu, image,
                      [("L", ln, "", None) for ln in lines],
                      script, out, f"{tag} ASCIIART", check,
                      maxcycles=5_000_000_000)
    txb = txb.encode("latin-1")
    golden = GOLDEN_PATH.read_bytes()
    pic = None
    i = txb.find(b"RUN\r\n")
    if i >= 0:
        pic = txb[i + 5: i + 5 + GOLDEN_LEN]
    ok = pic is not None and len(pic) == GOLDEN_LEN and pic == golden
    detail = ""
    if ok:
        detail = (f"sum16={sum16(pic)} crc32="
                  f"{zlib.crc32(pic) & 0xFFFFFFFF:08X}")
    elif pic is not None and len(pic) == GOLDEN_LEN:
        k = next(n for n in range(GOLDEN_LEN) if pic[n] != golden[n])
        detail = (f"first mismatch at byte {k}: "
                  f"got {pic[k]:02X}, want {golden[k]:02X}")
    else:
        detail = "picture not extracted"
    check(f"{tag}: ASCIIART picture == golden (byte exact)", ok,
          detail)


def main() -> int:
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name, detail)

    # ---- 1. builds (faithful byte-identity is build.py's gate) ----
    r = subprocess.run([sys.executable, str(HERE / "build.py")],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    check("build.py (all four flavours) exit 0", r.returncode == 0)
    for name, want in (("msbasic68k.bin", (15496, 23356)),
                       ("msbasic68k-hw.bin", (15504, 58202))):
        data = (HERE / name).read_bytes()
        check(f"faithful {name} size/BSD sum",
              (len(data), bsd_sum(data)) == want,
              f"{len(data)} bytes, sum {bsd_sum(data)}")
    for name in ("msbasic68k-ext.bin", "msbasic68k-hw-ext.bin"):
        data = (HERE / name).read_bytes()
        print(f"INFO - EXT {name}: {len(data)} bytes, "
              f"BSD sum {bsd_sum(data)}")

    # ---- 2. branch checkers on the EXT listings ----
    for lst, binf in ((EXT_LST, EXT_BIN), (HWEXT_LST, None)):
        for chk in ("check_branches.py", "check_short_branches.py"):
            target = binf
            if target is None:
                hw = HWEXT_BIN.read_bytes()
                comp = bytearray(0x30000 + len(hw))
                struct.pack_into(">I", comp, 0, 0x40000)
                struct.pack_into(">I", comp, 4, 0x30000)
                comp[0x30000:] = hw
                COMPOSITE.write_bytes(comp)
                target = COMPOSITE
            r = subprocess.run([sys.executable, str(HERE / chk),
                                str(lst), str(target)],
                               capture_output=True, text=True)
            tail = (r.stdout + r.stderr).strip().splitlines()
            check(f"branch checker {chk} on {lst.name}",
                  bool(tail) and tail[-1].startswith("0 bad"),
                  tail[-1] if tail else "(no output)")

    # ---- 3. EXT-SIM spec session ----
    entries = SESSION + [("C", ENDMARK, "", None)]
    tx = run_session(EMU, EXT_BIN, entries,
                     HERE / "ext1.script", HERE / "ext1.out",
                     "ext-sim spec", check)
    got = regions68(tx, entries)
    check("ext-sim: endmark region",
          got[-1] == "ZZX1END\r\n\r\nREADY.\r\n", f"got {got[-1]!r}")
    for idx, e in enumerate(entries):
        if e[0] == "L" or e[3] is None:
            continue
        check(f"ext-sim: [{e[1]}]", got[idx] == e[3],
              f"got {got[idx]!r} want {e[3]!r}"
              if got[idx] != e[3] else "")

    # ---- 4. EXT-SIM ASCIIART ----
    asciiart_check(EMU, EXT_BIN, "ext-sim", check)

    # ---- 5. EXT-HW composite boot, both emulators ----
    hw = HWEXT_BIN.read_bytes()
    comp = bytearray(0x30000 + len(hw))
    struct.pack_into(">I", comp, 0, 0x40000)    # reset SSP
    struct.pack_into(">I", comp, 4, 0x30000)    # reset PC -> HWENTRY
    comp[0x30000:] = hw
    COMPOSITE.write_bytes(comp)
    hw_entries = [
        ("C", "PRINT &H1234", "", num(4660)),
        ("C", 'PRINT INSTR("HELLO","LL")', "", num(3)),
        ("C", "DOKE 36864,4660: PRINT DEEK(36864)", "", num(4660)),
        ("L", '10 IF 0 THEN PRINT "T" ELSE PRINT "F"', "", None),
        ("C", "RUN", "", "F\r\n\r\nREADY.\r\n"),
        ("C", ENDMARK, "", None),
    ]
    for emu, tag in ((EMU, "ext-hw"), (EMU_STRICT, "ext-hw-strict")):
        tx = run_session(emu, COMPOSITE, hw_entries,
                         HERE / f"{tag}.script", HERE / f"{tag}.out",
                         tag, check)
        i_b = tx.find("### COMMODORE BASIC ###")
        i_f = tx.find("40960 BYTES FREE")
        i_r = tx.find("READY.")
        check(f"{tag}: banner + 40960 BYTES FREE + READY, in order",
              0 <= i_b < i_f < i_r,
              f"banner@{i_b} free@{i_f} ready@{i_r}")
        got = regions68(tx, hw_entries)
        for idx, e in enumerate(hw_entries):
            if e[0] == "L" or e[3] is None:
                continue
            check(f"{tag}: [{e[1]}]", got[idx] == e[3],
                  f"got {got[idx]!r} want {e[3]!r}"
                  if got[idx] != e[3] else "")
        asciiart_check(emu, COMPOSITE, tag, check)

    # ---- 6. faithful regression via run_break.py ----
    r = subprocess.run([sys.executable, str(HERE / "run_break.py")],
                       capture_output=True, text=True, timeout=3600)
    tail = [l for l in (r.stdout + r.stderr).splitlines()
            if "FAIL" in l]
    check("regression run_break.py (cascades m5d gate + run_hw)",
          r.returncode == 0, "; ".join(tail[:4]) if tail else "exit 0")

    # ---- 7. EXT-flavour regression: run_m5d against EXT source ----
    faithful_src = (HERE / "msbasic68k.asm").read_bytes()
    try:
        (HERE / "msbasic68k.asm").write_bytes(
            (HERE / "msbasic68k-ext.asm").read_bytes())
        r = subprocess.run([sys.executable, str(HERE / "run_m5d.py")],
                           capture_output=True, text=True,
                           timeout=3600)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if l.startswith("FAIL")]
        known = ("PRINT 10^38; 2^31", "COS(3.14159265)")
        unknown = [l for l in fails
                   if not any(k in l for k in known)]
        check("EXT flavour: run_m5d cascade (only 2 known ulp diffs)",
              "116/118 checks PASS" in out and len(fails) == 2
              and not unknown,
              "; ".join(unknown[:4]) if unknown
              else "116/118 with the 2 known FAILs")
    finally:
        (HERE / "msbasic68k.asm").write_bytes(faithful_src)
        r = subprocess.run([sys.executable, str(HERE / "build.py"),
                            "sim"], capture_output=True, text=True)
        data = (HERE / "msbasic68k.bin").read_bytes()
        check("faithful build restored after the swap",
              r.returncode == 0 and len(data) == 15496
              and bsd_sum(data) == 23356,
              f"{len(data)} bytes, sum {bsd_sum(data)}")

    n_fail = sum(1 for _, ok in checks if not ok)
    print(f"\n{len(checks) - n_fail}/{len(checks)} checks PASS")
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
