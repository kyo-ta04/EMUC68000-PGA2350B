#!/usr/bin/env python3
"""M5b verification for the MS-BASIC 68K port.

Scope under test (see m5b-results.md):
  - DATA/READ/RESTORE: mixed numeric/string READ, quoted
    items containing ',' and ':', RESTORE re-read, DATA
    search across statements and lines, empty items,
    trailing spaces in unquoted items, ?OD ERROR on
    exhaustion, a bad item terminator reported in the DATA
    line, READ in direct mode.
  - INPUT: numeric and string variables, a prompt literal,
    several variables from one line and from several lines
    (the "?? " continuation), ?REDO FROM START on bad data,
    ?EXTRA IGNORED, direct-mode INPUT (?ID ERROR), and an
    empty first line stopping silently so CONT re-runs the
    INPUT statement.
  - ON...GOTO / ON...GOSUB: dispatch, 0 and past-the-end
    fall-through.
  - STOP/CONT: BREAK IN-free "BREAK" + READY, CONT resumes;
    CONT with nothing to continue is ?CN ERROR.
  - GET: a waiting key (string and numeric -- the numeric
    form is the FIN parse of the character, not its code),
    and, in a separate mini-session, no key at all.

Comparison model: a "region" is the response to one fed
line, from just after the line's echo (68K) or the previous
READY mark (golden) up to and including the next
"READY.\r\n".  Regions are byte-compared after the standing
$1D -> $20 normalization (NUMSPC).  Two systematic
differences are handled explicitly:
  - The py65 harness's CHRIN does not echo typed input, but
    the port's INLIN does.  For INPUT tests the fed data
    lines' echoed characters (not the CRLF: CBM's input
    routine emits the same CRLF when the line's CR arrives)
    are stripped from the 68K region, once each, in order
    (spec "strips").  Symmetrically, each golden region
    drops the one leading CRLF CBM emits when a line is
    entered (the port's twin of that CRLF ends its echo).
  - Error texts are long-form on the golden and two-letter
    on the port (the standing convention since M1): mode
    "R" checks the port region byte-exactly and the golden
    region by substrings.

A separate mini-session checks GET with an empty input
queue on both sides (the main 68K script is one preloaded
FIFO, so a truly empty queue only exists at its end).

Regressions run_m1.py .. run_m5a.py run as subprocesses at
the end and must exit 0.  Exit status 0 = all PASS.
"""
import importlib
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
SCRIPT = HERE / "m5b.script"
OUT = HERE / "m5b.out"
SCRIPT2 = HERE / "m5b2.script"
OUT2 = HERE / "m5b2.out"

ENDMARK = 'PRINT "ZZM5";"END"'  # split so the echo alone
                                # cannot trip the emu's --until

# Session entries:
#   ("L", text)                          stored program line
#   ("C", text, mode, spec, data)        direct line; data =
#       extra bytes fed right after text+"\r" (INPUT data
#       lines, GET keys).  mode "G": region compare, spec =
#       list of echo strings to strip from the 68K region.
#       mode "R": spec = (port region bytes, [golden
#       substrings]).  mode "S": spec = the 68K region
#       string (golden fed in lockstep, region unchecked).
SESSION = [
    # CONT with nothing to continue (fresh boot)
    ("C", "CONT", "R",
     (b"?CN ERROR\r\n\r\nREADY.\r\n", [b"CAN'T CONTINUE"]), ""),
    # ---- READ / DATA ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A,B,C$"),
    ("L", "20 PRINT A;B;C$"),
    ("L", "30 DATA 42,-7,HELLO"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A$,B$,C"),
    ("L", '20 PRINT A$;"|";B$;"|";C'),
    ("L", '30 DATA "X,Y","P:Q",3.5'),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A: PRINT A"),
    ("L", "20 RESTORE: READ B: PRINT B"),
    ("L", "30 DATA 99"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A,B"),
    ("L", "20 PRINT A;B"),
    ("L", '30 PRINT "X": DATA 111'),
    ("L", "40 DATA 222"),
    # Golden-probed CBM quirk: FINDATA's colon path checks
    # the byte IMMEDIATELY after ':' for the DATA token, so
    # ": DATA" (with a space) is missed; the search finds
    # line 40's 222 for A, then runs out at B -> OD on both
    # machines, before anything prints (R-mode).
    ("C", "RUN", "R",
     (b"?OD ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"OUT OF DATA", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A,B"),
    ("L", "20 PRINT A;B"),
    ("L", '30 PRINT "X":DATA 111'),
    ("L", "40 DATA 222"),
    # ...but ":DATA" with no space IS found (golden prints
    # 111/222, then X from line 30).
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A$,B$"),
    ("L", '20 PRINT A$;"|";B$'),
    ("L", "30 DATA ABC : DATA DEF"),
    # A ':' ends a DATA statement's items, and CRUNCH copies
    # the rest of a DATA line verbatim, so the second "DATA"
    # is data text, not a statement: B$'s search runs out
    # -> OD on both machines (golden-probed; R-mode).
    ("C", "RUN", "R",
     (b"?OD ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"OUT OF DATA", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A,B$,C"),
    ("L", '20 PRINT A;"|";B$;"|";C'),
    ("L", "30 DATA 1,,3"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A,B"),
    ("L", "20 DATA 1"),
    ("C", "RUN", "R",
     (b"?OD ERROR IN  10\r\n\r\nREADY.\r\n", [b"OUT OF DATA"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ A"),
    ("L", "20 DATA 12X"),
    ("C", "RUN", "R",
     (b"?SN ERROR IN  20\r\n\r\nREADY.\r\n",
      [b"SYNTAX", b"IN  20"]), ""),
    # READ in direct mode is legal
    ("C", "NEW", "G", [], ""),
    ("L", "10 DATA 77"),
    ("C", "READ A", "G", [], ""),
    ("C", "PRINT A", "G", [], ""),
    # ---- INPUT ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 INPUT A"),
    ("L", '20 PRINT "GOT";A'),
    ("C", "RUN", "G", ["42"], "42\r"),
    ("C", "NEW", "G", [], ""),
    ("L", '10 INPUT "NAME";N$'),
    ("L", '20 PRINT "HI ";N$'),
    ("C", "RUN", "G", ["BOB"], "BOB\r"),
    ("C", "NEW", "G", [], ""),
    ("L", "10 INPUT A,B$"),
    ("L", "20 PRINT A;B$"),
    ("C", "RUN", "G", ["7,SEVEN"], "7,SEVEN\r"),
    ("C", "NEW", "G", [], ""),
    ("L", "10 INPUT A,B"),
    ("L", "20 PRINT A;B"),
    ("C", "RUN", "G", ["5", "6"], "5\r6\r"),
    ("C", "NEW", "G", [], ""),
    ("L", "10 INPUT A"),
    ("L", '20 PRINT "OK";A'),
    ("C", "RUN", "G", ["9X", "9"], "9X\r9\r"),
    ("C", "NEW", "G", [], ""),
    ("L", "10 INPUT A"),
    ("L", '20 PRINT "DONE";A'),
    ("C", "RUN", "G", ["1,2"], "1,2\r"),
    ("C", "INPUT A", "R",
     (b"?ID ERROR\r\n\r\nREADY.\r\n", [b"ILLEGAL DIRECT"]), ""),
    # empty first INPUT line: silent stop, CONT re-runs INPUT
    ("C", "NEW", "G", [], ""),
    ("L", '10 INPUT A: PRINT "AFTER";A'),
    ("C", "RUN", "G", [], "\r"),
    ("C", "CONT", "G", ["33"], "33\r"),
    # ---- ON ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 X=2"),
    ("L", "20 ON X GOTO 100,200,300"),
    ("L", '30 PRINT "FELL": END'),
    ("L", '100 PRINT "ONE": END'),
    ("L", '200 PRINT "TWO": END'),
    ("L", '300 PRINT "THREE": END'),
    ("C", "RUN", "G", [], ""),
    ("L", "10 X=0"),
    ("C", "RUN", "G", [], ""),
    ("L", "10 X=4"),
    ("C", "RUN", "G", [], ""),
    ("L", "10 X=3"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 ON 2 GOSUB 100,200"),
    ("L", '20 PRINT "BACK": END'),
    ("L", '100 PRINT "S1": RETURN'),
    ("L", '200 PRINT "S2": RETURN'),
    ("C", "RUN", "G", [], ""),
    # ---- STOP / CONT ----
    ("C", "NEW", "G", [], ""),
    ("L", '10 PRINT "ONE"'),
    ("L", "20 STOP"),
    ("L", '30 PRINT "TWO"'),
    ("C", "RUN", "G", [], ""),
    ("C", "CONT", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", '10 PRINT "A": STOP: PRINT "B"'),
    ("C", "RUN", "G", [], ""),
    ("C", "CONT", "G", [], ""),
    # STOP, then edit the program (re-enter line 30), then
    # CONT: golden-probed -- entering ANY program line
    # invalidates the continue context on the original
    # (?CAN'T CONTINUE ERROR), and the port agrees (R-mode).
    ("C", "NEW", "G", [], ""),
    ("L", '10 PRINT "ONE"'),
    ("L", "20 STOP"),
    ("L", '30 PRINT "OLD"'),
    ("C", "RUN", "G", [], ""),
    ("L", '30 PRINT "NEW"'),
    ("C", "CONT", "R",
     (b"?CN ERROR\r\n\r\nREADY.\r\n", [b"CAN'T CONTINUE"]), ""),
    # ---- GET with a waiting key ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 GET A$"),
    ("L", '20 PRINT "K=";A$;"!"'),
    ("C", "RUN", "G", [], "Z"),
    ("C", "NEW", "G", [], ""),
    ("L", "10 GET N"),
    ("L", '20 PRINT "N=";N'),
    ("C", "RUN", "G", [], "5"),
    ("C", "NEW", "G", [], ""),
    ("L", "10 GET N"),
    ("L", '20 PRINT "N=";N'),
    # A non-numeric key in a numeric GET is the original's
    # INPUTERR trap: ?SYNTAX ERROR with CURLIN poisoned, so
    # no " IN n" suffix on either side (R-mode).
    ("C", "RUN", "R",
     (b"?SN ERROR\r\n\r\nREADY.\r\n", [b"SYNTAX ERROR"]), "Q"),
]

# Mini-session: GET with a truly empty input queue.
MINI = [
    "10 GET A$",
    "20 GET N",
    '30 PRINT "K=";A$;"!N=";N;"ZZM5";"END"',
    "RUN",
]


def fed_bytes(entry):
    if entry[0] == "L":
        return entry[1] + "\r"
    return entry[1] + "\r" + entry[4]


def assemble() -> bool:
    r = subprocess.run(
        [sys.executable, str(ASM68K), str(SRC), "--bin", str(BIN),
         "--list", str(LST), "-o", str(HERE / "msbasic68k.c")],
        capture_output=True, text=True)
    print("asm68k:", (r.stdout + r.stderr).strip())
    return r.returncode == 0


def regions68(tx: str, entries):
    """Per-entry response regions from the 68K transcript:
    the text after the entry's echo up to and including the
    next "READY.\r\n" (None for stored lines / not found)."""
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


def run_golden(entries):
    """Feed the session to CBM BASIC 2 under py65 and collect
    per-entry regions (raw bytes ending at the next
    "READY.\r\n"; b"" for stored lines)."""
    sys.path.insert(0, str(ROOT))
    import run_cbmbasic2 as g

    regions = []
    g.run_until(lambda: g.ready_count() >= 1, 5_000_000, "cold")
    if g.ready_count() < 1:
        raise RuntimeError("golden: no initial READY")
    mark = len(g.out)
    rc = 1
    for e in entries:
        if e[0] == "L":
            g.feed(e[1] + "\r")
            # Storing a line prints nothing; run until the
            # output is stable (the CPU halts at CHRIN).
            for _ in range(400):
                prev = len(g.out)
                g.run_until(lambda: False, 25_000, e[1])
                if len(g.out) == prev and g.state["halt"]:
                    break
            regions.append(b"")
            mark = len(g.out)
            continue
        rc += 1
        g.feed(fed_bytes(e))
        budget = 300_000_000 if e[1] == "RUN" else 50_000_000
        g.run_until(lambda rc=rc: g.ready_count() >= rc,
                    budget, e[1])
        if g.ready_count() < rc:
            regions.append(None)
            mark = len(g.out)
            continue
        seg = bytes(g.out[mark:])
        j = seg.find(b"READY.\r\n")
        if j < 0:
            regions.append(None)
            mark = len(g.out)
            continue
        region = seg[:j + len(b"READY.\r\n")]
        # CBM emits one CRLF when a line is entered (the
        # screen editor's line terminator); the port's
        # equivalent CRLF terminates the echo, which the 68K
        # regions exclude.  Drop exactly one leading CRLF.
        if region.startswith(b"\r\n"):
            region = region[2:]
        regions.append(region)
        mark += j + len(b"READY.\r\n")
    return regions


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

    # ---- 68K main session ----
    all_entries = SESSION + [("C", ENDMARK, "G", [], "")]
    SCRIPT.write_bytes(
        "".join(fed_bytes(e) for e in all_entries).encode("latin-1"))
    cmd = [EMU, "--image", str(BIN),
           "--masters", str(SIM / "masters"),
           "--script", str(SCRIPT), "--out", str(OUT),
           "--until", "ZZM5END", "--settle", "2000000",
           "--maxcycles", "1000000000"]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=900)
    print("emu:", r.stdout.strip(), f"(rc={r.returncode})")
    check("emu exit code 0 (until-string seen)", r.returncode == 0)
    tx = OUT.read_bytes().decode("latin-1")
    got68 = regions68(tx, all_entries)
    check("endmark region", got68[-1] == "ZZM5END\r\n\r\nREADY.\r\n",
          f"got {got68[-1]!r}")

    # ---- golden main session ----
    golden = run_golden(all_entries)

    # ---- compare ----
    norm = 0
    for idx, e in enumerate(all_entries):
        if e[0] == "L":
            continue
        _, text, mode, spec, _data = e
        k = got68[idx]
        g = golden[idx]
        if mode == "R":
            kexact, gsubs = spec
            check(f"R [{text}] port region",
                  k is not None and
                  k.encode("latin-1") == kexact,
                  f"got {k!r}")
            check(f"R [{text}] golden refuses it too",
                  g is not None and
                  all(s in g for s in gsubs),
                  f"golden={g!r}")
            continue
        if k is None or g is None:
            check(f"G [{text}] region extracted", False,
                  f"golden={g!r} 68k={k!r}")
            continue
        kb = k.encode("latin-1")
        for echo in spec:  # strip INLIN echoes of INPUT data
            eb = echo.encode("latin-1")
            p = kb.find(eb)
            if p >= 0:
                kb = kb[:p] + kb[p + len(eb):]
        norm += g.count(b"\x1d")
        gnorm = g.replace(b"\x1d", b"\x20")
        if gnorm == kb:
            check(f"G [{text}]", True, f"= {kb!r}")
        else:
            check(f"G [{text}]", False,
                  f"{first_diff(gnorm, kb)}  "
                  f"golden={gnorm!r} 68k={kb!r}")
    print(f"note: NUMSPC $1D (CBM) vs $20 (68K) bytes "
          f"normalized: {norm}")

    # ---- mini-session: GET with an empty queue ----
    SCRIPT2.write_bytes(
        "".join(l + "\r" for l in MINI).encode("latin-1"))
    cmd = [EMU, "--image", str(BIN),
           "--masters", str(SIM / "masters"),
           "--script", str(SCRIPT2), "--out", str(OUT2),
           "--until", "ZZM5END", "--settle", "2000000",
           "--maxcycles", "100000000"]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=300)
    print("emu (mini):", r.stdout.strip(), f"(rc={r.returncode})")
    check("mini emu exit code 0", r.returncode == 0)
    tx2 = OUT2.read_bytes()
    check("mini 68K: GET with no key gives \"\" and 0",
          b"K=!N= 0 ZZM5END" in tx2, f"tx tail={tx2[-80:]!r}")

    import run_cbmbasic2 as g2
    importlib.reload(g2)
    g2.run_until(lambda: g2.ready_count() >= 1, 5_000_000, "cold2")
    mark = len(g2.out)
    for ln in MINI:
        g2.feed(ln + "\r")
    g2.run_until(lambda: b"ZZM5END" in bytes(g2.out),
                 100_000_000, "mini")
    seg = bytes(g2.out[mark:]).replace(b"\x1d", b"\x20")
    check("mini golden: GET with no key gives \"\" and 0",
          b"K=!N= 0 ZZM5END" in seg, f"seg={seg!r}")

    # ---- regressions ----
    for t in ("run_m1.py", "run_m2.py", "run_m3.py", "run_m4.py",
              "run_m5a.py"):
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
