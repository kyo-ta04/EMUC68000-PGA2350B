import re, sys
lst = open(sys.argv[1]).read().splitlines()
img = open(sys.argv[2],'rb').read()
# collect instruction addresses and label addresses from the listing
insn_addr = set()
labels = {}
for l in lst:
    m = re.match(r'^([0-9A-F]{6})\s+([0-9A-F ]{2,})\s+\d+\s+(.*)$', l)
    if m:
        insn_addr.add(int(m.group(1),16))
    m2 = re.match(r'^(\S+)\s+([0-9A-F]{6})\s+label', l)
    if m2: labels[m2.group(1)] = int(m2.group(2),16)
def w(a): return (img[a]<<8)|img[a+1]
bad = 0
for a in sorted(insn_addr):
    if a+1 >= len(img): continue
    op = w(a)
    kind = None; target = None
    if op & 0xFF00 == 0x6000:  # BRA/BSR/Bcc
        d8 = op & 0xFF
        if d8 == 0:
            if a+3 >= len(img): continue
            d = w(a+2);  d = d-0x10000 if d & 0x8000 else d
            target = a+2+d; kind='branch.W'
        elif d8 == 0xFF:
            continue  # long form (68020+) not used
        else:
            d = d8-0x100 if d8 & 0x80 else d8
            target = a+2+d; kind='branch.S'
    if target is not None and target not in insn_addr and target not in labels.values():
        print(f'BAD {kind} at ${a:06X}: target ${target:06X} not an instruction boundary')
        bad += 1
print(f'{bad} bad branches')
