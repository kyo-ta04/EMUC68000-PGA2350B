#!/usr/bin/env python3
"""M7 verification: EXT1 (extension phase, batch 1) for the
MS-BASIC 68K port -- &H literals, a live USR, DEEK/DOKE/
LEEK/LOKE, INSTR and ELSE, in MS Extended BASIC form.

Gates, in order:
  1. build.py builds all four flavours; the FAITHFUL flavours
     keep their byte-identity gate inside build.py (sim 15492
     bytes / BSD sum 32410, hw 15500 / 17566 -- the post-M8
     reference values; M8's READY. fix moved the sums at
     unchanged sizes).  The EXT sizes and sums are recorded
     and printed.
  2. Branch checkers on both EXT listings ("0 bad").
  3. EXT-SIM spec session (this file's SESSION): byte-exact
     response regions, 68K-only like run_break.py -- the new
     features have no CBM golden.  Includes the CTRL-C break
     session (the EXT FETCH/IF parts must not break BRKCHK).
  4. EXT-SIM ASCIIART: the picture must equal the CBM golden
     byte for byte (the extension must not perturb the core).
  5. EXT-HW: composite boot (vector stub + image at $30000,
     run_hw.py style) under BOTH emu and emu_strict: banner,
     40960 BYTES FREE, an EXT smoke set, ASCIIART == golden.
  6. Faithful regression: run_break.py as a subprocess (it
     cascades run_m5d.py's 116/118-with-2-known-ulp gate and
     run_hw.py).
  7. EXT-flavour regression: the existing suite must pass
     against the EXT source too.  run_m5d.py (which cascades
     run_m1.py..run_m5c.py) assembles msbasic68k.asm by name,
     so the EXT combined source is swapped in under that name
     for the run and the faithful build is restored after.

This script honours MSB_EMU for its own sim sessions.
Exit status 0 = PASS.
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
EMU = os.environ.get("MSB_EMU", str(SIM / "emu"))
EMU_STRICT = str(SIM / "emu_strict")

RD_BIN = HERE / "msbasic68k-rd.bin"
EXT_BIN = RD_BIN
RD_LST = HERE / "msbasic68k-rd.lst"
EXT_LST = RD_LST
HWEXT_BIN = HERE / "msbasic68k-hw-ext.bin"
HWEXT_LST = HERE / "msbasic68k-hw-ext.lst"
COMPOSITE = HERE / "msbasic68k-hw-ext-composite.bin"

BAS = ROOT / "research" / "mez6502" / "ASCIIART.BAS"
GOLDEN_PATH = ROOT / "golden" / "asciiart-output.txt"
GOLDEN_LEN = 2025
GOLDEN_SUM16 = 25584
GOLDEN_CRC32 = 0x0D6D8795

ENDMARK = 'PRINT "ZZX1";"END"'  # split so the echo alone
                                # cannot trip the emu's --until

FC_R = "?FC ERROR\r\n\r\nREADY.\r\n"
SN_R = "?SN ERROR\r\n\r\nREADY.\r\n"
IQ_R = "?IQ ERROR\r\n\r\nREADY.\r\n"
DZ_R = "?/0 ERROR\r\n\r\nREADY.\r\n"
TM_R = "?TM ERROR\r\n\r\nREADY.\r\n"


def num(v):
    """The region for a direct PRINT of one number."""
    return f" {v} \r\n\r\nREADY.\r\n"


# Entries: ("L", text, "", None)                 stored line
#          ("C", text, data, expected-or-None)   direct line;
#          data = extra bytes fed right after text+"\r"
SESSION = [
    # ---- USR: unset vector -> ?FC (must precede any setup) ----
    ("C", "PRINT USR(0)", "", FC_R),
    ("C", "PRINT USR(1+2)", "", FC_R),
    # ---- &H literals ----
    ("C", "PRINT &H0", "", num(0)),
    ("C", "PRINT &HFF", "", num(255)),
    ("C", "PRINT &H1234", "", num(4660)),
    ("C", "PRINT &H7FFF", "", num(32767)),
    ("C", "PRINT &H8000", "", num(32768)),      # unsigned, not -32768
    ("C", "PRINT &HFFFF", "", num(65535)),
    ("C", "PRINT &H10000", "", num(65536)),
    ("C", "PRINT &H30000", "", num(196608)),
    ("C", "PRINT &HFFFFFFFF-4294967295", "", num(0)),
    ("C", "PRINT &H80000000/2147483648", "", num(1)),
    ("C", "PRINT &HDEF", "", num(3567)),        # CRUNCH trap: DEF
    ("C", "PRINT &HDEAD", "", num(57005)),
    ("C", "PRINT &H10+&H20", "", num(48)),
    ("C", "PRINT &HA-10", "", num(0)),
    ("C", "PRINT &H", "", SN_R),                # no digits
    ("C", "PRINT &H123456789", "", SN_R),       # 9 digits
    # ---- DEEK/DOKE/LEEK/LOKE (logical page, $9000 = 36864) ----
    ("C", "DOKE 36864,4660: PRINT DEEK(36864)", "", num(4660)),
    ("C", "PRINT PEEK(36864); PEEK(36865)", "",
     " 18  52 \r\n\r\nREADY.\r\n"),              # big-endian $12,$34
    ("C", "DOKE 36865,43981: PRINT DEEK(36865)", "", num(43981)),
    ("C", "PRINT PEEK(36865); PEEK(36866)", "",
     " 171  205 \r\n\r\nREADY.\r\n"),           # odd addr, $AB,$CD
    ("C", "DOKE 36864,65535: PRINT DEEK(36864)", "", num(65535)),
    ("C", "LOKE 36864,305419896: PRINT LEEK(36864)", "",
     num(305419896)),                           # $12345678
    ("C", "PRINT PEEK(36866); PEEK(36867)", "",
     " 86  120 \r\n\r\nREADY.\r\n"),            # $56,$78
    ("C", "LOKE 36865,4294967295: PRINT LEEK(36865)-4294967295",
     "", num(0)),                               # odd addr, $FFFFFFFF
    ("C", "PRINT DEEK(36865); DEEK(36867)", "",
     " 65535  65535 \r\n\r\nREADY.\r\n"),
    ("C", "LOKE 36864,0: PRINT LEEK(36864)", "", num(0)),
    ("C", "DOKE 36864,65536", "", IQ_R),
    ("C", "DOKE 36864,-1", "", IQ_R),
    ("C", "LOKE 36864,-1", "", IQ_R),
    ("C", "PRINT DEEK(65536)", "", None),        # R1: widened GETADR
                                                # reads through (A1
                                                # session checks it)
    ("C", "PRINT DEEK(-1)", "", IQ_R),
    ("C", "PRINT LEEK(36864)", "", num(0)),     # still 0 after errors
    # ---- INSTR ----
    ("C", 'PRINT INSTR("HELLO","LL")', "", num(3)),
    ("C", 'PRINT INSTR("HELLO","X")', "", num(0)),
    ("C", 'PRINT INSTR(2,"HELLO","L")', "", num(3)),
    ("C", 'PRINT INSTR(4,"HELLO","L")', "", num(4)),
    ("C", 'PRINT INSTR(5,"HELLO","L")', "", num(0)),
    ("C", 'PRINT INSTR(6,"HELLO","L")', "", num(0)),
    ("C", 'PRINT INSTR("HELLO","")', "", num(1)),
    ("C", 'PRINT INSTR(3,"HELLO","")', "", num(3)),
    ("C", 'PRINT INSTR("","X")', "", num(0)),
    ("C", 'PRINT INSTR("","")', "", num(0)),
    ("C", 'PRINT INSTR("AAAA","AA")', "", num(1)),
    ("C", 'PRINT INSTR(2,"AAAA","AA")', "", num(2)),
    ("C", 'PRINT INSTR(3,"AAAA","AA")', "", num(3)),
    ("C", 'PRINT INSTR(4,"AAAA","AA")', "", num(0)),
    ("C", 'PRINT INSTR(0,"A","A")', "", FC_R),
    ("C", 'PRINT INSTR(-1,"A","A")', "", FC_R),
    ("C", 'PRINT INSTR("HELLO",5)', "", TM_R),
    ("C", 'PRINT INSTR(5,"HELLO")', "", SN_R),  # missing 3rd argument
    ("C", 'A$="COMPUTER": PRINT INSTR(A$,"PUT")', "", num(4)),
    ("C", 'PRINT INSTR("X"+"HELLO","LL")', "", num(4)),
    ("C", 'PRINT INSTR(LEFT$("HELLO",4),"LL")', "", num(3)),
    ("C", 'B$="LL": PRINT INSTR("HELLO",B$)', "", num(3)),
    ("C", 'PRINT INSTR("HELLO","LL")*10', "", num(30)),
    # ---- USR: identity routine at logical $6000, vector $334 ----
    ("C", "POKE 24576,78: POKE 24577,117", "", "\r\nREADY.\r\n"),
    ("C", "POKE 820,96: POKE 821,0", "", "\r\nREADY.\r\n"),
    ("C", "PRINT USR(5)", "", num(5)),
    ("C", "PRINT USR(-3)", "", "-3 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT USR(1.5)", "", " 1.5 \r\n\r\nREADY.\r\n"),
    ("L", "10 PRINT USR(7)", "", None),
    ("C", "RUN", "", num(7)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- USR: constant-2.0 routine (overwrites $6000) ----
    ("L", "10 FOR I=0 TO 31: READ B: POKE 24576+I,B: NEXT I",
     "", None),
    ("L", "20 DATA 16,188,0,130,17,124,0,128,0,1,66,40,0,2,"
          "66,40,0,3,66,40,0,4,66,40,0,5,66,40,0,6,78,117",
     "", None),
    ("C", "RUN", "", "\r\nREADY.\r\n"),
    ("C", "PRINT USR(0)", "", num(2)),
    ("C", "PRINT USR(99)", "", num(2)),
    ("C", 'PRINT USR("A")', "", TM_R),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: basic true/false with ':' sequences ----
    ("L", "10 A=5", "", None),
    ("L", '20 IF A=5 THEN PRINT "T1" ELSE PRINT "F1"', "", None),
    ("L", '30 IF A=6 THEN PRINT "T2" ELSE PRINT "F2"', "", None),
    ("L", '40 PRINT "DONE"', "", None),
    ("C", "RUN", "", "T1\r\nF2\r\nDONE\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: line-number forms, both directions ----
    ("L", "10 A=0", "", None),
    ("L", "20 IF A THEN 100 ELSE 200", "", None),
    ("L", '30 PRINT "BAD"', "", None),
    ("L", "40 END", "", None),
    ("L", '100 PRINT "TRUE-LINE"', "", None),
    ("L", "110 END", "", None),
    ("L", '200 PRINT "FALSE-LINE"', "", None),
    ("C", "RUN", "", "FALSE-LINE\r\n\r\nREADY.\r\n"),
    ("L", "10 A=1", "", None),   # M8: stored line, no READY.
    ("C", "RUN", "", "TRUE-LINE\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: THEN line number + ELSE statement ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN 100 ELSE PRINT "E"', "", None),
    ("L", "30 END", "", None),
    ("L", '100 PRINT "G100"', "", None),
    ("C", "RUN", "", "G100\r\n\r\nREADY.\r\n"),
    ("L", "10 A=0", "", None),   # M8: stored line, no READY.
    ("C", "RUN", "", "E\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: nesting, inner (true outer, false inner) ----
    ("L", "10 A=1: B=0", "", None),
    ("L", '20 IF A THEN IF B THEN PRINT "X" ELSE PRINT "INNER"',
     "", None),
    ("L", '30 PRINT "AFTER"', "", None),
    ("C", "RUN", "", "INNER\r\nAFTER\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: nesting, outer false (depth counting) ----
    ("L", "10 A=0: B=1", "", None),
    ("L", '20 IF A THEN IF B THEN PRINT "X" ELSE PRINT "INNER"'
          ' ELSE PRINT "OUTER"', "", None),
    ("L", '30 PRINT "AFTER"', "", None),
    ("C", "RUN", "", "OUTER\r\nAFTER\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: true path runs ':' sequence, ELSE skipped ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN PRINT "T": PRINT "T2" ELSE PRINT "F"',
     "", None),
    ("L", '30 PRINT "NEXT"', "", None),
    ("C", "RUN", "", "T\r\nT2\r\nNEXT\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: PRINT ';' directly before ELSE (quiet end) ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN PRINT "S"; ELSE PRINT "F"', "", None),
    ("L", '30 PRINT "NEXT"', "", None),
    ("C", "RUN", "", "SNEXT\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: PRINT ',' (zone) directly before ELSE ----
    ("L", "10 A=1", "", None),
    ("L", '20 IF A THEN PRINT "Z", ELSE PRINT "F"', "", None),
    ("L", '30 PRINT "N"', "", None),
    ("C", "RUN", "", "Z         N\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: DATA payload must not be misread as ELSE ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN DATA ELSE: PRINT "REAL" ELSE PRINT "FAKE"',
     "", None),
    ("C", "RUN", "", "FAKE\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: string payload must not be misread ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN PRINT "ELSE" ELSE PRINT "REAL2"', "", None),
    ("C", "RUN", "", "REAL2\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: REM swallows the rest (no ELSE found) ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN REM ELSE PRINT "X"', "", None),
    ("L", '30 PRINT "Y"', "", None),
    ("C", "RUN", "", "Y\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: no ELSE present -- faithful false path ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A THEN PRINT "NO"', "", None),
    ("L", '30 PRINT "YES"', "", None),
    ("C", "RUN", "", "YES\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: THEN omitted (IF c GOTO n ELSE ...) ----
    ("L", "10 A=0", "", None),
    ("L", '20 IF A GOTO 100 ELSE PRINT "E2"', "", None),
    ("L", "30 END", "", None),
    ("L", '100 PRINT "G"', "", None),
    ("C", "RUN", "", "E2\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- ELSE: direct mode ----
    ("C", 'IF 0 THEN PRINT 1 ELSE PRINT 2', "", num(2)),
    ("C", 'IF 1 THEN PRINT 1 ELSE PRINT 2', "", num(1)),
    # ---- R2-M1: int32 type foundation (D1/D5/D9, % widened) ----
    # D9: an INT literal prints as a plain integer where the FP
    # path used E notation (pre-R2: 2147483647 printed as
    # " 2.14748365E+09 ", 2000000000 as " 2E+09 ").
    ("C", "PRINT 2147483647", "", num(2147483647)),
    ("C", "PRINT 4294967295", "",
     " 4.2949673E+09 \r\n\r\nREADY.\r\n"),  # > int32: stays FP
    ("C", "PRINT &H7FFFFFFF", "", num(2147483647)),   # D1 via &H
    ("C", "PRINT &H80000000", "",
     " 2.14748365E+09 \r\n\r\nREADY.\r\n"),  # > int32: stays FP
    # D5: plain-variable INT round trip through the tag byte;
    # an FP re-store must clear the tag (no stale INT).
    ("C", "A=2000000000: PRINT A", "", num(2000000000)),
    ("C", "A=123456789: PRINT A", "", num(123456789)),
    ("C", "A=2000000000: A=1.5: PRINT A", "",
     " 1.5 \r\n\r\nREADY.\r\n"),
    # D5/D7: % is int32 now (pre-R2: 70000 was ?IQ via AYINT).
    ("C", "A%=70000: PRINT A%", "", num(70000)),
    ("C", "A%=2147483647: PRINT A%", "", num(2147483647)),
    ("C", "A%=-2147483648: PRINT A%", "",
     "-2147483648 \r\n\r\nREADY.\r\n"),     # '-' replaces the
                                            # leading space (FOUT
                                            # format; cf. USR(-3))
    # FP -> % keeps the inherited ROUND + floor chain
    # (pre-R2 probes: 2.5 -> 2, 3.5 -> 3, -2.5 -> -3).
    ("C", "A%=2.5: PRINT A%", "", num(2)),
    ("C", "A%=-2.5: PRINT A%", "", "-3 \r\n\r\nREADY.\r\n"),
    ("C", "A%=3E9", "", IQ_R),              # out of int32: ?IQ
    ("C", "A%=2147483648", "", IQ_R),
    # % array elements are 4-byte int32 slots (D7).
    ("C", "DIM B%(3): B%(2)=100000: PRINT B%(2)", "", num(100000)),
    ("C", "B%(1)=-99999999: PRINT B%(1); B%(2)", "",
     "-99999999  100000 \r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- R2-M2: integer operators (D2) + overflow promotion ----
    # (D3).  The FP-promotion expectations are the exact FOUT
    # strings probed on the pre-M2 (R2-M1) build, where every
    # operator still ran through FP.
    ("C", "PRINT 100000*3", "", num(300000)),       # INT result
    ("C", "PRINT 1000*1000", "", num(1000000)),
    ("C", "PRINT 46340*46340", "", num(2147395600)),  # largest
                                            # square that fits int32
    ("C", "C=30000*30000: PRINT C", "", num(900000000)),
    ("C", "PRINT -2147483647-1", "",
     "-2147483648 \r\n\r\nREADY.\r\n"),     # INT -2^31 exactly
    # Overflow promotes silently to FP (D3):
    ("C", "PRINT 2147483647+1", "",
     " 2.14748365E+09 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 2000000000+2000000000", "",
     " 4E+09 \r\n\r\nREADY.\r\n"),
    ("C", "A%=-2147483648: PRINT A%-1", "",
     "-2.14748365E+09 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 46341*46341", "",
     " 2.14748828E+09 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 65536*65536", "",
     " 4.2949673E+09 \r\n\r\nREADY.\r\n"),
    ("C", "A=100000: B=A*A: PRINT B", "",
     " 1E+10 \r\n\r\nREADY.\r\n"),          # promotion on assignment
    # Unary minus / NOT on INT:
    ("C", "A%=5: PRINT -A%", "", "-5 \r\n\r\nREADY.\r\n"),
    ("C", "A%=-2147483648: PRINT -A%", "",
     " 2.14748365E+09 \r\n\r\nREADY.\r\n"),  # -(-2^31) promotes
    ("C", "PRINT NOT 0", "", "-1 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT NOT 5", "", "-6 \r\n\r\nREADY.\r\n"),
    # AND/OR in int32 when both sides are INT (pre-M2 these were
    # ?IQ via the 16-bit AYINT path):
    ("C", "PRINT 2000000000 AND 2000000000", "", num(2000000000)),
    ("C", "PRINT 16777216 OR 255", "", num(16777471)),
    # Relational operators compare by value (exact FP shadows);
    # the result stays FP -1/0 as before R2:
    ("C", "PRINT 2000000000<2000000001", "",
     "-1 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 2147483647=2147483647", "",
     "-1 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 5=5.0", "", "-1 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 5<5.5", "", "-1 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 2147483647<2147483646", "", num(0)),
    # / is always FP (D2); assigning it to % uses the M1 chain:
    ("C", "PRINT 7/2", "", " 3.5 \r\n\r\nREADY.\r\n"),
    ("C", "A%=7/2: PRINT A%", "", num(3)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- R2-M3: \ and MOD operators (D2).  Operands convert
    # through the STO_INT32 chain (floor: 5.5 -> 5, probed on
    # the M2 build), division truncates toward zero and MOD's
    # sign follows the dividend.  Precedence (BASIC-80):
    # ^ > unary- > * / > \ > MOD > + - > relational > NOT >
    # AND > OR.  Negative results print with '-' in place of
    # the leading space (FOUT format).
    ("C", "PRINT 7\\2", "", num(3)),
    ("C", "A%=-7: PRINT A%\\2", "", "-3 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT -7\\2", "", "-3 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 7\\-2", "", "-3 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 10 MOD 3", "", num(1)),
    ("C", "A%=-10: PRINT A% MOD 3", "", "-1 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT 10 MOD -3", "", num(1)),
    ("C", "PRINT 5.5\\2", "", num(2)),        # 5.5 -> 5 (floor chain)
    ("C", "PRINT 10\\3*3", "", num(1)),       # * binds tighter than \
    ("C", "PRINT 10+10 MOD 3", "", num(11)),  # MOD tighter than +
    ("C", "PRINT 1\\0", "", DZ_R),
    ("C", "PRINT 2147483647\\1", "", num(2147483647)),
    ("C", "A%=-2147483648: PRINT A%\\-1", "", IQ_R),  # the one
                                            # quotient overflow
    ("C", "A%=-2147483648: PRINT A% MOD -1", "", num(0)),
    ("C", "MODE=5: PRINT MODE", "", num(5)),  # MOD prefix stays
    ("C", "MODX=7: PRINT MODX", "", num(7)),  # a variable name
    # Stored-program round trip: \ and MOD tokenise, LIST back
    # verbatim, and RUN.
    ("L", "10 A%=17: PRINT A%\\5: PRINT A% MOD 5", "", None),
    ("C", "LIST", "",
     "\r\n10 A%=17: PRINT A%\\5: PRINT A% MOD 5\r\nREADY.\r\n"),
    ("C", "RUN", "", " 3 \r\n 2 \r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- R2-M3: integer FOR (D4).  INT frame when variable,
    # limit and step are all INT; FP fallback (per-iteration
    # store through STO_INT32) when a % variable meets an FP
    # limit or step.
    ("C", "S=0: FOR I%=1 TO 100: S=S+I%: NEXT: PRINT S", "", num(5050)),
    ("C", "FOR I%=10 TO 1 STEP -3: PRINT I%: NEXT", "",
     " 10 \r\n 7 \r\n 4 \r\n 1 \r\n\r\nREADY.\r\n"),
    ("C", "C=0: FOR I%=2000000000 TO 2000000003: C=C+1: NEXT: PRINT C",
     "", num(4)),
    ("C", "C=0: FOR I%=1 TO 3.5: C=C+1: NEXT: PRINT C", "", num(3)),
    ("C", "FOR I%=1 TO 10 STEP 2: NEXT: PRINT I%", "", num(11)),
    ("C", "S=0: FOR I%=1 TO 3: FOR J%=1 TO 3: S=S+I%*J%: NEXT J%: NEXT I%: PRINT S",
     "", num(36)),
    # ---- R2-M4 Part 0: comma NEXT (pre-existing defect, also
    # in phase1: NX_EXIT reset SP past the popped frame and
    # abandoned the dispatch return address, so a comma-named
    # loop that CONTINUED returned into frame bytes).  NEXT
    # with a list closes loops innermost-first; a variable
    # with no live frame is still ?NF.
    ("L", "10 S=0: FOR I=1 TO 3: FOR J=1 TO 3: S=S+1: NEXT J,I: PRINT S",
     "", None),
    ("C", "RUN", "", num(9)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    ("L", "10 S=0: FOR I%=1 TO 3: FOR J%=1 TO 3: S=S+I%*J%: NEXT J%,I%: PRINT S",
     "", None),
    ("C", "RUN", "", num(36)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    ("L", "10 S=0: FOR I=1 TO 3: FOR J%=1 TO 3: S=S+1: NEXT J%,I: PRINT S",
     "", None),
    ("C", "RUN", "", num(9)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    ("L", "10 S=0: FOR I%=1 TO 3: FOR J=1 TO 3: S=S+1: NEXT J,I%: PRINT S",
     "", None),
    ("C", "RUN", "", num(9)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    ("L", "10 FOR I=1 TO 1: NEXT I,J", "", None),
    ("C", "RUN", "", "?NF ERROR IN  10\r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- R2-M4 Part A: function type rules (D6) and VAL
    # (D10).  Type observability: an INT result prints in
    # integer form and stays INT through + - *, an FP result
    # of the same value prints in E form -- the checks below
    # discriminate on exactly that where digits alone cannot.
    # SGN: INT in -> INT out; FP in -> FP out.
    ("C", "A%=-5: PRINT SGN(A%)+2147483647", "", num(2147483646)),
    ("C", "PRINT SGN(-5.5)+2147483647", "",
     " 2.14748365E+09 \r\n\r\nREADY.\r\n"),
    # INT: identity on INT; FP in -> FP floor result.
    ("C", "A%=2000000000: PRINT INT(A%)", "", num(2000000000)),
    ("C", "PRINT INT(2000000000.5)", "",
     " 2E+09 \r\n\r\nREADY.\r\n"),
    ("C", "PRINT INT(-2.5)", "", "-3 \r\n\r\nREADY.\r\n"),
    # ABS: preserves INT; -2147483648 promotes to exact FP.
    ("C", "A%=-2000000000: PRINT ABS(A%)", "", num(2000000000)),
    ("C", "A%=-2147483648: PRINT ABS(A%)", "",
     " 2.14748365E+09 \r\n\r\nREADY.\r\n"),
    # PEEK/DEEK return INT and join \ directly (byte 200 sits
    # at 36865 after the big-endian DOKE; DEEK reads the word).
    ("C", "DOKE 36864,200: PRINT PEEK(36865)\\3", "", num(66)),
    ("C", "PRINT DEEK(36864)\\3", "", num(66)),
    # LEEK: INT form at $7FFFFFFF (the FP form was E notation).
    ("C", "LOKE 36864,2147483647: PRINT LEEK(36864)", "",
     num(2147483647)),
    # VAL (D10): D1 rule on the parsed text.
    ("C", 'PRINT VAL("2147483647")', "", num(2147483647)),
    ("C", 'PRINT VAL("1.5")', "", " 1.5 \r\n\r\nREADY.\r\n"),
    ("C", 'PRINT VAL("12A")', "", num(12)),   # prefix parse
    # ---- R2-M4 Part B: % array elements load as INT (D7).
    # The type comes from the array name's % mark in PTRGET
    # (INTFLG), not from a per-element tag: the element slot
    # IS the int32.  FP array elements load as FP (M1 checks
    # above cover the tagged-FP-element round trip).
    ("C", "DIM A%(3): A%(1)=2000000000: A%(2)=7: PRINT A%(1)+1",
     "", num(2000000001)),
    ("C", "PRINT A%(1)\\7", "", num(285714285)),
    ("C", "PRINT A%(2)+A%(1)", "", num(2000000007)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- R2-M4 Part B: USR type tag (D8).  The vector still
    # points at logical $6000, which currently holds the EXT1
    # constant-2.0 routine: a legacy routine that never
    # touches FACTYP returns its FAC as FP even for an INT
    # argument (2000000000 would come back as-is if the stale
    # entry tag were honoured instead).
    ("C", "PRINT USR(2000000000)", "", num(2)),
    # Echo-tag routine (assembled with asm68k-py at $6000;
    # reads USRTYP at physical $101F2, returns INT 2000000000
    # for an INT argument, INT 7 for an FP argument, by
    # setting FACINT + FACTYP=1 at $101E8/$101F0):
    ("L", "10 FOR I=0 TO 31: READ B: POKE 24576+I,B: NEXT I",
     "", None),
    ("L", "20 DATA 112,7,74,57,0,1,1,242,103,6,32,60,119,53,"
          "148,0,35,192,0,1,1,232,19,252,0,1,0,1,1,240,78,117",
     "", None),
    ("C", "RUN", "", "\r\nREADY.\r\n"),
    ("C", "PRINT USR(5)", "", num(2000000000)),
    ("C", "PRINT USR(1.5)", "", num(7)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # Increment routine (FACINT := FACINT+1, FACTYP := 1):
    # an INT result whose shadow USRFN rebuilds, so +1 stays
    # integer all the way.
    ("L", "10 FOR I=0 TO 23: READ B: POKE 24576+I,B: NEXT I",
     "", None),
    ("L", "20 DATA 32,57,0,1,1,232,82,128,35,192,0,1,1,232,"
          "19,252,0,1,0,1,1,240,78,117", "", None),
    ("C", "RUN", "", "\r\nREADY.\r\n"),
    ("C", "PRINT USR(41)", "", num(42)),
    ("C", "PRINT USR(41)+1", "", num(43)),
    ("C", "PRINT USR(2000000000)", "", num(2000000001)),
    ("C", "NEW", "", "\r\nREADY.\r\n"),
    # ---- CTRL-C break still works (run_break session A) ----
    ("C", "NEW", "", None),
    ("L", "10 GET A$", "", None),
    ("L", "20 GOTO 10", "", None),
    ("C", "RUN", "Z\x03", "\r\nBREAK IN  10\r\nREADY.\r\n"),
]



# A1 acceptance session (R1-M1): single array blocks over 64KB,
# multi-dimension 32-bit counts/offsets, GC with big arrays
# present, and logical addresses beyond the old 64KB page.
# Groups are separated by NEW to stay inside the 129024-byte
# space.  A silent direct command's region is "\r\nREADY.\r\n".
SIL = "\r\nREADY.\r\n"
SESSION2 = [
    ("C", "PRINT DEEK(65536)", "", num(0)),     # empty program text
    # R2-M1 (D7): % elements are 4 bytes now, so the >64KB-block
    # array is A%(200,100) = 20301 el, 81212 B (the R1 form,
    # A%(200,200) at 2 bytes/element, would need 161618 B at
    # 4 bytes -- more than the whole 129024-byte space: ?OM).
    ("C", "DIM A%(200,100)", "", SIL),          # 20301 el, 81212 B
    ("C", "A%(200,100)=12345: PRINT A%(200,100)", "", num(12345)),
    ("C", "A%(0,0)=7: A%(100,100)=-999: "
          "PRINT A%(0,0); A%(100,100); A%(200,100)",
     "", " 7 -999  12345 \r\n\r\nREADY.\r\n"),
    ("C", "DIM D%(10)", "", SIL),
    ("C", "D%(10)=99: PRINT D%(10); A%(200,100)", "",
     " 99  12345 \r\n\r\nREADY.\r\n"),
    ("C", 'T$="": FOR I=1 TO 50: T$=T$+"XYZW": NEXT: PRINT LEN(T$)',
     "", num(200)),
    ("C", "PRINT A%(200,100)", "", num(12345)),   # survived GC churn
    ("C", "NEW", "", SIL),
    ("C", "DIM B(15000)", "", SIL),             # 90014-byte FP block
    ("C", "B(15000)=1.5: B(0)=2.5: PRINT B(15000); B(0)", "",
     " 1.5  2.5 \r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", SIL),
    ("C", "DIM E(200,100)", "", SIL),           # 20301 el, 121814 B
    ("C", "E(200,100)=3.25: E(0,0)=8: E(199,3)=33: "
          "PRINT E(200,100); E(0,0); E(199,3)", "",
     " 3.25  8  33 \r\n\r\nREADY.\r\n"),
    ("C", "NEW", "", SIL),
    ("C", "DIM S$(100)", "", SIL),
    ("C", 'S$(100)="BIG": S$(0)="S": PRINT S$(100); S$(0)', "",
     "BIGS\r\n\r\nREADY.\r\n"),
    ("C", "LOKE 1048576,305419896: PRINT LEEK(1048576)", "",
     num(305419896)),                           # logical $100000
    ("C", "DOKE 1048577,4660: PRINT DEEK(1048577)", "", num(4660)),
    ("C", "PRINT DEEK(-1)", "", IQ_R),          # still an error
]


def fed_bytes(entry):
    if entry[0] == "L":
        return entry[1] + "\r"
    return entry[1] + "\r" + entry[2]


def regions68(tx: str, entries):
    """Per-entry response regions, run_break.py's convention."""
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


def bsd_sum(data: bytes) -> int:
    s = 0
    for b in data:
        s = ((s >> 1) | ((s & 1) << 15)) & 0xFFFF
        s = (s + b) & 0xFFFF
    return s


def sum16(data: bytes) -> int:
    s = 0
    for b in data:
        s = (s + b) & 0xFFFF
    return s


def run_session(emu, image, entries, script, out, tag, check,
                until="ZZX1END", maxcycles=1_000_000_000):
    script.write_bytes(
        "".join(fed_bytes(e) for e in entries).encode("latin-1"))
    cmd = [emu, "--image", str(image),
           "--masters", str(SIM / "masters"),
           "--script", str(script), "--out", str(out),
           "--until", until, "--settle", "2000000",
           "--maxcycles", str(maxcycles)]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       timeout=1800)
    print(f"emu[{tag}]:", r.stdout.strip(), f"(rc={r.returncode})")
    check(f"{tag}: emu exit code 0 (until-string seen)",
          r.returncode == 0)
    return out.read_bytes().decode("latin-1")


def asciiart_check(emu, image, tag, check):
    prog = [ln for ln in BAS.read_text().splitlines() if ln.strip()]
    lines = prog + ["RUN", 'PRINT "ZZX1";"END"']
    script = HERE / f"ext1-{tag}-art.script"
    out = HERE / f"ext1-{tag}-art.out"
    txb = run_session(emu, image,
                      [("L", ln, "", None) for ln in lines],
                      script, out, f"{tag} ASCIIART", check,
                      maxcycles=5_000_000_000)
    txb = txb.encode("latin-1")
    golden = GOLDEN_PATH.read_bytes()
    pic = None
    i = txb.find(b"RUN\r\n")
    if i >= 0:
        pic = txb[i + 5: i + 5 + GOLDEN_LEN]
    ok = pic is not None and len(pic) == GOLDEN_LEN and pic == golden
    detail = ""
    if ok:
        detail = (f"sum16={sum16(pic)} crc32="
                  f"{zlib.crc32(pic) & 0xFFFFFFFF:08X}")
    elif pic is not None and len(pic) == GOLDEN_LEN:
        k = next(n for n in range(GOLDEN_LEN) if pic[n] != golden[n])
        detail = (f"first mismatch at byte {k}: "
                  f"got {pic[k]:02X}, want {golden[k]:02X}")
    else:
        detail = "picture not extracted"
    check(f"{tag}: ASCIIART picture == golden (byte exact)", ok,
          detail)


def main() -> int:
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok))
        print(("PASS" if ok else "FAIL"), "-", name, detail)

    # ---- 1. build the rd variant ----
    r = subprocess.run([sys.executable, str(HERE / "build.py"), "rd"],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    check("build.py rd exit 0", r.returncode == 0)
    data = RD_BIN.read_bytes()
    print(f"INFO - RD msbasic68k-rd.bin: {len(data)} bytes, "
          f"BSD sum {bsd_sum(data)}")

    # ---- 2. branch checkers on the EXT listings ----
    for lst, binf in ((RD_LST, RD_BIN),):
        for chk in ("check_branches.py", "check_short_branches.py"):
            target = binf
            r = subprocess.run([sys.executable, str(HERE / chk),
                                str(lst), str(target)],
                               capture_output=True, text=True)
            tail = (r.stdout + r.stderr).strip().splitlines()
            check(f"branch checker {chk} on {lst.name}",
                  bool(tail) and tail[-1].startswith("0 bad"),
                  tail[-1] if tail else "(no output)")

    # ---- 3. EXT-SIM spec session ----
    entries = SESSION + [("C", ENDMARK, "", None)]
    tx = run_session(EMU, EXT_BIN, entries,
                     HERE / "ext1.script", HERE / "ext1.out",
                     "ext-sim spec", check)
    check("rd: banner + 129024 BYTES FREE at boot",
          "### COMMODORE BASIC ###" in tx
          and "129024 BYTES FREE" in tx)
    got = regions68(tx, entries)
    check("ext-sim: endmark region",
          got[-1] == "ZZX1END\r\n\r\nREADY.\r\n", f"got {got[-1]!r}")
    for idx, e in enumerate(entries):
        if e[0] == "L" or e[3] is None:
            continue
        check(f"ext-sim: [{e[1]}]", got[idx] == e[3],
              f"got {got[idx]!r} want {e[3]!r}"
              if got[idx] != e[3] else "")

    # ---- 4. EXT-SIM ASCIIART ----
    asciiart_check(EMU, EXT_BIN, "ext-sim", check)

    # ---- 5. A1 acceptance session ----
    entries2 = SESSION2 + [("C", ENDMARK, "", None)]
    tx2 = run_session(EMU, RD_BIN, entries2,
                      HERE / "rd-a1.script", HERE / "rd-a1.out",
                      "rd A1", check)
    got2 = regions68(tx2, entries2)
    check("rd A1: endmark region",
          got2[-1] == "ZZX1END\r\n\r\nREADY.\r\n",
          f"got {got2[-1]!r}")
    for idx, e in enumerate(entries2):
        if e[0] == "L" or e[3] is None:
            continue
        check(f"rd A1: [{e[1][:40]}]", got2[idx] == e[3],
              f"got {got2[idx]!r} want {e[3]!r}"
              if got2[idx] != e[3] else "")

    n_fail = sum(1 for _, ok in checks if not ok)
    print(f"\n{len(checks) - n_fail}/{len(checks)} checks PASS")
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
