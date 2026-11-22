#!/usr/bin/env python3
"""Check every short (byte-displacement) branch in an asm68k listing:
the encoded target must equal the intended label's address.
asm68k-py silently truncates out-of-range .S displacements."""
import re
import sys

lst = open(sys.argv[1]).read()
lines = lst.splitlines()

# symbol table: "LABEL  00000A2C  label"
syms = {}
for ln in lines:
    m = re.match(r"^(\S+)\s+([0-9A-F]{8})\s+label", ln)
    if m:
        syms[m.group(1)] = int(m.group(2), 16)

bad = 0
for ln in lines:
    # code line: "000776  67 94    ...  BEQ.S   PRTERM ..."
    m = re.match(r"^([0-9A-F]{6})\s+([0-9A-F]{2}) ([0-9A-F]{2})\s+.*?"
                 r"\b(B[A-Z]{2,3}|BRA)\.S\s+(\S+)", ln)
    if not m:
        continue
    addr = int(m.group(1), 16)
    op = int(m.group(2), 16)
    disp = int(m.group(3), 16)
    if op & 0xF0 != 0x60:
        continue
    if disp == 0:
        continue  # word displacement follows; not a byte branch
    if disp >= 0x80:
        disp -= 0x100
    target = addr + 2 + disp
    label = m.group(5).rstrip(",")
    want = syms.get(label)
    if want is not None and want != target:
        print(f"BAD {ln.strip()}  -> encoded ${target:06X}, "
              f"{label} is ${want:06X}")
        bad += 1
print(f"{bad} bad short branches")
sys.exit(1 if bad else 0)
