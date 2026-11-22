#!/usr/bin/env python3
"""M5g verification: the CTRL-C break (BRKCHK / BRKGO) and the
1-byte console pushback, for the MS-BASIC 68K port.

Background: ISCNTC existed since M1 but was never called, so a
running program could not be interrupted (found on the real
board in Phase 1.5 Step 3).  The fix wires a check to the
heads of FETCH and EXEC -- the port's counterparts of the
original's NEWSTT head, where NEWSTT does JSR ISCNTC -- and
gives the machine layer a pushback slot so the check never
eats type-ahead: it examines only the head of the input
stream; $03 breaks (STOPC semantics), anything else is pushed
back for the next MONRDKEY / MONPOLKEY consumer.

The golden harness cannot check the break itself (its ISCNTC
hook always reports "not pressed"), so these checks are
68K-only, byte-exact against the BREAK format that run_m5b.py
verified against the golden for the STOP statement
("BREAK IN  n" with the INPRT suffix, bare "BREAK" in direct
mode).

Sessions (one preloaded FIFO, like every suite here; "typed
during the run" is modelled by byte order in the stream):
  A. A GOTO loop (10 GET A$ / 20 GOTO 10) with "Z" queued
     ahead of $03: 'Z' is pushed back at the direct-line
     boundary and drained by the first GET, then $03 breaks
     the loop: BREAK IN  10 and READY.  (A bare 10 GOTO 10
     cannot be modelled in a preloaded FIFO: a $03 queued
     directly behind RUN is seen at the RUN line's own
     direct-mode boundary first -- faithfully, per the
     original -- which is what session D pins down.)
  B. A sacrificial byte 'Z' is queued ahead of $03: the
     boundary check pushes 'Z' back, GET (statement 1)
     receives it via MONPOLKEY, the $03 then breaks at line
     10's terminator, and CONT resumes and finishes the
     program (FOR 1..100, PRINT I= 101); A$ still holds "Z".
  C. Type-ahead "HELLO\r" queued before RUN of a FOR loop
     followed by INPUT A$: the head byte is pushed back at
     the first boundary, the rest streams untouched, and
     INPUT receives the whole line.
  D. A $03 queued behind a direct statement: bare "BREAK",
     no save, no IN-line suffix (the original's DIRIS path).

Regressions: run_m5d.py (which itself cascades run_m1.py ..
run_m5c.py as exit-0 subprocesses) and run_hw.py (both emu
flavours internally).  run_m5d.py exits 1 by design -- its
two known 1-ulp display differences (2^31 and
COS(3.14159265), see m5d-results.md) count as failed checks
-- so it is gated by parsing: the summary must read 116/118
and every FAIL line must be one of those two known cases.
This script honours MSB_EMU like the other suites, so the
whole gate runs under emu_strict when the caller sets it.
Exit status 0 = PASS.
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
LST = HERE / "msbasic68k.lst"
SCRIPT = HERE / "m5g.script"
OUT = HERE / "m5g.out"

ENDMARK = 'PRINT "ZZM5";"END"'  # split so the echo alone
                                # cannot trip the emu's --until

# Entries: ("L", text, "", None)                 stored line
#          ("C", text, data, expected-or-None)   direct line;
#          data = extra bytes fed right after text+"\r";
#          expected = the exact response region (str) or
#          None to only require that a region was found.
SESSION = [
    # ---- A: GOTO loop break ----
    ("C", "NEW", "", None),
    ("L", "10 GET A$", "", None),
    ("L", "20 GOTO 10", "", None),
    ("C", "RUN", "Z\x03", "\r\nBREAK IN  10\r\nREADY.\r\n"),
    # ---- B: pushback -> GET, break, CONT resumes ----
    ("C", "NEW", "", None),
    ("L", "10 GET A$", "", None),
    ("L", "20 FOR I=1 TO 100", "", None),
    ("L", "30 NEXT I", "", None),
    ("L", '40 PRINT "I=";I', "", None),
    ("C", "RUN", "Z\x03", "\r\nBREAK IN  10\r\nREADY.\r\n"),
    ("C", "CONT", "", "I= 101 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT A$", "", "Z\r\n\r\nREADY.\r\n"),
    # ---- C: type-ahead survives into INPUT ----
    ("C", "NEW", "", None),
    ("L", "10 FOR I=1 TO 50", "", None),
    ("L", "20 NEXT I", "", None),
    ("L", "30 INPUT A$", "", None),
    ("L", '40 PRINT "GOT:";A$', "", None),
    ("C", "RUN", "HELLO\r", "? HELLO\r\nGOT:HELLO\r\n\r\nREADY.\r\n"),
    # ---- D: direct-mode break is a bare BREAK ----
    ("C", 'PRINT "X"', "\x03", "\r\nBREAK\r\nREADY.\r\n"),
]


def fed_bytes(entry):
    if entry[0] == "L":
        return entry[1] + "\r"
    return entry[1] + "\r" + entry[2]


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
    next "READY.\r\n" (None for stored lines / not found).
    Same convention as run_m5b.py."""
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
    all_entries = SESSION + [("C", ENDMARK, "", None)]
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
    got = regions68(tx, all_entries)
    check("endmark region", got[-1] == "ZZM5END\r\n\r\nREADY.\r\n",
          f"got {got[-1]!r}")

    for idx, e in enumerate(all_entries):
        if e[0] == "L":
            continue
        expected = e[3]
        k = got[idx]
        if expected is None:
            check(f"[{e[1]}] region extracted", k is not None,
                  f"got {k!r}")
        else:
            check(f"[{e[1]}] region", k == expected,
                  f"got {k!r} want {expected!r}")

    # ---- regressions (run_m5d cascades m1..m5c) ----
    # run_m5d.py exits 1 by design (its two known 1-ulp
    # display differences count as failed checks), so gate
    # it by parsing: 116/118 summary and no FAIL line other
    # than the two known cases.
    r = subprocess.run([sys.executable, str(HERE / "run_m5d.py")],
                       capture_output=True, text=True,
                       timeout=1800)
    out = r.stdout + r.stderr
    fails = [l for l in out.splitlines() if l.startswith("FAIL")]
    known = ("PRINT 10^38; 2^31", "COS(3.14159265)")
    unknown = [l for l in fails
               if not any(k in l for k in known)]
    check("regression run_m5d.py (only the 2 known 1-ulp diffs)",
          "116/118 checks PASS" in out and len(fails) == 2
          and not unknown,
          "; ".join(unknown[:4]) if unknown
          else f"{len(fails)} known FAILs, summary "
               f"{'116/118' if '116/118 checks PASS' in out else '??'}")

    r = subprocess.run([sys.executable, str(HERE / "run_hw.py")],
                       capture_output=True, text=True,
                       timeout=1800)
    tail = [l for l in (r.stdout + r.stderr).splitlines()
            if "FAIL" in l]
    check("regression run_hw.py", r.returncode == 0,
          "; ".join(tail[:4]) if tail else "exit 0")

    n_fail = sum(1 for _, ok in checks if not ok)
    print(f"\n{len(checks) - n_fail}/{len(checks)} checks PASS")
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
