; msbasic68k.asm -- file header.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; Variant-neutral front matter (history, conventions).

;=====================================================================
; MS-BASIC for MC68000 -- Phase 1 / M1+M2
;
; A faithful-in-spirit port of Microsoft BASIC M6502 v1.1
; (microsoft/BASIC-M6502, MIT), REALIO=3 (Commodore PET) configuration,
; to the MC68000, following phase1-kickoff-2026-11-18.md.  Written in
; the ASM.BAS instruction subset, no macros, so a later self-assembly
; stays possible.  Assembled on the PC with asm68k-py, run in the
; Musashi simulator.
;
; M1 scope: reset vectors + INIT, machine layer (MONCOUT / MONRDKEY /
; ISCNTC on the ACIA), banner + BYTES FREE + READY loop, line input.
; M2 scope: CHRGET/CHRGOT, CRUNCH (tokenizer), program storage,
; LINGET, statement dispatch skeleton.  Real statements: NEW, LIST,
; RUN, CLEAR, PRINT (string literals only), GOTO, END, REM, DATA
; (skip).  Everything else dispatches to ?SN ERROR.  LET and numeric
; expressions arrive in M3.
; M3 scope: evaluator, FP scalar variables, math pack core
; (FADD/FSUB/FMULT/FDIV, FIN/FOUT, INT/ABS/SGN), FOR/NEXT, numeric
; PRINT.
; M4 scope: IF...THEN, CHR$, string literals as expressions,
; PRINT completed (comma zones with the original's constants).
; Phase 1 acceptance: ASCIIART.BAS output byte-identical to the
; CBM BASIC 2 golden.
; M5a scope: GOSUB/RETURN, string variables, CAT, string
; comparison, GETSPA/GARBAG, FRE, 80-column terminal model.
; M5b scope: DATA/READ/RESTORE, INPUT (prompt, REDO, ??,
; ?EXTRA IGNORED), ON...GOTO/GOSUB, STOP/CONT, GET.
; M5c scope: arrays (DIM, implicit DIM, FP/integer/string
; elements, GC array scan), integer variables verified and
; completed (AYINT carries the original's short-constant
; -32768 bug), DEF FN / FN (numeric only, as in the original).
; M5d scope: the rest of the function table (FPWRT ^, SQR,
; LOG, EXP, SIN/COS/TAN/ATN, RND, POS, PEEK, LEN, STR$, VAL,
; ASC, LEFT$/RIGHT$/MID$) and the POKE / WAIT statements.
; With M5d the Phase 1 faithful port is complete: the only
; remaining stubs are the channel/file statements (INPUT#,
; PRINT#, LOAD, SAVE, VERIFY, CMD, SYS, OPEN, CLOSE) and USR,
; all ?SN ERROR, as decided for Phase 1.
;
; Memory layout: this source is built from parts (build.py);
; the layout comment and the address EQUs live in the config
; part (parts/10-config-sim.asm / parts/10-config-hw.asm),
; selected per variant.
;
; Program line format (all line start addresses are EVEN, so word
; and long accesses never fault on the 68000):
;   +0  link (4 bytes, absolute address of next line; the last line
;       points at the end marker, whose link field is 0)
;   +4  line number (2 bytes, 0-63999)
;   +6  tokenized text, terminated by a 0 byte
;   ... one pad byte if the total length would be odd
; The end marker is just the 4-byte zero link at VARTAB-4.
; Links are absolute and are repaired by LNKPRG after every edit
; (the original re-links after edits too; it stores 2-byte links).
;
; Tokens: $80 up, assigned in RESLST order, which is the original's
; REALIO=3 order and therefore identical to CBM BASIC 2:
;   $80 END   $81 FOR   $82 NEXT  $83 DATA  $84 INPUT# $85 INPUT
;   $86 DIM   $87 READ  $88 LET   $89 GOTO  $8A RUN    $8B IF
;   $8C RESTORE $8D GOSUB $8E RETURN $8F REM $90 STOP  $91 ON
;   $92 WAIT  $93 LOAD  $94 SAVE  $95 VERIFY $96 DEF  $97 POKE
;   $98 PRINT# $99 PRINT $9A CONT $9B LIST  $9C CLR   $9D CMD
;   $9E SYS   $9F OPEN  $A0 CLOSE $A1 GET   $A2 NEW
;   $A3 TAB(  $A4 TO    $A5 FN    $A6 SPC(  $A7 THEN  $A8 NOT
;   $A9 STEP  $AA +     $AB -     $AC *     $AD /     $AE ^
;   $AF AND   $B0 OR    $B1 >     $B2 =     $B3 <
;   $B4 SGN   $B5 INT   $B6 ABS   $B7 USR   $B8 FRE   $B9 POS
;   $BA SQR   $BB RND   $BC LOG   $BD EXP   $BE COS   $BF SIN
;   $C0 TAN   $C1 ATN   $C2 PEEK  $C3 LEN   $C4 STR$  $C5 VAL
;   $C6 ASC   $C7 CHR$  $C8 LEFT$ $C9 RIGHT$ $CA MID$ $CB GO
; Statement tokens are $80-$A2 (STMDSP has 35 entries).
;
; Register conventions:
;   A6 = TXTPTR.  It points at the LAST character read (the original
;        keeps TXTPTR in a ZP slot; the kickoff memo moves it to a
;        register).  CHRGET advances A6 then reads; CHRGOT re-reads.
;   A6 is the only register with a permanent meaning.  Handlers may
;   clobber D0-D7/A0-A5 freely.
;
; CHRGET contract (the useful half of the original's flag contract;
; the 6502 carry-for-digit trick has no 68K equivalent, so digit
; tests are explicit at call sites):
;   CHRGET: A6 += 1, then as CHRGOT.  Spaces ($20) are skipped.
;   CHRGOT: D0.B = byte at (A6); Z=1 iff it is a terminator
;           (NUL or ':'); Z=0 otherwise.
;
; Virtual zero page: the original's page-zero variables keep the
; original ORDER and, for the pre-pointer block, the original offsets
; (REALIO=3 layout of m6502.asm lines 730-942).  Pointer slots are
; widened from 2 to 4 bytes; offsets from TXTTAB on are shifted:
;   $00 GORESTART/GOSTROUT/GOAYINT/GOGIVEAYF slots (10 bytes, unused)
;   $0A CHARAC   $0B ENDCHR   $0C COUNT    $0D DIMFLG
;   $0E VALTYP   $0F INTFLG   $10 DORES    $11 SUBFLG
;   $12 INPFLG   $13 TANSGN   $14 LINNUM(2)
;   $17 BUF (input buffer, BUFLEN bytes)
;   then TEMPPT/LASTPT/TEMPST/INDEX1/INDEX2/RESHO..RESLO,
;   TXTTAB VARTAB ARYTAB STREND FRETOP FRESPC MEMSIZ (4 bytes each),
;   CURLIN(2) OLDLIN(2) OLDTXT DATLIN(2) DATPTR INPPTR,
;   VARNAM(2) VARPNT FORPNT OPPTR OPMASK DEFPNT DSCPNT,
;   HIGHDS HIGHTR LOWDS LOWTR, FAC(8) ARG(6) ARISGN FACOV,
;   FBUFPT, TXTPTR (slot kept for layout; A6 is the live TXTPTR),
;   CURLINP (4 bytes, M2: address of the line being executed).
;=====================================================================
