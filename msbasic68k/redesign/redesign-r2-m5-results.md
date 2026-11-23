# R2-M5 results — native math pack + evaluator FAC traffic (2026-11-22)

Baseline at M5 start (re-verified before any edit): build PASS,
run_rd 233/233, ASCIIART **1,005,000,000** cycles, image 19,240 B /
sum 36432 (the M4 endpoint).

Predictions recorded up front (Kyo's yardstick: measurements, not
gates): Stage 1 ASCIIART 850–950M; Stage 2 total 700–900M.
Hard invariant: every FP result bit-identical (mantissa, exponent,
FACOV, rounding) — any 1-ulp drift is a FAIL.

Files changed: `redesign/parts/60-core-b.asm` only (both stages so
far). `run_rd.py` untouched; no check expectation changed; `phase1/`
untouched. No asm68k-py extension needed (MULU/ADDX/SUBX/ROXR/LSL
were all already encodable).

---

## Stage 1 — native math pack on the memory FAC — GATE PASSED

Gate: build PASS; run_rd **233/233 on emu AND emu_strict**;
ASCIIART byte-identical (sum16 25584 / CRC32 0D6D8795);
ASCIIART cycles **898,300,000** (baseline 1,005,000,000 → −106.7M,
−10.6%; inside the 850–950M prediction band).
Image: 19,244 B / sum 26971 (+4 B vs M4).

### NORMALIZE — rewritten in registers

The old byte-at-a-time loop is now: load the 40-bit field (mantissa
long in D0, FACOV byte in D1) once, count the shift in D2 — the
same clobber set as before (D0–D2). Chunked shifts: if the field <
2^16 shift left 16 (count 16); if < 2^24 shift left 8 (count += 8);
then a bit loop (LSL.B #1,D1 / ROXL.L #1,D0) of at most 7
iterations. Exponent rule unchanged: count ≥ exponent → ZERO_FAC.
Zero mantissa → ZERO_FAC immediately (the old code reached it
after 4 byte shifts with count == 32; the only difference is that
mantissa bytes under a zero exponent may hold different stale
values — inert, because every consumer tests the exponent byte
first and the original itself leaves path-dependent stale bytes
there).

### FMULT_CORE — MULU-based 32×32→64, bit-identical by construction

Key fact (proof in the code comment): the old bit-serial loop
computes exactly `floor(Mcand · B40 / 2^32)`, where Mcand is the
ARG mantissa and B40 is the FAC mantissa:FACOV 40-bit field. Each
add-and-rotate step maintains `2^40·acc = Mcand·2^8·(bits consumed)
− D` with `0 ≤ D < 2^40`, forcing D = product mod 2^40 at the end;
the ROL extraction then yields the floor formula. So any exact
64-bit product gives the identical result field.

New core: split B40 = B32·2^8 + FACOV. Mcand·B40 = P·2^8 + T with
P = Mcand·B32 (full 64-bit, new **UMUL64** helper: 16-bit partial
products, same construction as IMUL32) and T = Mcand·FACOV.
Result = (P >> 24) + (T >> 32) + carry, where carry = 1 iff
((P mod 2^24) << 8) + (T mod 2^32) ≥ 2^32. Prologue (zero checks,
exponent sum, TMPEXP, SGNCPR → FACSIGN, FACTYP clear) unchanged.

Two measured refinements after the first bench (952.7M):
- FACOV is a single byte, so T needs only 2 MULUs (not a second
  UMUL64): t1 = mh·ov < 2^24, t0 = ml·ov; Thi/Tlo assembled with
  one carry.
- FACOV == 0 skips T entirely (common case: literals, integers).

UMUL64: in D6 = a, D7 = b → out D1 = high, D0 = low; clobbers
D2–D7 (inputs consumed) — inside FMULT_CORE's existing clobber
contract. Hand-verified $FFFFFFFF² → hi $FFFFFFFE, lo 1.

### FDIV_CORE — restoring division with a proven skip-ahead

The old 65-step loop's first 31 steps provably only shift: after
k steps the remainder equals the dividend's top k bits, which is
< 2^k ≤ 2^31 ≤ divisor (both mantissas normalised), so no
subtraction can succeed. New setup jumps straight to that state:
D1 = 0, D2 = A >> 1 (remainder), D6 = A << 31 (remaining dividend
bits), quotient registers zero, and the loop counter drops
65 → 34. The loop body, the quotient spec (Q34 = floor(A·2^33/D)),
and the extraction (mantissa = Q34 >> 2, FACOV = (Q34 & 3) << 6)
are unchanged, so the quotient and rounding are bit-identical.
(The R0-era faster division was not needed; this keeps the
existing core's exact semantics with ~half the iterations.)

### FADD_CORE — register alignment + long-word op (and a bug)

What changed:
- The small operand's 40-bit field now rides in registers
  (D0 = mantissa, D1 = extension byte) instead of the RESULT
  memory field. The alignment reproduces the old loop's exact
  arithmetic: byte shifts while count ≥ 8 (the byte about to fall
  out feeds the sticky), then single bits (the falling bit feeds
  the sticky), with one shortcut — once the field is zero the
  remaining shifts change nothing (the old loop shifting zeros
  proves it).
- The 40-bit add/subtract is one byte op + one long op through X
  (ADD.B/SUB.B on the extension bytes, ADDX.L/SUBX.L on the
  mantissa longs) instead of five byte-wise ADDX/SUBX steps
  against memory. The carry-out path (ROXR pair + exponent+1),
  the sticky −1 tail, the borrow/NEGFAC40 path and the sign
  selection are the old code, reached with the field stored to
  FAC first where the tail works on FAC memory.

Deliberately left: FSUB_CORE (a sign flip into FADD_CORE — it
inherits the win), FADDH/FMUL10/FDIV10 wrappers, ROUND_FAC,
INC_FAC_M, NEGFAC40, and the RESULT-field protocol (FOR/NEXT in
64-core-b3 still uses RESULT; FADD no longer writes it, and
nothing read FADD's RESULT field — verified by grep + suite).

**Bug found and fixed during Stage 1 (the important lesson):**
the first register version broke 74 checks and, worse, corrupted
FIN literal parsing (12 parsed toward 10, fraction digits lost,
USR vector appeared unset). Root cause: **the old byte-chain
FADD_CORE preserved D2; the register version used D2 as the big
operand.** Callers rely on the preservation — FIN parks the
current digit in D2 across FMUL10 precisely because only D0 was
documented as clobbered. Fix: FAD_SH pushes D2 (both FADD entries
pass through FAD_SH exactly once) and every exit restores it —
the two add-path RTSs and a pop stub before the subtract path's
BRA NORMALIZE (NORMALIZE then clobbers D2 again, exactly as the
old chain behaved; the OVERR exit needs no restore because ERROR
resets SP to STACKTOP). A second, earlier attempt failed for a
different reason worth recording: feeding the small operand from
D0 with `LSR.L #8` between ADDX.B steps destroys X and breaks the
carry chain — shifts other than ROXL/ROXR must never sit between
ADDX/SUBX steps. After the D2 fix: probes 12/8 = 1.5, 11/8 =
1.375, 1.5+2.25 = 3.75 all exact, suite 233/233 on both emus.

Register clobber contracts after Stage 1 (audited against the old
code): NORMALIZE D0–D2 (same); FMULT_CORE D0–D7 (same; A1 no
longer used); FDIV_CORE D0–D7 (same); FADD_CORE D0, D1, D3–D7
with D2 preserved (same as old — this is now pinned by the FIN
behaviour in the suite).

---

## Stage 2 — register layer under the performers — GATE PASSED

Gate: build PASS; run_rd **233/233 on emu AND emu_strict**;
ASCIIART byte-identical (sum16 25584 / CRC32 0D6D8795);
ASCIIART cycles **883,200,000** (Stage 1's 898.3M → −15.1M;
cumulative vs the 1,005.0M baseline: −121.8M, −12.1%; inside the
700–900M prediction band for the Stage 2 total).
Image: 19,148 B / sum 26291 (−96 B vs Stage 1: the byte chains
were also the longer code).

### Which reading of §4 was built, and why

The full §4 sketch (FAC in D4/D5 across the whole evaluator) was
audited against the code as built by M1–M4 and **not** taken:
FRMEVL itself owns D3 (relational mask), D4 (operator index) and
D5 (popped precedence) for the duration of every pass, the
performers clobber D0–D7 wholesale, and the memory FAC is the
interface for FOUT, LET/ST_FAC, FOR/NEXT frames, the function
dispatch, the M4 USR boundary (which must see the synced
(FAC, FACINT, FACTYP) triple in memory) and CONT/STOP state.
Holding FAC in registers across that surface would need a
save/restore at nearly every boundary — the traffic it saves is
the traffic it adds, with far more places to get it wrong. The
brief's lower-risk reading was taken instead: **the register
layer sits UNDER the performers; the memory FAC remains the one
interface.** Concretely, Stage 1 already put the registers inside
the cores; Stage 2 removes the remaining byte-at-a-time FAC
traffic on the evaluator's frame path and the FAC↔ARG copies:

- **CP_F2A / CP_A2F**: the 5-byte copies are now `MOVE.L` +
  `MOVE.B` (FAC and ARG are both even-based ZP slots; the copied
  byte set — exponent + mantissa — is unchanged, as are the
  ARGEXT/FACOV clears and the sign copies). These run on every
  FIN scaling step (CP_F2AR), every FADD FAC=0 exit, FDIV and the
  FMUL10/FDIV10 chains.
- **EV_RECURSE frame push**: the stacked operand's 5 FAC bytes
  were 5 byte pushes; they are now `MOVE.L FAC,-(SP)` +
  `MOVE.B FAC+4,-(SP)`.
- **PERFORM2 frame pop**: mirrored — `MOVE.B (SP)+,ARG+4` then
  `MOVE.L (SP)+,ARG`.

Frame-layout note (the parity trap): the push/pop pair order had
to flip together. The stack bytes are the same 5, the frame size
is unchanged, and the long accesses land on the same even
addresses the old sequence's parity produces (pushing the long
first, while SP is still even, then the byte; popping the byte
first, then the long). Nothing else reads those 5 frame bytes —
PERFORM2 is the only consumer, and the string-operand path
(EV_RSK, descriptor long pushed separately) is untouched.
Verified beyond the suite with emu_audit: no odd-address accesses
logged on an arithmetic session.

### Sync-boundary list (as built)

Because the memory FAC is the interface, there is exactly one
rule: **no value ever lives only in registers across a call.**
Registers are used strictly inside one core/frame operation and
written back to the memory FAC/ARG before returning. Therefore:

- Statement boundaries, BRKCHK, CONT/STOP: memory FAC is always
  current — nothing to sync.
- Function dispatch and the USR boundary: performers run to
  completion in memory first; the M4 USRTYP/FACINT contract sees
  the synced triple by construction.
- EV_RECURSE recursion: the frame carries the operand in memory
  form (packed bytes + FACINT + FACTYP), so nesting is the M2
  frame discipline unchanged; ROUND_FAC still runs before the
  push (the stacked operand is the rounded FAC), and the string
  path still skips it.
- Error paths: an error mid-expression finds the memory FAC
  holding the last completed performer's result, exactly as
  before M5 — no register residue exists to go stale.
- CPRTYP: untouched (PERFORM2's pop still writes CPRMASK only).
- CAT string bypass: untouched (the frame's descriptor long and
  the EV_RSK path are byte-for-byte the old behaviour).

### Deliberately left alone in Stage 2

- LD_FAC / LD_ARG / ST_FAC / ST_FAC_TAG: these move values
  through (A0), which can point at odd-aligned array elements —
  byte moves there are the odd-address discipline, not sloppiness.
- The integer wrappers and FAC2INT/IDIV32: already register-
  internal where it matters (M2/M3); their interface is FACINT.
- FRM_ELEMENT/FIN control flow: the literal cache (M1) already
  covers repeated literals; restructuring FIN was out of scope.

### Deviations / surprises

- The Stage 2 gain (−15.1M) is much smaller than Stage 1's
  (−106.7M): ASCIIART's cost sits in the cores and in FOUT/FIN
  control flow, not in the frame copies. Recorded as measured;
  per Kyo's yardstick this is a result, not a shortfall to chase
  by taking the risky full-register reading.
- Two Stage 1 attempts failed before the keeper (LSR-between-ADDX
  carry-chain break; FADD D2 clobber) — both are documented in
  the Stage 1 section because both are traps the next person
  editing this pack will otherwise rediscover the hard way.
- No check expectation changed; no new checks added (M5 is
  semantics-invariant and the 233-check suite + golden are the
  bit-identity proof). `run_rd.py` untouched.

### M5 totals

| point | ASCIIART cycles | image | sum |
|---|---|---|---|
| M4 endpoint (baseline) | 1,005,000,000 | 19,240 B | 36432 |
| Stage 1 | 898,300,000 | 19,244 B | 26971 |
| Stage 2 | 883,200,000 | 19,148 B | 26291 |

Predictions vs actuals: Stage 1 predicted 850–950M → 898.3M ✓.
Stage 2 total predicted 700–900M → 883.2M ✓ (top of the band —
the evaluator-traffic share of ASCIIART was smaller than the
sketch assumed; the FP-core share was the real one, and Stage 1
took it).

## Errata（2026-11-22、メイン側の照合で判明）

最終イメージの BSD sum は本記録の 26291 ではなく **49995**（19,148 B は一致）。build.py rd を 2 回連続で実行して決定性を確認済みで、現行ツリーに対して run_rd.py をメイン側で再実行し **233/233 PASS**（ASCIIART バイト一致を含む）。26291 は中間ビルドの値を最終値として記録したものとみられる。Stage 2 のサイクル数 883,200,000 は実施時のゲートビルドでの測定値として残す。

