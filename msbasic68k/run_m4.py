#!/usr/bin/env python3
"""M4 verification for the MS-BASIC 68K port -- Phase 1 acceptance.

Main gate: enter ASCIIART.BAS (19 lines, taken verbatim from
../research/mez6502/ASCIIART.BAS), RUN it, and compare the
picture (25 rows x 79 chars + CRLF = 2,025 bytes) byte for byte
with the CBM BASIC 2 golden in ../golden/asciiart-output.txt
(sum16 = 25584, CRC32 = 0D6D8795).  After the picture the machine
must be back at READY.

Also measured: the RUN interval's cycle count, as the difference
of two emu runs (full session minus program-entry-only session).
emu counts in 100,000-cycle quanta and checks the --until marker
after each quantum, so the figure carries roughly +/-100k cycles
of quantization error.  --settle 0 is passed so no settle cycles
are included.

Extra feature checks (direct mode, own spec): CHR$ (single and
packed pair), IF statement form (true/false, whole-line skip on
false), IF..GOTO in a program (taken / not taken), comma zones
(width 10; the last zone started at column 30 per the base
text's REALIO=3 constants in M4 -- M5a moved it to column 70
with the 80-column terminal unification, Kyo's 2026-11-19
decision, and the one affected expectation below is marked).
String concatenation was an M5 item in M4 (?SN ERROR then);
M5a implements it, and the check below now expects "AB".

Regressions run_m1.py / run_m2.py / run_m3.py must PASS, and the
branch-target checker (check_branches.py, from M3) must report
0 bad branches.  Exit status 0 = all PASS.
"""
import re
import os
import subprocess
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SIM = Path.home() / "workspace/mc68000-selfhost/sim"
EMU = os.environ.get("MSB_EMU", str(SIM / "emu"))
ASM68K = Path.home() / "workspace/mc68000-selfhost/asm68k-py/asm68k.py"

SRC = HERE / "msbasic68k.asm"
BIN = HERE / "msbasic68k.bin"
LST = HERE / "msbasic68k.lst"
SCRIPT = HERE / "m4.script"
OUT = HERE / "m4.out"
SCRIPT_B = HERE / "m4b.script"
OUT_B = HERE / "m4b.out"
SCRIPT_X = HERE / "m4x.script"
OUT_X = HERE / "m4x.out"

BAS = ROOT / "research" / "mez6502" / "ASCIIART.BAS"
GOLDEN_PATH = ROOT / "golden" / "asciiart-output.txt"
GOLDEN_LEN = 2025
GOLDEN_SUM16 = 25584
GOLDEN_CRC32 = 0x0D6D8795

ENDMARK = 'PRINT "ZZM4END"'


def sum16(data: bytes) -> int:
    s = 0
    for b in data:
        s = (s + b) & 0xFFFF
    return s


def assemble() -> bool:
    r = subprocess.run(
        [sys.executable, str(ASM68K), str(SRC), "--bin", str(BIN),
         "--list", str(LST), "-o", str(HERE / "msbasic68k.c")],
        capture_output=True, text=True)
    print("asm68k:", (r.stdout + r.stderr).strip())
    return r.returncode == 0


def run_emu(script: Path, out: Path, until: str, maxcycles: int,
            timeout: int):
    cmd = [EMU, "--image", str(BIN),
           "--masters", str(SIM / "masters"),
           "--script", str(script), "--out", str(out),
           "--until", until, "--settle", "0",
           "--maxcycles", str(maxcycles)]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=timeout)
    m = re.search(r"after (\d+) cycles", r.stdout)
    cycles = int(m.group(1)) if m else None
    print(f"emu[{script.name}]:", r.stdout.strip(), f"(rc={r.returncode})")
    return r.returncode, cycles, out.read_bytes()


def payloads(tx: str, lines):
    """Per-line response payloads, run_m3.py style."""
    res = []
    pos = 0
    for ln in lines:
        echo = ln + "\r\n"
        i = tx.find(echo, pos)
        if i < 0:
            res.append(None)
            continue
        start = i + len(echo)
        if ln[0].isdigit():
            # M8: storing a numbered line prints NOTHING (no
            # READY.); the next bytes are the next echo.
            res.append("")
            pos = start
            continue
        rest = tx[start:]
        if rest.startswith("\r\nREADY.\r\n"):
            res.append("")
            pos = start + len("\r\nREADY.\r\n")
            continue
        j = rest.find("\r\n\r\nREADY.\r\n")
        if j < 0:
            res.append(None)
            pos = start
            continue
        res.append(rest[:j])
        pos = start + j + len("\r\n\r\nREADY.\r\n")
    return res


def main() -> int:
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name, detail)

    if not assemble():
        print("FAIL: assembly error")
        return 1

    # ---- branch-target checker (from M3) ----
    for chk in ("check_branches.py", "check_short_branches.py"):
        r = subprocess.run([sys.executable, str(HERE / chk),
                            str(LST), str(BIN)],
                           capture_output=True, text=True)
        tail = (r.stdout + r.stderr).strip().splitlines()
        check(f"branch checker {chk}",
              bool(tail) and tail[-1].startswith("0 bad"),
              tail[-1] if tail else "(no output)")

    # ---- golden sanity ----
    golden = GOLDEN_PATH.read_bytes()
    check("golden length", len(golden) == GOLDEN_LEN,
          f"{len(golden)} bytes")
    check("golden sum16", sum16(golden) == GOLDEN_SUM16,
          f"{sum16(golden)}")
    check("golden CRC32",
          (zlib.crc32(golden) & 0xFFFFFFFF) == GOLDEN_CRC32,
          f"{zlib.crc32(golden) & 0xFFFFFFFF:08X}")

    # ---- main run: enter ASCIIART.BAS and RUN it ----
    prog = [ln for ln in
            BAS.read_text().splitlines() if ln.strip()]
    check("ASCIIART.BAS line count", len(prog) == 19,
          f"{len(prog)} lines")
    lines_a = prog + ["RUN", ENDMARK]
    SCRIPT.write_bytes(
        "".join(l + "\r" for l in lines_a).encode("ascii"))
    rc, cyc_a, txa = run_emu(SCRIPT, OUT, "ZZM4END",
                             5_000_000_000, 1800)
    check("emu A exit code 0 (until-string seen)", rc == 0)

    pic = None
    i = txa.find(b"RUN\r\n")
    if i >= 0:
        pic = txa[i + 5: i + 5 + GOLDEN_LEN]
    check("picture extracted (2025 bytes after RUN echo)",
          pic is not None and len(pic) == GOLDEN_LEN)
    if pic is not None and len(pic) == GOLDEN_LEN:
        if pic == golden:
            check("ASCIIART picture == golden (byte exact)", True,
                  f"sum16={sum16(pic)} crc32="
                  f"{zlib.crc32(pic) & 0xFFFFFFFF:08X}")
        else:
            k = next(n for n in range(GOLDEN_LEN)
                     if pic[n] != golden[n])
            row, col = k // 81, k % 81
            check("ASCIIART picture == golden (byte exact)", False,
                  f"first mismatch at byte {k} (row {row + 1}, "
                  f"col {col + 1}): expected "
                  f"{golden[k]:02X} {chr(golden[k])!r}, got "
                  f"{pic[k]:02X} {chr(pic[k])!r}; "
                  f"sum16={sum16(pic)} (want {GOLDEN_SUM16}), "
                  f"crc32={zlib.crc32(pic) & 0xFFFFFFFF:08X} "
                  f"(want {GOLDEN_CRC32:08X})")
        after = txa[i + 5 + GOLDEN_LEN: i + 5 + GOLDEN_LEN + 16]
        check("READY. after the picture",
              after.startswith(b"\r\nREADY.\r\n"),
              repr(after))

    # ---- cycle measurement: entry-only run for the difference ----
    lines_b = prog + [ENDMARK]
    SCRIPT_B.write_bytes(
        "".join(l + "\r" for l in lines_b).encode("ascii"))
    rc_b, cyc_b, _ = run_emu(SCRIPT_B, OUT_B, "ZZM4END",
                             200_000_000, 600)
    check("emu B exit code 0", rc_b == 0)
    if cyc_a is not None and cyc_b is not None:
        run_cyc = cyc_a - cyc_b
        print(f"cycles: total A={cyc_a:,}, entry-only B={cyc_b:,}, "
              f"RUN interval ~= {run_cyc:,} "
              f"(~{run_cyc / 1e6:.1f} s at 1 MHz; "
              f"+/-100k quantization)")
        check("RUN cycle count recorded", run_cyc > 0,
              f"{run_cyc:,}")

    # ---- extra feature checks (direct mode / small programs) ----
    xlines = [
        'PRINT CHR$(65)',
        'PRINT CHR$(48);CHR$(49)',
        'PRINT CHR$(321)',
        'IF 1 THEN PRINT "YES1"',
        'IF 0 THEN PRINT "NO1"',
        'IF 0 THEN PRINT "NO2": PRINT "NO3"',
        'IF 3>2 THEN PRINT "YES2"',
        'PRINT 1,2',
        'PRINT SPC(3)"X"',
        'PRINT TAB(5)"Y"',
        'PRINT "AB";TAB(6)"Z"',
        'PRINT "0123456789ABCDEF",1',
        'PRINT "012345678901234567890123456789X",1',
        'PRINT "A"+"B"',
        'NEW',
        '10 IF 1 GOTO 30',
        '20 PRINT "BAD"',
        '30 PRINT "OKGO"',
        'RUN',
        'NEW',
        '10 IF 0 GOTO 30',
        '20 PRINT "TWO"',
        '30 PRINT "THREE"',
        'RUN',
        ENDMARK,
    ]
    xwant = {
        'PRINT CHR$(65)': "A",
        'PRINT CHR$(48);CHR$(49)': "01",
        'IF 1 THEN PRINT "YES1"': "YES1",
        'IF 0 THEN PRINT "NO1"': "",
        'IF 0 THEN PRINT "NO2": PRINT "NO3"': "",
        'IF 3>2 THEN PRINT "YES2"': "YES2",
        'PRINT 1,2': " 1 " + " " * 7 + " 2 ",
        'PRINT SPC(3)"X"': " " * 3 + "X",
        'PRINT TAB(5)"Y"': " " * 5 + "Y",
        'PRINT "AB";TAB(6)"Z"': "AB" + " " * 4 + "Z",
        'PRINT "0123456789ABCDEF",1':
            "0123456789ABCDEF" + " " * 4 + " 1 ",
        'PRINT "012345678901234567890123456789X",1':
            # M5a: 80-column terminal (NCMPOS=70): the comma at
            # column 31 now pads to the zone at column 40 instead
            # of forcing a newline (M4's REALIO=3 expectation).
            "012345678901234567890123456789X" + " " * 9 + " 1 ",
    }
    SCRIPT_X.write_bytes(
        "".join(l + "\r" for l in xlines).encode("ascii"))
    rc_x, _, txx_b = run_emu(SCRIPT_X, OUT_X, "ZZM4END",
                             200_000_000, 600)
    check("emu X exit code 0", rc_x == 0)
    txx = txx_b.decode("latin-1")
    got = payloads(txx, xlines)
    byline = dict(zip(xlines, got))
    for ln, want in xwant.items():
        check(f"X [{ln}]", byline.get(ln) == want,
              f"got {byline.get(ln)!r} want {want!r}"
              if byline.get(ln) != want else f"= {want!r}")
    # CHR$ out of range -> ?IQ ERROR (documented behavior check)
    p = byline.get('PRINT CHR$(321)')
    check("X [PRINT CHR$(321)] ?IQ ERROR",
          p is not None and "?IQ ERROR" in p, f"got {p!r}")
    # concatenation: an M5 item in M4 (?SN ERROR then); M5a
    # implements CAT, so the payload is now the joined string
    p = byline.get('PRINT "A"+"B"')
    check("X [PRINT \"A\"+\"B\"] is AB (CAT, M5a)",
          p == "AB", f"got {p!r}")
    # IF..GOTO programs: 'RUN' appears twice in the session, so
    # use the payload list by position (the raw transcript cannot
    # be used: it contains the echoed program lines, including
    # the word BAD itself).
    run_idx = [n for n, l in enumerate(xlines) if l == 'RUN']
    check("X [IF 1 GOTO 30] RUN payload is OKGO only",
          len(run_idx) == 2 and got[run_idx[0]] == "OKGO",
          f"got {got[run_idx[0]]!r}" if run_idx else "no RUN")
    check("X [IF 0 GOTO 30] RUN payload is TWO then THREE",
          len(run_idx) == 2 and got[run_idx[1]] == "TWO\r\nTHREE",
          f"got {got[run_idx[1]]!r}" if len(run_idx) == 2
          else "no second RUN")

    # ---- regressions ----
    for name in ("run_m1.py", "run_m2.py", "run_m3.py"):
        r = subprocess.run([sys.executable, str(HERE / name)],
                           capture_output=True, text=True, timeout=1200)
        tail = (r.stdout + r.stderr).strip().splitlines()
        check(f"regression {name}", r.returncode == 0,
              tail[-2] if len(tail) >= 2 else "")

    ok = all(v for _, v in checks)
    print("M4:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
