#!/usr/bin/env python3
"""M5a verification for the MS-BASIC 68K port.

Scope under test (see m5a-results.md):
  - GOSUB/RETURN (incl. two-level nesting); bare RETURN is
    ?RG ERROR on the port (the golden prints its long-form
    "RETURN WITHOUT GOSUB" -- checked as a substring there).
  - String variables, reassignment, CAT ('+' on strings),
    string comparison in IF (lexicographic, all six operators).
  - GETSPA + GARBAG: two stress programs whose garbage volume
    exceeds the string space on BOTH machines (port: 61,440
    bytes; CBM golden: 31,743), so finishing at all proves the
    collector ran; the second also keeps live CAT-built strings
    in variables across the collections and prints them after.
  - Accumulation A$=A$+"AB" x 50.
  - FRE(0) / FRE("X"): the value is memory-map dependent, so it
    is checked against the port's own map (fresh machine:
    FRETOP-STREND = 61436, floated as a signed word = -4100),
    not against the golden.
  - Terminal width 80 columns (Kyo, 2026-11-19): comma zones
    are 10 wide with the last zone starting at column 70
    (NCMPOS -- the base text's own formula,
    ((LINLEN/CLMWID)-1)*CLMWID).  Zone output is NOT
    golden-compared at any column: the py65 harness's KERNAL
    CHROUT stub does not maintain the cursor column, so on the
    golden every comma pads a full zone of ten $1D bytes
    regardless of position (measured; see m5a-results.md).
    All zone checks therefore carry expectations derived from
    the port's spec (the original's algorithm, CLMWID=10,
    LINLEN=80), below column 30 as well as past it.

Expectations marked "G" are byte-compared with the CBM BASIC 2
golden (py65, ../run_cbmbasic2.py), with the standing $1D ->
$20 normalization for the numeric trailing byte (NUMSPC).
On a mismatch the first differing byte position is reported.

Regressions run_m1.py .. run_m4.py run as subprocesses at the
end and must exit 0.  (run_m4.py's two M4-era expectations --
the column-31 zone line and PRINT "A"+"B" -- were updated to
the M5a spec; see m5a-results.md.)  Exit status 0 = all PASS.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SIM = Path.home() / "workspace/mc68000-selfhost/sim"
EMU = os.environ.get("MSB_EMU", str(SIM / "emu"))
ASM68K = Path.home() / "workspace/mc68000-selfhost/asm68k-py/asm68k.py"

SRC = HERE / "msbasic68k.asm"
BIN = HERE / "msbasic68k.bin"
LST = HERE / "msbasic68k.lst"
SCRIPT = HERE / "m5a.script"
OUT = HERE / "m5a.out"

ENDMARK = 'PRINT "ZZM5END"'

S70 = "0123456789" * 7            # exactly 70 characters
S69 = "0123456789" * 6 + "012345678"  # exactly 69 characters

# (line, mode, spec68)
#   mode "G": byte-compare with the golden (normalized)
#   mode "S": 68K-only expectation in spec68 (golden still fed
#             the line, to keep the two sessions in lockstep)
#   mode "R": bare RETURN -- port "?RG ERROR", golden long form
SESSION = [
    ('PRINT FRE(0)', "S", "-4100 "),
    ('PRINT FRE("X")', "S", "-4100 "),
    ("RETURN", "R", None),
    ('A$="FOO"', "G", None),
    ('B$="BAR"', "G", None),
    ('PRINT A$+B$+"!"', "G", None),
    ('A$="X"', "G", None),
    ("PRINT A$", "G", None),
    ('A$="FOO"', "G", None),
    ('IF A$="FOO" THEN PRINT "EQ1"', "G", None),
    ('IF A$<>"BAR" THEN PRINT "NE1"', "G", None),
    ('IF "ABC"<"ABD" THEN PRINT "LT1"', "G", None),
    ('IF "ABC">"ABD" THEN PRINT "GTX"', "G", None),
    ('IF "ABD">"ABC" THEN PRINT "GT1"', "G", None),
    ('IF A$<="FOO" THEN PRINT "LE1"', "G", None),
    ('IF A$>="FOO" THEN PRINT "GE1"', "G", None),
    ('IF "ABC"="ABC" THEN PRINT "EQ2"', "G", None),
    ('PRINT "A"+"B"', "G", None),
    ("A=5", "G", None),
    ('A$="STR"', "G", None),
    ("PRINT A;A$", "G", None),
    ("PRINT 1,2,3", "S", " 1 " + " " * 7 + " 2 " + " " * 7 +
     " 3 "),
    # ---- 80-column zone spec (past column 30: no golden) ----
    ('PRINT "A","B","C","D","E","F","G","H"', "S",
     "".join(c + " " * 9 for c in "ABCDEFG") + "H"),
    (f'PRINT "{S70}","X"', "S", S70 + "\r\n" + "X"),
    (f'PRINT "{S69}","Y"', "S", S69 + " " + "Y"),
    ('PRINT "012345678901234567890123456789X",1', "S",
     "012345678901234567890123456789X" + " " * 9 + " 1 "),
    # ---- programs (golden-compared) ----
    ("NEW", "G", None),
    ('10 GOSUB 100: PRINT "BACK": END', "G", None),
    ('100 PRINT "SUB": RETURN', "G", None),
    ("RUN", "G", None),
    ("NEW", "G", None),
    ('10 GOSUB 100: PRINT "BACK1": END', "G", None),
    ('100 GOSUB 200: PRINT "SUB1": RETURN', "G", None),
    ('200 PRINT "SUB2": RETURN', "G", None),
    ("RUN", "G", None),
    ("NEW", "G", None),
    ('10 A$=""', "G", None),
    ('20 FOR I=1 TO 50: A$=A$+"AB": NEXT I', "G", None),
    ("30 PRINT A$", "G", None),
    ("RUN", "G", None),
    ("NEW", "G", None),
    ('10 A$="0123456789"', "G", None),
    ("20 FOR I=1 TO 2000", "G", None),
    ("30 B$=A$+A$+A$+A$+A$", "G", None),
    ("40 NEXT I", "G", None),
    ('50 PRINT "SURVIVED"', "G", None),
    ("60 PRINT B$", "G", None),
    ("RUN", "G", None),
    ("NEW", "G", None),
    ('10 A$="AL"+"PHA"', "G", None),
    ('20 B$="BE"+"TA"', "G", None),
    ("30 FOR I=1 TO 900", "G", None),
    ("40 C$=A$+B$+A$+B$+A$+B$", "G", None),
    ("50 NEXT I", "G", None),
    ('60 PRINT A$;"-";B$;"-";C$', "G", None),
    ("RUN", "G", None),
]

LINES = [ln for ln, _, _ in SESSION]


def assemble() -> bool:
    r = subprocess.run(
        [sys.executable, str(ASM68K), str(SRC), "--bin", str(BIN),
         "--list", str(LST), "-o", str(HERE / "msbasic68k.c")],
        capture_output=True, text=True)
    print("asm68k:", (r.stdout + r.stderr).strip())
    return r.returncode == 0


def payloads68(tx: str, lines):
    """Per-line response payloads from the 68K transcript
    (run_m4.py style: locate each line's echo, then the response
    up to the following READY.)."""
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


def extract_payload(seg: bytes) -> bytes:
    """CBM segment (after previous READY.) -> response payload
    (run_m3.py style)."""
    if seg.startswith(b"\r\n"):
        seg = seg[2:]
    if seg.startswith(b"\r\nREADY.\r\n"):
        return b""
    j = seg.find(b"\r\n\r\nREADY.\r\n")
    if j < 0:
        return None
    return seg[:j]


def run_golden():
    """Feed the same session to CBM BASIC 2 under py65 and
    collect per-line payloads (run_m3.py's runner, with a
    stored-line payload of "" and a large budget for RUN)."""
    sys.path.insert(0, str(ROOT))
    import run_cbmbasic2 as g

    payloads = []
    raw = []
    g.run_until(lambda: g.ready_count() >= 1, 5_000_000, "cold")
    if g.ready_count() < 1:
        raise RuntimeError("golden: no initial READY")
    mark = len(g.out)
    rc = 1
    for ln in LINES:
        g.feed(ln + "\r")
        if ln[0].isdigit():
            # Storing a program line prints no READY. on CBM
            # BASIC 2; wait for the echoed CRLF to settle.
            for _ in range(400):
                g.run_until(lambda: False, 25_000, ln)
                if len(g.out) - mark >= 2:
                    break
            prev = len(g.out)
            for _ in range(400):
                g.run_until(lambda: False, 25_000, ln)
                if len(g.out) == prev:
                    break
                prev = len(g.out)
            payloads.append(b"")
            raw.append(b"")
            mark = len(g.out)
        else:
            rc += 1
            budget = 600_000_000 if ln == "RUN" else 20_000_000
            g.run_until(lambda rc=rc: g.ready_count() >= rc,
                        budget, ln)
            if g.ready_count() < rc:
                payloads.append(None)
                raw.append(None)
                mark = len(g.out)
                continue
            seg = bytes(g.out[mark:])
            raw.append(seg)
            payloads.append(extract_payload(seg))
            mark = len(g.out)
    return payloads, raw


def first_diff(a: bytes, b: bytes) -> str:
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return (f"first diff at byte {i}: "
                    f"golden={a[i]:#04x} 68k={b[i]:#04x}")
    if len(a) != len(b):
        return (f"length differs at byte {n}: "
                f"golden {len(a)} bytes, 68k {len(b)} bytes")
    return ""


def main() -> int:
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name, detail)

    if not assemble():
        print("FAIL: assembly error")
        return 1

    for chk in ("check_branches.py", "check_short_branches.py"):
        r = subprocess.run([sys.executable, str(HERE / chk),
                            str(LST), str(BIN)],
                           capture_output=True, text=True)
        tail = (r.stdout + r.stderr).strip().splitlines()
        check(f"branch checker {chk}",
              bool(tail) and tail[-1].startswith("0 bad"),
              tail[-1] if tail else "(no output)")

    # ---- 68K side ----
    all_lines = LINES + [ENDMARK]
    SCRIPT.write_bytes(
        "".join(l + "\r" for l in all_lines).encode("ascii"))
    cmd = [EMU, "--image", str(BIN),
           "--masters", str(SIM / "masters"),
           "--script", str(SCRIPT), "--out", str(OUT),
           "--until", "\r\nZZM5END\r\n", "--settle", "0",
           # M5e: the until string is the RESPONSE framing, not the
           # bare marker: the bare "ZZM5END" also matches the input
           # echo, and once the port's cycle counts shifted (M5e
           # realignment) the emu stopped between echo and response.
           "--maxcycles", "3000000000"]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=900)
    print("emu:", r.stdout.strip(), f"(rc={r.returncode})")
    check("emu exit code 0 (until-string seen)", r.returncode == 0)
    tx = OUT.read_bytes().decode("latin-1")
    got68 = payloads68(tx, all_lines)
    check("endmark payload", got68[-1] == "ZZM5END",
          f"got {got68[-1]!r}")

    # ---- golden side ----
    golden, golden_raw = run_golden()

    # ---- compare ----
    norm = 0
    for idx, (ln, mode, spec) in enumerate(SESSION):
        k = got68[idx]
        if mode == "S":
            check(f"S [{ln}]", k == spec,
                  f"got {k!r} want {spec!r}" if k != spec
                  else f"= {spec!r}")
            continue
        if mode == "R":
            # An error response has no blank line before READY.,
            # so extract_payload cannot frame it; use the raw
            # segment (the golden's long-form message is checked
            # as a substring -- the port's short form is its own
            # standing convention since M1).
            g = golden_raw[idx]
            check("R [RETURN] port answers ?RG ERROR",
                  k == "?RG ERROR", f"got {k!r}")
            check("R [RETURN] golden refuses it too",
                  g is not None and
                  b"RETURN WITHOUT GOSUB" in g,
                  f"golden={g!r}")
            continue
        g = golden[idx]
        if g is None or k is None:
            check(f"G [{ln}] payload extracted", False,
                  f"golden={g!r} 68k={k!r}")
            continue
        kb = k.encode("latin-1")
        norm += g.count(b"\x1d")
        gnorm = g.replace(b"\x1d", b"\x20")
        if gnorm == kb:
            check(f"G [{ln}]", True, f"= {kb!r}")
        else:
            check(f"G [{ln}]", False,
                  f"{first_diff(gnorm, kb)}  "
                  f"golden={gnorm!r} 68k={kb!r}")
    print(f"note: OUTSP $1D (CBM) vs $20 (68K) bytes normalized: "
          f"{norm}")

    # ---- regressions ----
    for t in ("run_m1.py", "run_m2.py", "run_m3.py", "run_m4.py"):
        r = subprocess.run([sys.executable, str(HERE / t)],
                           capture_output=True, text=True,
                           timeout=1800)
        tail = [l for l in (r.stdout + r.stderr).splitlines()
                if "FAIL" in l]
        check(f"regression {t}", r.returncode == 0,
              "; ".join(tail[:4]) if tail else "exit 0")

    n_fail = sum(1 for _, ok in checks if not ok)
    print(f"\n{len(checks) - n_fail}/{len(checks)} checks PASS")
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
