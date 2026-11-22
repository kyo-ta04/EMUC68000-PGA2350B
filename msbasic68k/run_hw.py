#!/usr/bin/env python3
"""Hardware-map variant verification (Phase 1.5 Step 2).

Builds msbasic68k-hw.bin via build_hw.py (landing zone $30000,
entered by CALL on the real board), then verifies it in the sim:
the emu boots from the vectors at $0, so a composite image is
used -- vector stub at $0 (SSP=$40000, PC=$30000) with the HW
binary placed at $30000, exactly where CALL $30000 would find it
on the real board.

Checks, under BOTH the normal emu and emu_strict (address-error
emulation; the layout change must not reintroduce odd accesses):
  - banner, "40960 BYTES FREE", READY
  - PRINT arithmetic (2+3*4, 1/3)
  - string variables + concatenation
  - GOSUB/RETURN in a small program
  - GC stress (2000 iterations, ~280KB of garbage against a
    ~40KB string space: survival proves GARBAG works here)
  - accumulation A$=A$+"AB" x 50
  - ASCIIART.BAS: picture byte-identical to the CBM golden
    (sum16 25584, CRC32 0D6D8795), READY afterwards
Plus the branch-target checkers against the HW listing (indexed
into the composite image, whose base is $0).

Exit status 0 = all PASS.
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
EMU = str(SIM / "emu")
EMU_STRICT = str(SIM / "emu_strict")

HW_BIN = HERE / "msbasic68k-hw.bin"
HW_LST = HERE / "msbasic68k-hw.lst"
COMPOSITE = HERE / "msbasic68k-hw-composite.bin"

BAS = ROOT / "research" / "mez6502" / "ASCIIART.BAS"
GOLDEN_PATH = ROOT / "golden" / "asciiart-output.txt"
GOLDEN_LEN = 2025
GOLDEN_SUM16 = 25584
GOLDEN_CRC32 = 0x0D6D8795

ENDMARK = 'PRINT "ZZHWEND"'
UNTIL = "\r\nZZHWEND\r\n"     # response framing only (not the echo)

SMOKE_LINES = [
    'PRINT 2+3*4',
    'PRINT 1/3',
    'A$="FOO":B$="BAR":PRINT A$+B$+"!"',
    '10 GOSUB 100: PRINT "BACK": END',
    '100 PRINT "SUB": RETURN',
    'RUN',
    'NEW',
    '10 A$="0123456789"',
    '20 FOR I=1 TO 2000',
    '30 B$=A$+A$+A$+A$+A$',
    '40 NEXT I',
    '50 PRINT "SURVIVED"',
    '60 PRINT B$',
    'RUN',
    'NEW',
    '10 A$=""',
    '20 FOR I=1 TO 50: A$=A$+"AB": NEXT I',
    '30 PRINT A$',
    'RUN',
    ENDMARK,
]
# expected response payloads, by position in SMOKE_LINES
SMOKE_WANT = {
    0: " 14 ",
    1: " .333333333 ",
    2: "FOOBAR!",
    5: "SUB\r\nBACK",
    13: "SURVIVED\r\n" + "0123456789" * 5,
    18: "AB" * 50,
}


def sum16(data: bytes) -> int:
    s = 0
    for b in data:
        s = (s + b) & 0xFFFF
    return s


def payloads(tx: str, lines):
    """Per-line response payloads, run_m4.py style."""
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


def run_emu(emu, script: Path, out: Path, maxcycles: int,
            timeout: int):
    cmd = [emu, "--image", str(COMPOSITE),
           "--masters", str(SIM / "masters"),
           "--script", str(script), "--out", str(out),
           "--until", UNTIL, "--settle", "0",
           "--maxcycles", str(maxcycles)]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=timeout)
    print(f"emu[{Path(emu).name}/{script.name}]:",
          r.stdout.strip(), f"(rc={r.returncode})")
    return r.returncode, out.read_bytes()


def verify(emu, tag, check):
    """Run the smoke + ASCIIART sessions under one emulator."""
    # ---- smoke session ----
    script = HERE / f"hw-{tag}.script"
    out = HERE / f"hw-{tag}.out"
    script.write_bytes(
        "".join(l + "\r" for l in SMOKE_LINES).encode("ascii"))
    rc, txb = run_emu(emu, script, out, 2_000_000_000, 1200)
    check(f"{tag}: smoke emu exit 0", rc == 0)
    tx = txb.decode("latin-1")
    i_b = tx.find("### COMMODORE BASIC ###")
    i_f = tx.find("40960 BYTES FREE")
    i_r = tx.find("READY.")
    check(f"{tag}: banner + 40960 BYTES FREE + READY, in order",
          0 <= i_b < i_f < i_r,
          f"banner@{i_b} free@{i_f} ready@{i_r}")
    got = payloads(tx, SMOKE_LINES)
    for idx, want in SMOKE_WANT.items():
        check(f"{tag}: smoke [{SMOKE_LINES[idx]}] -> payload",
              got[idx] == want,
              f"got {got[idx]!r}" if got[idx] != want
              else f"= {want[:24]!r}...")

    # ---- ASCIIART session ----
    prog = [ln for ln in BAS.read_text().splitlines() if ln.strip()]
    lines = prog + ["RUN", ENDMARK]
    script = HERE / f"hw-{tag}-art.script"
    out = HERE / f"hw-{tag}-art.out"
    script.write_bytes(
        "".join(l + "\r" for l in lines).encode("ascii"))
    rc, txb = run_emu(emu, script, out, 5_000_000_000, 1800)
    check(f"{tag}: ASCIIART emu exit 0", rc == 0)
    golden = GOLDEN_PATH.read_bytes()
    pic = None
    i = txb.find(b"RUN\r\n")
    if i >= 0:
        pic = txb[i + 5: i + 5 + GOLDEN_LEN]
    if pic is not None and len(pic) == GOLDEN_LEN and pic == golden:
        check(f"{tag}: ASCIIART picture == golden (byte exact)",
              True, f"sum16={sum16(pic)} crc32="
              f"{zlib.crc32(pic) & 0xFFFFFFFF:08X}")
    else:
        detail = "picture not extracted"
        if pic is not None and len(pic) == GOLDEN_LEN:
            k = next(n for n in range(GOLDEN_LEN)
                     if pic[n] != golden[n])
            detail = (f"first mismatch at byte {k}: "
                      f"got {pic[k]:02X}, want {golden[k]:02X}")
        check(f"{tag}: ASCIIART picture == golden (byte exact)",
              False, detail)
    if pic is not None and len(pic) == GOLDEN_LEN:
        after = txb[i + 5 + GOLDEN_LEN: i + 5 + GOLDEN_LEN + 16]
        check(f"{tag}: READY. after the picture",
              after.startswith(b"\r\nREADY.\r\n"), repr(after))


def main() -> int:
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name, detail)

    # ---- build the HW variant ----
    r = subprocess.run([sys.executable, str(HERE / "build_hw.py")],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    check("build_hw.py exit 0", r.returncode == 0)

    hw = HW_BIN.read_bytes()
    check("HW entry is code, not vectors (MOVE.W #$2700,SR first)",
          hw[:4] == bytes([0x46, 0xFC, 0x27, 0x00]),
          f"first bytes {hw[:8].hex()}")

    # ---- composite image: vector stub + HW binary at $30000 ----
    comp = bytearray(0x30000 + len(hw))
    struct.pack_into(">I", comp, 0, 0x40000)    # reset SSP
    struct.pack_into(">I", comp, 4, 0x30000)    # reset PC -> HWENTRY
    comp[0x30000:] = hw
    COMPOSITE.write_bytes(comp)
    check("composite image built",
          len(comp) == 0x30000 + len(hw),
          f"{len(comp)} bytes, HW image at $30000")

    # ---- branch checkers (listing addresses index the composite) ----
    for chk in ("check_branches.py", "check_short_branches.py"):
        r = subprocess.run([sys.executable, str(HERE / chk),
                            str(HW_LST), str(COMPOSITE)],
                           capture_output=True, text=True)
        tail = (r.stdout + r.stderr).strip().splitlines()
        check(f"branch checker {chk}",
              bool(tail) and tail[-1].startswith("0 bad"),
              tail[-1] if tail else "(no output)")

    # ---- golden sanity ----
    golden = GOLDEN_PATH.read_bytes()
    check("golden length/sum16/CRC32",
          len(golden) == GOLDEN_LEN
          and sum16(golden) == GOLDEN_SUM16
          and (zlib.crc32(golden) & 0xFFFFFFFF) == GOLDEN_CRC32,
          f"{len(golden)} bytes")

    # ---- verify under both emulators ----
    verify(EMU, "emu", check)
    verify(EMU_STRICT, "strict", check)

    ok = all(v for _, v in checks)
    print("HW:", "PASS" if ok else "FAIL",
          f"({sum(1 for _, v in checks if v)}/{len(checks)} checks)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
