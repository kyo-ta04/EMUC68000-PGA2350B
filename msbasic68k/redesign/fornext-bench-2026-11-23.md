# FOR–NEXT ループ速度比較 — MS-BASIC 68K (R2+C1) vs EhBASIC

Date: 2026-11-23. Venue: host sim (Musashi), deterministic cycle counts
(not wall time). Question from Kyo: FOR–NEXT ループではどの位の差か。

## Builds

- MS-BASIC: redesign `rd` (accepted R2+C1), rebuilt and verified
  before measuring: **19,794 B / BSD sum 52171** (`build.py rd` PASS).
  Image `redesign/msbasic68k-rd.bin`, booted as resident $0 image.
- EhBASIC: firmware EhBASIC, `sim/spike/ehbasic.bin`, booted
  unmodified by the same `emu` with the same `masters/`.

## Method

`emu` reports total cycles when the `--until` marker is seen, in
100,000-cycle quanta, including boot, script typing, RUN and PRINT.
Each shape was therefore run at **two sizes with equal digit counts**
(N = 20,000 and 60,000; nested: inner M = 500 / 1,500 × outer 100),
and cycles/iteration is the **slope** (C2−C1)/(iters2−iters1), which
cancels the fixed overhead. `--settle 0`; check values are PRINTed
*before* the end marker so nothing needed is cut off. Residual
quantisation error on the slope is ≤ ±2.5 cycles/iter (±1 for the
nested shape). Every run's printed final values were checked against
the expected values on both interpreters — all matched (table below).

Driver: `/tmp/fornext/bench.py` (ephemeral; shapes are reproduced
in full below).

## Shapes and raw totals

### S1 — empty FP loop `FOR I=1 TO N / NEXT I` (check: I = N+1)

| interp | N=20,000 | N=60,000 | cycles/iter |
|---|---|---|---|
| MS-BASIC | 89,600,000 | 277,000,000 | **4,685.0** |
| EhBASIC  | 57,800,000 | 173,900,000 | **2,902.5** |

Ratio MS/EH = **1.614**.

### S2 — empty integer loop, MS-BASIC only `FOR I%=1 TO N / NEXT I%` (check: I% = N+1)

| interp | N=20,000 | N=60,000 | cycles/iter |
|---|---|---|---|
| MS-BASIC (int) | 44,300,000 | 131,600,000 | **2,182.5** |

EhBASIC has no integer type; cross-type vs EhBASIC's S1 FP loop:
2,182.5 / 2,902.5 = **0.752** (MS-BASIC integer loop is faster than
EhBASIC's FP loop). Against MS-BASIC's own FP loop: 0.466.

### S3 — FP body `A=0 / FOR I=1 TO N / A=A+1 / NEXT I` (check: A=N, I=N+1)

| interp | N=20,000 | N=60,000 | cycles/iter |
|---|---|---|---|
| MS-BASIC | 231,400,000 | 697,500,000 | **11,652.5** |
| EhBASIC  | 187,600,000 | 563,400,000 | **9,395.0** |

Ratio MS/EH = **1.240**.

### S4 — integer body, MS-BASIC only `A%=0 / FOR I%=1 TO N / A%=A%+1 / NEXT I%` (check: A%=N, I%=N+1)

| interp | N=20,000 | N=60,000 | cycles/iter |
|---|---|---|---|
| MS-BASIC (int) | 185,500,000 | 546,700,000 | **9,030.0** |

Cross-type vs EhBASIC's S3 FP body: 9,030.0 / 9,395.0 = **0.961** —
only a tie, not a win. Against MS-BASIC's own FP body: 0.775.

### S5 — FP body with STEP 2 `FOR I=1 TO N STEP 2 / A=A+1` (check: A=N/2, I=N+1)

| interp | N=20,000 | N=60,000 | cycles/iter |
|---|---|---|---|
| MS-BASIC | 115,700,000 | 347,800,000 | **11,605.0** |
| EhBASIC  | 93,900,000  | 281,700,000 | **9,390.0** |

Ratio MS/EH = **1.236** — per iteration essentially identical to S3
on both interpreters (STEP itself costs nothing measurable).

### S6 — nested empty FP loop `FOR J=1 TO 100 / FOR I=1 TO M / NEXT I / NEXT J` (check: J=101, I=M+1)

Cycles per *inner* iteration (slope over 50,000 → 150,000 inner
iterations; includes outer-loop cost amortised at 1/500–1/1500):

| interp | M=500 | M=1,500 | cycles/inner-iter |
|---|---|---|---|
| MS-BASIC | 216,300,000 | 632,800,000 | **4,165.0** |
| EhBASIC  | 147,700,000 | 439,900,000 | **2,922.0** |

Ratio MS/EH = **1.425**, in line with the flat empty loop (S1).

## Where the cycles go (body cost = body shape − empty loop)

| | MS FP | MS int | EhBASIC FP |
|---|---|---|---|
| empty loop / iter | 4,685 | 2,183 | 2,903 |
| `A=A+1` body alone | 6,968 | 6,848 (`A%=A%+1`) | 6,493 |

The integer win is concentrated in the **FOR/NEXT machinery**
(2,183 vs 4,685 per empty iteration). The *body statement* costs
about the same (~6.5–7.0k) on all three paths: one statement's
evaluation overhead dominates, and the arithmetic itself is a small
part of it. That is why S4 only ties EhBASIC's FP body instead of
beating it clearly.

## Prediction scorecard (predictions recorded before measuring)

| # | prediction | measured | verdict |
|---|---|---|---|
| 1 | empty FP loop: MS ≈ 1.3–1.6× EH | **1.614×** | at the band edge, marginally over (by 0.01) |
| 2 | int empty (MS int vs EH FP): MS ≈ 0.5–0.8× | **0.752×** | **hit** |
| 3 | FP body A=A+1: MS ≈ 1.3–1.5× EH | **1.240×** | miss — below the band (MS relatively faster than predicted) |
| 4 | int body (MS int vs EH FP body): MS ≈ 0.4–0.7× | **0.961×** | miss — well above the band (only a tie) |

Predictions 3 and 4 both erred in the same direction: they assumed
the body statement would scale with the loop machinery / arithmetic
type. It doesn't — statement evaluation overhead (~6.5–7k cycles) is
type-insensitive here and dominates any body-carrying loop.

## Dialect notes

- The identical source text ran on both interpreters for S1/S3/S5/S6
  (`NEXT I` with the variable named; separate `NEXT I` / `NEXT J`
  for the nested shape). No dialect adaptation was needed.
- Feeding followed each tree's harness convention: LF-terminated
  script lines for EhBASIC (bench.script precedent), CR-terminated
  for MS-BASIC (run_rd.py convention).
- Cross-type comparisons (S2, S4) are labelled as such: EhBASIC has
  no `%` type, so its FP loop is the only comparator.

## Bottom line

- Pure FP loops: EhBASIC is faster — 1.61× (empty), 1.24× (with an
  `A=A+1` body), 1.43× (nested inner).
- MS-BASIC's integer FOR/NEXT machinery is genuinely fast: an empty
  integer loop beats even EhBASIC's FP loop (0.75×).
- But an integer *body* does not compound the win: `A%=A%+1` only
  ties EhBASIC's FP body (0.96×), because statement evaluation, not
  arithmetic, dominates the body cost.
