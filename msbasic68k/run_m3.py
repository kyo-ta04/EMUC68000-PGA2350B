#!/usr/bin/env python3
"""M3 verification for the MS-BASIC 68K port.

Every test input line is run BOTH on the 68K port (Musashi sim)
and on the golden: CBM BASIC 2 (mist64 orig/cbmbasic2.bin) under
py65, via ../run_cbmbasic2.py imported as a module.  For each
checked line, the response payload (the bytes printed in answer
to that line, excluding the input echo, the terminating CRLF and
the READY. prompt) must match byte for byte.

One known, deliberate difference is reported separately rather
than hidden: after a numeric PRINT item, CBM BASIC 2 on its
screen device emits $1D (cursor right) as the trailing space,
where this port (like the generic v1.1 target) emits $20.
Those bytes are normalized for the comparison and counted as
the "OUTSP $1D vs $20" item (要判断-1 in m3-results.md); every
other byte must match exactly.

Checks: the M3 exit expressions, variable assignment, FOR/NEXT
(sum 55, 2-level nesting, STEP 0.5), plus extra FOUT/FIN probes.
M1/M2 regressions are run as subprocesses and must PASS.
Exit status 0 = all PASS.
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
SCRIPT = HERE / "m3.script"
OUT = HERE / "m3.out"

# (line, check?) -- the full session, fed identically to both sides.
SESSION = [
    ('PRINT 1/3', True),
    ('PRINT 2+3*4', True),
    ('PRINT (2+3)*4', True),
    ('PRINT 10/4', True),
    ('PRINT -7/2', True),
    ('PRINT 1.5*1.5', True),
    ('PRINT INT(3.7)', True),
    ('PRINT INT(-3.7)', True),
    ('PRINT ABS(-5)', True),
    ('PRINT SGN(-2)', True),
    ('PRINT SGN(0)', True),
    ('PRINT -5', True),
    ('PRINT -5*-3', True),
    ('PRINT 1000000', True),
    ('PRINT 0.00001', True),
    ('PRINT 123456789', True),
    ('PRINT 1E10', True),
    ('PRINT 2.5E-3', True),
    ('PRINT 0', True),
    ('PRINT -0.5', True),
    ('PRINT 0.05', True),
    ('PRINT 3>2', True),
    ('PRINT 2=2', True),
    ('PRINT 1<0', True),
    ('A=123', False),
    ('PRINT A', True),
    ('A=A+1', False),
    ('PRINT A', True),
    ('NEW', False),
    ('10 FOR I=1 TO 10: S=S+I: NEXT I: PRINT S', False),
    ('RUN', True),
    ('NEW', False),
    ('10 FOR Y=1 TO 3: FOR X=1 TO 3: C=C+1: NEXT X: NEXT Y: PRINT C', False),
    ('RUN', True),
    ('NEW', False),
    ('10 FOR I=0 TO 1 STEP 0.5: T=T+I: NEXT: PRINT T', False),
    ('RUN', True),
    ('PRINT "ZZM3END"', True),
]
LINES = [ln for ln, _ in SESSION]


def extract_payloads_68k(tx: str):
    """Split the 68K transcript into per-line response payloads."""
    payloads = []
    pos = 0
    for ln in LINES:
        echo = ln + "\r\n"
        i = tx.find(echo, pos)
        if i < 0:
            payloads.append(None)
            continue
        start = i + len(echo)
        if ln[0].isdigit():
            # M8: storing a numbered line prints NOTHING (no
            # READY.) -- the next bytes are the next line's
            # echo.  (Through M7 the port reprinted READY.
            # after every stored line.)
            payloads.append("")
            pos = start
            continue
        rest = tx[start:]
        if rest.startswith("\r\nREADY.\r\n"):
            payloads.append("")
            pos = start + len("\r\nREADY.\r\n")
            continue
        j = rest.find("\r\n\r\nREADY.\r\n")
        if j < 0:
            payloads.append(None)
            pos = start
            continue
        payloads.append(rest[:j])
        pos = start + j + len("\r\n\r\nREADY.\r\n")
    return payloads


def extract_payload(seg: bytes) -> bytes:
    """CBM segment (after previous READY.) -> response payload."""
    if seg.startswith(b"\r\n"):
        seg = seg[2:]
    if seg.startswith(b"\r\nREADY.\r\n"):
        return b""
    j = seg.find(b"\r\n\r\nREADY.\r\n")
    if j < 0:
        return None
    return seg[:j]


def run_golden():
    sys.path.insert(0, str(ROOT))
    import run_cbmbasic2 as g

    payloads = []
    n = g.run_until(lambda: g.ready_count() >= 1, 5_000_000, "cold")
    if g.ready_count() < 1:
        raise RuntimeError("golden: no initial READY")
    mark = len(g.out)
    rc = 1
    for ln in LINES:
        g.feed(ln + "\r")
        if ln[0].isdigit():
            # Storing a program line prints NO "READY." on CBM
            # BASIC 2 -- the whole response is the CRLF for the
            # entered line.  (Gating on ready_count here was the
            # original bug: the count never advances for a stored
            # line, so every later line was misreported as None.)
            # Wait for those 2 bytes, then confirm the output has
            # settled with one more chunk.
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
        else:
            rc += 1
            g.run_until(lambda rc=rc: g.ready_count() >= rc, 20_000_000, ln)
            if g.ready_count() < rc:
                payloads.append(None)
                mark = len(g.out)
                continue
        seg = bytes(g.out[mark:])
        payloads.append(extract_payload(seg))
        mark = len(g.out)
    return payloads


def main() -> int:
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name, detail)

    # ---- assemble + run the 68K side ----
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
           "--until", "ZZM3END",
           "--maxcycles", "300000000"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    print("emu:", r.stdout.strip(), f"(rc={r.returncode})")
    check("emu exit code 0 (until-string seen)", r.returncode == 0)
    tx = OUT.read_bytes().decode("latin-1")
    got68 = extract_payloads_68k(tx)

    # ---- golden side ----
    golden = run_golden()

    # ---- compare ----
    outsp_diffs = 0
    for idx, (ln, wanted) in enumerate(SESSION):
        if not wanted:
            continue
        g = golden[idx]
        k = got68[idx]
        if g is None or k is None:
            check(f"[{ln}] payload extracted", False,
                  f"golden={g!r} 68k={k!r}")
            continue
        kb = k.encode("latin-1")
        n1d = g.count(b"\x1d")
        outsp_diffs += n1d
        gnorm = g.replace(b"\x1d", b"\x20")
        check(f"[{ln}]", gnorm == kb,
              f"golden={gnorm!r} 68k={kb!r}" if gnorm != kb else
              f"= {kb!r}")
    print(f"note: OUTSP $1D (CBM) vs $20 (68K) bytes normalized: "
          f"{outsp_diffs} (要判断-1)")

    # ---- regressions ----
    for name in ("run_m1.py", "run_m2.py"):
        r = subprocess.run([sys.executable, str(HERE / name)],
                           capture_output=True, text=True, timeout=600)
        tail = (r.stdout + r.stderr).strip().splitlines()
        check(f"regression {name}", r.returncode == 0,
              tail[-2] if len(tail) >= 2 else "")

    ok = all(v for _, v in checks)
    print("M3:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
