#!/usr/bin/env python3
"""GC-C1 equivalence harness (2026-11-23).

Runs GC-heavy BASIC probes on the OLD (pre-C1) rd image and the
C1 rd image and demands byte-identical transcripts: string
contents, FRE(0) values (which pin the packed string-space
layout exactly), descriptor data pointers read back through
LEEK (the VARPTR-equivalent observation this port has), the
?OM ERROR point on the allocation-shortage path, and the
over-capacity fallback (live set > GCLCAP, where C1 defers to
the original collector).

The one deliberate exception is the TIE probe: two descriptors
sharing one string-space block, arranged by descriptor
surgery (LOKE one descriptor onto another).  PUTSTR's copy
rule keeps pure BASIC from creating such a tie in string
space -- assignment copies string-space data, and a bare
literal assignment only points into the program text -- which
is exactly the study's premise.  The original collector
updates only the last-scanned sharer and re-moves the stale
block (double-packing it), while C1 moves the block once and
updates every sharer (design study
redesign-gc-design-2026-11-23.md SS3-C1).  The tie probe is
therefore asserted against the C1 specification, and the old
build's differing output is reported, not compared.

Usage: run_gc_equiv.py OLD_IMAGE NEW_IMAGE
Exit status 0 = every comparison/assertion holds.
"""
import re
import subprocess
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SIM = Path.home() / "workspace/mc68000-selfhost/sim"
EMU = str(SIM / "emu")
GOLDEN = (ROOT / "golden" / "asciiart-output.txt").read_bytes()

FAILS = []


def run(image, lines, tag, maxcycles=20_000_000_000):
    script = HERE / f"gceq-{tag}.script"
    out = HERE / f"gceq-{tag}.out"
    feed = lines + ["RUN", 'PRINT "ZZX1";"END"']
    script.write_bytes("".join(l + "\r" for l in feed).encode("latin-1"))
    cmd = [EMU, "--image", str(image), "--masters", str(SIM / "masters"),
           "--script", str(script), "--out", str(out),
           "--until", "ZZX1END", "--settle", "2000000",
           "--maxcycles", str(maxcycles)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    m = re.search(r"after (\d+) cycles", r.stdout)
    cycles = int(m.group(1)) if m else -1
    if r.returncode != 0:
        FAILS.append(f"{tag}: emu rc={r.returncode} ({r.stdout.strip()})")
    return out.read_bytes(), cycles


def compare(name, old_tx, new_tx):
    ok = old_tx == new_tx
    print(("PASS " if ok else "FAIL ") + name +
          ("" if ok else f" (old {len(old_tx)} B, new {len(new_tx)} B)"))
    if not ok:
        for i, (a, b) in enumerate(zip(old_tx, new_tx)):
            if a != b:
                print(f"   first diff at byte {i}: "
                      f"old ...{old_tx[max(0, i-40):i+40]!r}")
                print(f"                      "
                      f"new ...{new_tx[max(0, i-40):i+40]!r}")
                break
        FAILS.append(name)


PROBES = {}

PROBES["churn_array"] = [
    '5 AT=0: HD=0',
    '10 DIM S$(260)',
    '20 FOR I=0 TO 260: S$(I)="ITEM"+STR$(I)+"-"+LEFT$("XXXXXXXXXXXXXXXXXXXXXXX",1+I MOD 23): NEXT',
    '30 FOR R=1 TO 12',
    '40 FOR I=0 TO 260 STEP 3',
    '50 T$=S$(I): S$(I)=T$+MID$(T$,2,3)+"<"+STR$(R)+">"',
    '60 NEXT I',
    '70 F=FRE(0): C=0: FOR I=0 TO 260: C=C+LEN(S$(I))+ASC(S$(I)): NEXT',
    '80 PRINT R,F,C',
    '90 PRINT S$(0): PRINT S$(129): PRINT S$(260)',
    '100 NEXT R',
    '110 AT=LEEK(186): HD=PEEK(AT-65536+6)*2+8',
    '120 PRINT "PTRS",LEEK(AT-65536+HD),LEEK(AT-65536+HD+774),LEEK(AT-65536+HD+1560)',
]

PROBES["churn_scalar"] = [
    '10 A$="ALPHA": B$="BETA": C$="GAMMA": D$="DELTA"',
    '20 FOR R=1 TO 40',
    '30 A$=B$+C$+LEFT$(A$,5): B$=MID$(A$,3,4)+D$: C$=A$+B$: D$=LEFT$(C$,R MOD 7+1)',
    '40 IF R MOD 8=0 THEN PRINT R,FRE(0),A$,B$',
    '50 NEXT R',
    '60 PRINT A$: PRINT B$: PRINT C$: PRINT D$: PRINT FRE(0)',
    '70 VT=LEEK(182): AR=LEEK(186)',
    '80 FOR P=VT TO AR-8 STEP 8',
    '90 IF PEEK(P-65536)=65 AND PEEK(P-65536+1)=128 THEN PRINT "ADSC",LEEK(P-65536+2),PEEK(P-65536+6)',
    '100 NEXT P',
]

PROBES["fre_discipline"] = [
    '5 AT=0: HD=0',
    '10 DIM N$(600)',
    '20 FOR I=1 TO 600',
    '30 N$(I)=LEFT$("ABCDEFGH",I MOD 8)+STR$(I)',
    '40 IF I MOD 16=0 THEN G=FRE(0): PRINT I,G',
    '50 NEXT I',
    '60 C=0: FOR I=1 TO 600: C=C+LEN(N$(I)): NEXT: PRINT "TOT",C,FRE(0)',
    '70 AT=LEEK(186): HD=PEEK(AT-65536+6)*2+8',
    '80 PRINT "PTRS",LEEK(AT-65536+HD),LEEK(AT-65536+HD+3594)',
]

PROBES["oom"] = [
    '5 BIG$="": FOR J=1 TO 25: BIG$=BIG$+"0123456789": NEXT',
    '10 DIM B$(700)',
    '20 FOR I=0 TO 700',
    '30 B$(I)=BIG$',
    '40 IF I MOD 25=0 THEN PRINT I,FRE(0)',
    '50 NEXT I',
    '60 PRINT "NO OOM",FRE(0)',
]

PROBES["fallback_over"] = [
    '10 DIM W$(2000)',
    '20 FOR I=0 TO 2000: W$(I)="W"+STR$(I): NEXT',
    '30 PRINT "F1",FRE(0)',
    '40 C=0: FOR I=0 TO 2000: C=C+LEN(W$(I)): NEXT: PRINT "TOT",C',
    '50 FOR I=0 TO 2000 STEP 7: W$(I)=W$(I)+"!": NEXT',
    '60 PRINT "F2",FRE(0),W$(0),W$(1995)',
]

PROBES["nearcap_under"] = [
    '10 DIM U$(1700)',
    '20 FOR I=0 TO 1700: U$(I)="U"+STR$(I): NEXT',
    '30 PRINT "F1",FRE(0)',
    '40 FOR R=1 TO 3: FOR I=0 TO 1700 STEP 5: U$(I)=U$(I)+".": NEXT: PRINT R,FRE(0): NEXT',
    '50 C=0: FOR I=0 TO 1700: C=C+LEN(U$(I)): NEXT: PRINT "TOT",C',
]

# A genuine string-space tie DOES need surgery in this port:
# assignment copies string-space data (PUTSTR's rule), and a
# bare literal assignment only points into the program text
# (below STREND, invisible to the collector).  So: build two
# independent string-space blocks with LEFT$, then LOKE the
# second descriptor onto the first.  The sacrificial X$ block
# sits ABOVE the shared block and dies before the collection,
# so the shared block is not flush at the top when collected
# -- otherwise the stale descriptor's pointer equals the new
# FRETOP and even the original collector treats it as moved.
TIE = [
    '5 AT=0: HD=0: D0=0: D1=0: F=0',
    '10 DIM T$(2)',
    '15 X$=LEFT$("QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ",36)',
    '20 T$(0)=LEFT$("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",36)',
    '30 T$(1)=LEFT$("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",36)',
    '40 T$(2)=LEFT$("ZZZZZZZZZZZZZZZZZZZZZZ",22)',
    '45 X$=""',
    '50 AT=LEEK(186): HD=PEEK(AT-65536+6)*2+8: D0=AT-65536+HD: D1=D0+6',
    '60 PRINT "PRE",LEEK(D0),LEEK(D1)',
    '70 LOKE D1,LEEK(D0): POKE D1+4,PEEK(D0+4)',
    '75 PRINT "TIED",LEEK(D0),LEEK(D1)',
    '80 F=FRE(0)',
    '90 PRINT "T0:",T$(0): PRINT "T1:",T$(1): PRINT "T2:",T$(2)',
    '100 PRINT "DESC",LEEK(D0),LEEK(D1)',
    '110 PRINT "FRE",F',
]
CONTROL = [l for l in TIE if not l.startswith("70 ")]


def numbers(tx, marker):
    m = re.search(rb"\r\n" + marker + rb" +(-?\d+)", tx)
    return int(m.group(1)) if m else None


def main():
    old_img, new_img = sys.argv[1], sys.argv[2]
    for name, prog in PROBES.items():
        o, oc = run(old_img, prog, f"old-{name}")
        n, nc = run(new_img, prog, f"new-{name}")
        compare(f"probe {name} (old {oc} cyc, new {nc} cyc)", o, n)

    # ASCIIART on the rd image: golden bytes + cycle record.
    bas = [ln for ln in (ROOT / "research" / "mez6502" /
             "ASCIIART.BAS").read_text().splitlines() if ln.strip()]
    for tag, img in (("old", old_img), ("new", new_img)):
        tx, cyc = run(img, bas, f"art-{tag}", maxcycles=5_000_000_000)
        i = tx.find(b"RUN\r\n")
        pic = tx[i + 5: i + 5 + len(GOLDEN)] if i >= 0 else b""
        ok = pic == GOLDEN
        print(("PASS " if ok else "FAIL ") +
              f"ASCIIART {tag}: picture == golden, {cyc} cycles, "
              f"crc32={zlib.crc32(pic) & 0xFFFFFFFF:08X}")
        if not ok:
            FAILS.append(f"asciiart {tag}")

    # Tie probe: the control (no sharing) must be byte-identical
    # across builds.  On the tie itself the builds are EXPECTED
    # to differ, in exactly the sanctioned way: same program, so
    # FRE(new) - FRE(old) = +36 (the old collector packs the
    # shared block twice, C1 once), the new build's descriptors
    # end united, and both builds keep the contents intact.
    otx, _ = run(old_img, TIE, "old-tie")
    ntx, _ = run(new_img, TIE, "new-tie")
    ctx, _ = run(new_img, CONTROL, "new-control")
    otxc, _ = run(old_img, CONTROL, "old-control")
    compare("tie control (old vs new)", otxc, ctx)
    ok = True
    for lbl, tx in (("old", otx), ("new", ntx)):
        pm = re.search(rb"PRE +(-?\d+) +(-?\d+)", tx)
        if not (pm and pm.group(1) != pm.group(2) and
                int(pm.group(1)) > 200000 and
                int(pm.group(2)) > 200000):
            ok = False
            print(f"FAIL tie PRE not two string-space blocks "
                  f"({lbl}): {pm and pm.groups()}")
        tm = re.search(rb"TIED +(-?\d+) +(-?\d+)", tx)
        if not (tm and tm.group(1) == tm.group(2)):
            ok = False
            print(f"FAIL tie surgery did not unite ({lbl}): "
                  f"{tm and tm.groups()}")
    t0 = re.search(rb"T0: +([^\r]*)\r\n", ntx)
    t1 = re.search(rb"T1: +([^\r]*)\r\n", ntx)
    want = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    if not (t0 and t1 and t0.group(1) == want and t1.group(1) == want):
        ok = False
        print(f"FAIL tie contents (new): T0={t0 and t0.group(1)}, "
              f"T1={t1 and t1.group(1)}")
    dm = re.search(rb"DESC +(-?\d+) +(-?\d+)", ntx)
    if not (dm and dm.group(1) == dm.group(2)):
        ok = False
        print(f"FAIL tie descriptors not united (new): "
              f"{dm and dm.groups()}")
    fre_new = numbers(ntx, rb"FRE")
    fre_old = numbers(otx, rb"FRE")
    if fre_new is None or fre_old is None or fre_new - fre_old != 36:
        ok = False
        print(f"FAIL tie FRE delta new-old: {fre_new}-{fre_old} "
              f"(want 36: old packs the shared block twice)")
    print(("PASS " if ok else "FAIL ") +
          "tie probe (C1 spec: block moved once, both descriptors "
          "updated, FRE counts the shared block once)")
    if not ok:
        FAILS.append("tie probe")
    print("   old build on the tie probe (sanctioned deviation, "
          "reported):")
    for ln in otx.decode("latin-1").split("\r\n"):
        if ln.startswith(("PRE", "TIED", "T0:", "T1:", "T2:",
                          "DESC", "FRE")):
            print("     " + ln)

    print()
    if FAILS:
        print("EQUIV: FAIL -- " + "; ".join(FAILS))
        return 1
    print("EQUIV: ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
