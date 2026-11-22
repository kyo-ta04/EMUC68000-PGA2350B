#!/usr/bin/env python3
"""M5c verification for the MS-BASIC 68K port.

Scope under test (see m5c-results.md):
  - Integer variables: assignment conversion (the original's
    ROUND + AYINT + QINT chain: floor semantics, the -32768
    rejection caused by the original's short NEG32768
    constant), integer arithmetic through the FAC, and the
    ?SN ERROR for an integer FOR variable (SUBFLG rule).
  - Arrays: DIM (multi-dimensional, several at once, computed
    and fractional sizes), implicit DIM, element assignment
    and reads for FP / integer / string arrays, nested array
    references in subscripts, READ into elements, scalar and
    array namespaces staying independent, and the errors
    ?DD (redimension), ?BS (bad subscript, including a
    dimension-count mismatch), ?IQ (negative / oversized
    subscript), ?TM (string subscript).
  - DEF FN / FN: definition and calls, argument save and
    restore (also across a nested call reusing the argument
    name), redefinition, FN in the argument of an FN call,
    undefined FN (?UF), DEF in direct mode (?ID), string FN
    name / string argument (?TM), an array as the DEF
    argument (?SN), a call before the DEF executes (?UF),
    and CLR wiping definitions.
  - GC: string array elements are followed by GARBAG (scan
    3): two stress programs generate ~90KB of garbage around
    live array strings; the live strings must survive
    byte-exactly on both machines.

Comparison model and conventions are exactly run_m5b.py's:
regions are byte-compared after the $1D -> $20 (NUMSPC)
normalization; "R" entries check the port region byte-exactly
and the golden region by substrings (long-form error texts).

Regressions run_m1.py .. run_m5b.py run as subprocesses at
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
SCRIPT = HERE / "m5c.script"
OUT = HERE / "m5c.out"

ENDMARK = 'PRINT "ZZM5";"END"'  # split so the echo alone
                                # cannot trip the emu's --until

IQ_R = (b"?IQ ERROR\r\n\r\nREADY.\r\n", [b"ILLEGAL QUANTITY"])
BS_R = (b"?BS ERROR\r\n\r\nREADY.\r\n", [b"BAD SUBSCRIPT"])

# Session entries: ("L", text) stored program line;
# ("C", text, mode, spec, data) direct line -- see run_m5b.py.
SESSION = [
    # ---- integer variables (direct mode) ----
    ("C", "A%=3.7: PRINT A%", "G", [], ""),
    ("C", "A%=-3.7: PRINT A%", "G", [], ""),
    ("C", "A%=2.5: PRINT A%", "G", [], ""),
    ("C", "A%=-2.5: PRINT A%", "G", [], ""),
    ("C", "A%=32767: PRINT A%", "G", [], ""),
    ("C", "A%=-32767.5: PRINT A%", "G", [], ""),
    ("C", "A%=32767.999: PRINT A%", "G", [], ""),
    ("C", "A%=-32768", "R", IQ_R, ""),
    ("C", "A%=40000", "R", IQ_R, ""),
    ("C", "PRINT (-32768) AND 255", "R", IQ_R, ""),
    ("C", "PRINT INT(-32768)", "G", [], ""),
    ("C", "A%=7: PRINT A%/2; A%*3; A%-10", "G", [], ""),
    ("C", "A%=0.29*100: PRINT A%", "G", [], ""),
    ("C", "A%=1.15*100: PRINT A%", "G", [], ""),
    ("C", "FOR I%=1 TO 3: NEXT", "R",
     (b"?SN ERROR\r\n\r\nREADY.\r\n", [b"SYNTAX ERROR"]), ""),
    # ---- arrays: DIM, elements, subscripts ----
    ("C", "NEW", "G", [], ""),
    ("C", "DIM A(5),B(3,4)", "G", [], ""),
    ("C", "A(3)=7: B(2,3)=9: PRINT A(3)+B(2,3); A(0); B(3,4)",
     "G", [], ""),
    ("C", "FOR I=0 TO 5: A(I)=I*I: NEXT: "
          "PRINT A(0)+A(1)+A(2)+A(3)+A(4)+A(5)", "G", [], ""),
    ("C", "PRINT A(6)", "R", BS_R, ""),
    ("C", "PRINT A(1,2)", "R", BS_R, ""),
    ("C", "DIM A(3)", "R",
     (b"?DD ERROR\r\n\r\nREADY.\r\n", [b"REDIM'D ARRAY"]), ""),
    ("C", "A(3.7)=1: PRINT A(3)", "G", [], ""),
    ("C", "PRINT A(-1)", "R", IQ_R, ""),
    ("C", "PRINT A(40000)", "R", IQ_R, ""),
    ("C", "A(\"X\")=1", "R",
     (b"?TM ERROR\r\n\r\nREADY.\r\n", [b"TYPE MISMATCH"]), ""),
    ("C", "N=3: DIM C(N+2): C(5)=1: PRINT C(5)", "G", [], ""),
    ("C", "DIM W(0): W(0)=5: PRINT W(0)", "G", [], ""),
    ("C", "PRINT W(1)", "R", BS_R, ""),
    # ---- implicit DIM; scalar/array independence ----
    ("C", "NEW", "G", [], ""),
    ("C", "C(7)=3: PRINT C(7); C(10)", "G", [], ""),
    ("C", "PRINT C(11)", "R", BS_R, ""),
    ("C", "F=1: DIM F(3): F(2)=9: PRINT F; F(2)", "G", [], ""),
    ("C", "G(2)=9: G=1: PRINT G; G(2)", "G", [], ""),
    # ---- string and integer arrays ----
    ("C", "NEW", "G", [], ""),
    ("C", "DIM S$(2): S$(1)=\"HI\": S$(2)=S$(1)+\"!\": "
          "PRINT S$(2); S$(0); \"?\"", "G", [], ""),
    ("C", "DIM I%(2): I%(1)=7.6: I%(2)=-7.6: "
          "PRINT I%(1); I%(2)", "G", [], ""),
    ("C", "E%(2)=5: PRINT E%(2)", "G", [], ""),
    ("C", "DIM T$(1,2): T$(1,2)=\"DEEP\": PRINT T$(1,2)",
     "G", [], ""),
    # ---- nested subscripts, READ into elements, 3 dims ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 DIM V(3): V(1)=2: V(2)=3"),
    ("L", "20 DIM W(5): W(2)=40: W(3)=50"),
    ("L", "30 PRINT W(V(1))+W(V(2))"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ M(1),M(2): PRINT M(1)+M(2)"),
    ("L", "20 DATA 3,4"),
    ("C", "RUN", "G", [], ""),
    # The cold DATA scan recognizes DATA only at a line head:
    # a DATA statement behind ':' on the READ's own line is
    # invisible to it and both machines report out-of-data
    # (verified on the golden: V1/V3/V4 probes, m5c-results).
    ("C", "NEW", "G", [], ""),
    ("L", "10 READ M(1),M(2): PRINT M(1)+M(2): DATA 3,4"),
    ("C", "RUN", "R",
     (b"?OD ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"OUT OF DATA", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DIM Z(2,2,2): Z(1,2,1)=8: PRINT Z(1,2,1); Z(2,2,2)"),
    ("C", "RUN", "G", [], ""),
    # ---- DEF FN / FN ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X)=X*X+1"),
    ("L", "20 PRINT FN F(3); FN F(0); FN F(-2)"),
    ("C", "RUN", "G", [], ""),
    ("C", "PRINT FN F(2)", "G", [], ""),
    ("C", "PRINT FN Q(2)", "R",
     (b"?UF ERROR\r\n\r\nREADY.\r\n", [b"UNDEF'D FUNCTION"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 T=5"),
    ("L", "20 DEF FN F(T)=T*2"),
    ("L", "30 PRINT FN F(10); T"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN G(X)=X*10"),
    ("L", "20 DEF FN F(X)=FN G(1)+X"),
    ("L", "30 PRINT FN F(3)"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X)=X*X+1"),
    ("L", "20 PRINT FN F(FN F(1))"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X)=X"),
    ("L", "20 DEF FN F(X)=X+100"),
    ("L", "30 PRINT FN F(1)"),
    ("C", "RUN", "G", [], ""),
    ("C", "DEF FN F(X)=X", "R",
     (b"?ID ERROR\r\n\r\nREADY.\r\n", [b"ILLEGAL DIRECT"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN A$(X$)=X$"),
    ("C", "RUN", "R",
     (b"?TM ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"TYPE MISMATCH", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X$)=1"),
    ("C", "RUN", "R",
     (b"?TM ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"TYPE MISMATCH", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 PRINT FN F(1)"),
    ("L", "20 DEF FN F(X)=X"),
    ("C", "RUN", "R",
     (b"?UF ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"UNDEF'D FUNCTION", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(Z(1))=Z(1)"),
    ("C", "RUN", "R",
     (b"?SN ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"SYNTAX ERROR", b"IN  10"]), ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN AB(X)=X*3"),
    ("L", "20 PRINT FN AB(2)"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X)=X+1: PRINT \"AFTER\""),
    ("L", "20 PRINT FN F(1)"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X)=X+Y"),
    ("L", "20 Y=100: PRINT FN F(1); Y"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DEF FN F(X)=X*2"),
    ("L", "20 CLR"),
    ("L", "30 PRINT FN F(2)"),
    ("C", "RUN", "R",
     (b"?UF ERROR IN  30\r\n\r\nREADY.\r\n",
      [b"UNDEF'D FUNCTION", b"IN  30"]), ""),
    # ---- GC stress: live strings inside arrays ----
    ("C", "NEW", "G", [], ""),
    ("L", "10 DIM S$(4)"),
    ("L", "20 FOR I=0 TO 4: S$(I)=\"S\"+CHR$(48+I): NEXT"),
    ("L", "30 FOR I=1 TO 3000"),
    ("L", "40 T$=\"GARBAGE--\"+CHR$(65+(I AND 7)): U$=T$+T$"),
    ("L", "50 NEXT"),
    ("L", "60 PRINT S$(0);S$(1);S$(2);S$(3);S$(4)"),
    ("C", "RUN", "G", [], ""),
    ("C", "NEW", "G", [], ""),
    ("L", "10 DIM R$(2)"),
    ("L", "20 FOR I=1 TO 3000: R$(1)=\"ELEMENT--\"+"
          "CHR$(65+(I AND 7)): R$(2)=R$(1)+R$(1): NEXT"),
    ("L", "30 PRINT R$(2)"),
    ("C", "RUN", "G", [], ""),
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

    # ---- 68K session ----
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

    # ---- golden session ----
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

    # ---- regressions ----
    for t in ("run_m1.py", "run_m2.py", "run_m3.py", "run_m4.py",
              "run_m5a.py", "run_m5b.py"):
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
