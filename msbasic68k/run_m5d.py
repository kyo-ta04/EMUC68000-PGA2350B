#!/usr/bin/env python3
"""M5d verification for the MS-BASIC 68K port -- the final
faithful-port milestone.

Scope under test (see m5d-results.md):
  - FPWRT (^): representative values, negative bases with
    integer / non-integer exponents, 0^0, 0^negative (the
    original returns 0), overflow, and ^ chaining / unary
    minus precedence (whatever the golden does).
  - The math functions SQR, LOG, EXP, SIN, COS, TAN, ATN:
    value batteries (0, positive, negative, large arguments)
    byte-compared against the golden -- the port uses the
    original's algorithms and constants, so PRINT output
    must match digit for digit.  Domain errors are the
    original's (?IQ for LOG/SQR of negatives, ?OV for EXP).
  - RND: the boot sequence, RND(0), and negative-argument
    reseeds are deterministic in BOTH harnesses (the golden's
    entropy cells read as zero in py65, and the port has no
    timer), so the whole series is byte-compared.
  - String functions STR$, VAL, ASC, LEN, LEFT$, RIGHT$,
    MID$: representative and boundary cases (empty strings,
    zero counts, out-of-range starts), plus the original's
    errors (?IQ, ?TM).
  - PEEK/POKE/WAIT on the port's logical 64KB page
    (physical = ZPBASE + logical): round trips in the free
    page area and at logical 0, address-range errors, and
    WAIT returning at once when its condition already holds
    (mask and mask+xor forms).
  - POS: 0 at line start on both machines; after output the
    golden harness still reports 0 (its KERNAL stub keeps no
    column), so that case is an R check against the port's
    spec value 3.

Comparison model and conventions are exactly run_m5b.py's:
regions are byte-compared after the $1D -> $20 (NUMSPC)
normalization; "R" entries check the port region byte-exactly
and the golden region by substrings (long-form error texts).

Regressions run_m1.py .. run_m5c.py run as subprocesses at
the end and must exit 0.  Exit status 0 = all PASS.
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
SCRIPT = HERE / "m5d.script"
OUT = HERE / "m5d.out"

ENDMARK = 'PRINT "ZZM5";"END"'  # split so the echo alone
                                # cannot trip the emu's --until

IQ_R = (b"?IQ ERROR\r\n\r\nREADY.\r\n", [b"ILLEGAL QUANTITY"])
TM_R = (b"?TM ERROR\r\n\r\nREADY.\r\n", [b"TYPE MISMATCH"])
OV_R = (b"?OV ERROR\r\n\r\nREADY.\r\n", [b"OVERFLOW"])

# Session entries: ("L", text) stored program line;
# ("C", text, mode, spec, data) direct line -- see run_m5b.py.
SESSION = [
    # ---- RND first: the sequence is stateful from boot ----
    ("C", "PRINT RND(1); RND(1); RND(1)", "G", [], ""),
    ("C", "PRINT RND(0); RND(1)", "G", [], ""),
    ("C", "PRINT RND(-1); RND(1); RND(1)", "G", [], ""),
    ("C", "PRINT RND(-3.5); RND(1)", "G", [], ""),
    ("C", "PRINT RND(-1)", "G", [], ""),
    ("C", "PRINT RND(0.5); RND(2); RND(100)", "G", [], ""),
    ("C", 'PRINT RND("A")', "R", TM_R, ""),
    # ---- ^ (FPWRT) ----
    ("C", "PRINT 2^10; 2^0.5; 2^-2; 10^2; 5^1", "G", [], ""),
    ("C", "PRINT (-2)^3; (-2)^2; (-2)^-3; (-2)^0", "G", [], ""),
    ("C", "PRINT 0^0; 0^5; 0^-1; 1.5^2.5; 0.5^-0.5", "G", [], ""),
    ("C", "PRINT 2^3^2; -2^2; 4^0.5; 9^(1/2)", "G", [], ""),
    ("C", "PRINT 10^38; 2^31", "G", [], ""),
    ("C", "PRINT (-2)^0.5", "R", IQ_R, ""),
    ("C", "PRINT (-2)^2.5", "R", IQ_R, ""),
    ("C", "PRINT 10^39", "R", OV_R, ""),
    # ---- SQR / LOG / EXP ----
    ("C", "PRINT SQR(2); SQR(0); SQR(0.25); SQR(100)", "G", [], ""),
    ("C", "PRINT SQR(3); SQR(12345); SQR(1E-10)", "G", [], ""),
    ("C", "PRINT LOG(1); LOG(10); LOG(2.71828183); LOG(0.5)", "G", [], ""),
    ("C", "PRINT LOG(1000000); LOG(0.001); LOG(1E-30)", "G", [], ""),
    ("C", "PRINT EXP(0); EXP(1); EXP(-1); EXP(10); EXP(-10)", "G", [], ""),
    ("C", "PRINT EXP(50); EXP(-50); EXP(80); EXP(-80)", "G", [], ""),
    ("C", "PRINT EXP(LOG(5)); LOG(EXP(2))", "G", [], ""),
    ("C", "PRINT LOG(0)", "R", IQ_R, ""),
    ("C", "PRINT LOG(-1)", "R", IQ_R, ""),
    ("C", "PRINT SQR(-1)", "R", IQ_R, ""),
    ("C", "PRINT EXP(100)", "R", OV_R, ""),
    ("C", 'PRINT LOG("A")', "R", TM_R, ""),
    # ---- SIN / COS / TAN / ATN ----
    ("C", "PRINT SIN(0); COS(0); TAN(0); ATN(0)", "G", [], ""),
    ("C", "PRINT SIN(1); COS(1); TAN(1); ATN(1)", "G", [], ""),
    ("C", "PRINT SIN(-1); COS(-1); TAN(-1); ATN(-1)", "G", [], ""),
    ("C", "PRINT SIN(3.14159265); COS(3.14159265); ATN(100); ATN(0.5)",
     "G", [], ""),
    ("C", "PRINT SIN(100); COS(100); TAN(100)", "G", [], ""),
    ("C", "PRINT SIN(-100); COS(1000); TAN(-1000)", "G", [], ""),
    ("C", "PRINT SIN(123456); COS(-98765)", "G", [], ""),
    ("C", "PRINT ATN(1E10); ATN(-1E10); ATN(0.001)", "G", [], ""),
    ("C", "PRINT SIN(0.7)^2+COS(0.7)^2", "G", [], ""),
    ("C", 'PRINT SIN("A")', "R", TM_R, ""),
    # ---- POS ----
    ("C", "PRINT POS(0)", "G", [], ""),
    ("C", 'PRINT "ABC"; POS(0)', "R",
     (b"ABC 3 \r\n\r\nREADY.\r\n", [b"ABC 0"]), ""),
    # ---- string functions ----
    ("C", 'PRINT LEN("HELLO"); LEN(""); LEN("A")', "G", [], ""),
    ("C", 'PRINT ASC("A"); ASC("HELLO"); ASC(CHR$(200))', "G", [], ""),
    ("C", 'PRINT VAL("123"); VAL("-3.5"); VAL("12AB"); VAL("")',
     "G", [], ""),
    ("C", 'PRINT VAL(" 42"); VAL(".5"); VAL("1E2"); VAL("ABC")',
     "G", [], ""),
    ("C", 'PRINT VAL("1.5E-2"); VAL("-0"); VAL("."); VAL("+.25X")',
     "G", [], ""),
    ("C", 'A$=STR$(5): PRINT LEN(A$); A$;"!"', "G", [], ""),
    ("C", "PRINT STR$(-5); STR$(0); STR$(1/3); STR$(123456789)",
     "G", [], ""),
    ("C", "PRINT STR$(1E20); STR$(-0.001)", "G", [], ""),
    ("C", 'PRINT LEFT$("HELLO",2); RIGHT$("HELLO",2); MID$("HELLO",2,3)',
     "G", [], ""),
    ("C", 'PRINT LEFT$("HELLO",10); RIGHT$("HELLO",10); MID$("HELLO",4,10)',
     "G", [], ""),
    ("C", 'PRINT LEFT$("HELLO",0); RIGHT$("HELLO",0); MID$("HELLO",2,0)',
     "G", [], ""),
    ("C", 'PRINT MID$("HELLO",6,2); MID$("HELLO",5,1); MID$("HELLO",3)',
     "G", [], ""),
    ("C", 'PRINT MID$("HELLO",1); RIGHT$("",3); LEN(RIGHT$("",3))',
     "G", [], ""),
    ("C", 'A$="COMPUTER": PRINT LEFT$(A$,3); MID$(A$,4,3); RIGHT$(A$,3)',
     "G", [], ""),
    ("C", 'PRINT LEFT$("HELLO",2)+"X"+RIGHT$("WORLD",3)', "G", [], ""),
    ("C", 'A$="XYZ": B$=LEFT$(A$,2): A$="W": PRINT B$; LEFT$(A$,1)',
     "G", [], ""),
    ("C", 'PRINT ASC("")', "R", IQ_R, ""),
    ("C", 'PRINT MID$("HELLO",0)', "R", IQ_R, ""),
    ("C", 'PRINT LEFT$("HELLO",-1)', "R", IQ_R, ""),
    ("C", 'PRINT LEFT$("HELLO",256)', "R", IQ_R, ""),
    ("C", "PRINT LEN(5)", "R", TM_R, ""),
    ("C", "PRINT VAL(5)", "R", TM_R, ""),
    ("C", "PRINT ASC(5)", "R", TM_R, ""),
    ("C", "PRINT LEFT$(5,1)", "R", TM_R, ""),
    ("C", 'PRINT MID$("HELLO","X")', "R", TM_R, ""),
    ("C", "PRINT CHR$(-0.5)", "R", IQ_R, ""),
    ("C", 'PRINT CHR$("A")', "R", TM_R, ""),
    # ---- PEEK / POKE / WAIT (logical page) ----
    ("C", "POKE 36864,65: POKE 36865,66: PRINT PEEK(36864); PEEK(36865)",
     "G", [], ""),
    ("C", "POKE 36864,255: PRINT PEEK(36864)", "G", [], ""),
    ("C", "POKE 0,123: PRINT PEEK(0)", "G", [], ""),
    ("C", "PRINT PEEK(65535)", "G", [], ""),
    ("C", "POKE 36864,5: WAIT 36864,1: PRINT \"W1\"", "G", [], ""),
    ("C", "WAIT 36864,4,1: PRINT \"W2\"", "G", [], ""),
    ("C", "POKE 36864,0: WAIT 36864,1,1: PRINT \"W3\"", "G", [], ""),
    ("C", "POKE 65536,1", "R", IQ_R, ""),
    ("C", "POKE -1,1", "R", IQ_R, ""),
    ("C", "PRINT PEEK(65536)", "R", IQ_R, ""),
    ("C", "PRINT PEEK(-1)", "R", IQ_R, ""),
    # ---- stored program: functions in program context ----
    ("L", "10 A=0: FOR I=1 TO 5: A=A+SIN(I): NEXT: PRINT A"),
    ("L", "20 PRINT LEFT$(\"PROGRAM\",4); MID$(\"PROGRAM\",5,3); VAL(\"42\")"),
    ("L", "30 POKE 36864,77: PRINT PEEK(36864)"),
    ("L", "40 WAIT 36864,1: PRINT \"DONE\""),
    ("C", "RUN", "G", [], ""),
    ("L", "10 PRINT LOG(-1)"),
    ("C", "RUN", "R",
     (b"?IQ ERROR IN  10\r\n\r\nREADY.\r\n",
      [b"ILLEGAL QUANTITY", b"IN  10"]), ""),
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
              "run_m5a.py", "run_m5b.py", "run_m5c.py"):
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
