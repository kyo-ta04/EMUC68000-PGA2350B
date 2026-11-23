; Equates -- variant-independent.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; ACIA, sizes, virtual-ZP slots, token values.

ACIADAT EQU     $80E000         ; ACIA data register
ACIASTA EQU     $80E001         ; ACIA status (bit0 RDRF, bit1 TDRE)

BUFLEN  EQU     256             ; line input buffer length
                                ; (R1 port work: was 128, the
                                ; Phase 1 value -- ASM.BAS has
                                ; 140-column lines, so BUF also
                                ; moved out of the packed ZP to
                                ; $00A000; see BUF below)
DSCLEN  EQU     6               ; M5e: string descriptor size and
                                ; layout: +0 data pointer (long),
                                ; +4 length (byte), +5 pad.  The
                                ; M1-M5d form (length at +0, pointer
                                ; at +1) put a longword at an odd
                                ; offset inside every descriptor --
                                ; an address error on a real 68000.
ZPSIZE  EQU     $0332           ; bytes of ZP mirror to clear
                                ; (M5b: raised from $01C0 to cover
                                ; the M5b slots at $1C0 and up;
                                ; M5c: raised to cover SUBBUF and
                                ; the M5c slots at $300 and up;
                                ; M5g: +2 for PUSHBK at $330)

; --- virtual zero page slots (absolute = ZPBASE + original offset) ---
CHARAC  EQU     ZPBASE+$0A
ENDCHR  EQU     ZPBASE+$0B
COUNT   EQU     ZPBASE+$0C
DIMFLG  EQU     ZPBASE+$0D
VALTYP  EQU     ZPBASE+$0E
INTFLG  EQU     ZPBASE+$0F
DORES   EQU     ZPBASE+$10
SUBFLG  EQU     ZPBASE+$11
INPFLG  EQU     ZPBASE+$12
TANSGN  EQU     ZPBASE+$13
LINNUM  EQU     ZPBASE+$14
BUF     EQU     $00A000         ; R1: the line input buffer,
                                ; BUFLEN bytes at a fixed side
                                ; address (the ZP slot it held
                                ; through Phase 1, ZPBASE+$17, is
                                ; 128 bytes boxed in by FRETOP/FAC
                                ; and cannot grow; ASM.BAS needs
                                ; 140+).  All references go through
                                ; this equate and BUFM1.
BUFM1   EQU     BUF-1           ; M5b: the byte just before BUF.
                                ; INPUT plants a ',' sentinel here
                                ; (the original stores 44 at BUF-1)
                                ; so the data pointer can start at
                                ; BUFM1 and the first item needs no
                                ; line fetch.
TEMPPT  EQU     ZPBASE+$190     ; M5a: 4-byte pointer (was a byte
                                ; offset at $97 in M1-M4, when the
                                ; temp stack did not exist yet)
LASTPT  EQU     ZPBASE+$194     ; M5a: 4-byte pointer (was $98)
TMPDSC  EQU     ZPBASE+$180     ; M5a: the temporary descriptor
                                ; stack itself, 3 descriptors of
                                ; DSCLEN bytes (NUMTMP=3).  It cannot sit
                                ; at the original TEMPST offset ($9C):
                                ; only 9 bytes remain before INDEX1.
                                ; The old TEMPST slot at $9C is unused
                                ; from M5a on.
INDEX1  EQU     ZPBASE+$A5
INDEX2  EQU     ZPBASE+$A9
RESHO   EQU     ZPBASE+$AD
TXTTAB  EQU     ZPBASE+$B2
VARTAB  EQU     ZPBASE+$B6
ARYTAB  EQU     ZPBASE+$BA
STREND  EQU     ZPBASE+$BE
FRETOP  EQU     ZPBASE+$C2
FRESPC  EQU     ZPBASE+$C6
MEMSIZ  EQU     ZPBASE+$CA
CURLIN  EQU     ZPBASE+$CE
OLDLIN  EQU     ZPBASE+$D0
OLDTXT  EQU     ZPBASE+$D2
DATLIN  EQU     ZPBASE+$D6
DATPTR  EQU     ZPBASE+$D8
INPPTR  EQU     ZPBASE+$DC
VARNAM  EQU     ZPBASE+$E0
VARPNT  EQU     ZPBASE+$E2
FORPNT  EQU     ZPBASE+$E6
OPPTR   EQU     ZPBASE+$EA
OPMASK  EQU     ZPBASE+$EE
; --- M5e realignment (Phase 1.5 Step 1): every slot from DEFPNT
; on sits one byte higher than in M1-M5d, so that each multi-byte
; slot starts at an EVEN offset (the M1-M5d packing put the whole
; DEFPNT..CURLINP run, FAC+4, RESULT and FORSP on odd offsets --
; word/long accesses there are address errors on a real 68000).
; All references are symbolic, and FACOV/FACSIGN/ARGEXT stay
; relative to FAC/ARG, so only these EQU values change. ---
DEFPNT  EQU     ZPBASE+$F0
DSCPNT  EQU     ZPBASE+$F4
HIGHDS  EQU     ZPBASE+$F8
HIGHTR  EQU     ZPBASE+$FC
LOWDS   EQU     ZPBASE+$100
LOWTR   EQU     ZPBASE+$104
FAC     EQU     ZPBASE+$108     ; +0 exp, +1..+4 mantissa,
                                ; +5 FACOV (extension), +6 FACSIGN, +7 spare
ARG     EQU     ZPBASE+$110     ; +0 exp, +1..+4 mantissa, +5 ARGEXT
ARISGN  EQU     ZPBASE+$116
FACOV   EQU     FAC+5
FACSIGN EQU     FAC+6
ARGEXT  EQU     ARG+5
FBUFPT  EQU     ZPBASE+$118
TXTPTR  EQU     ZPBASE+$11C
CURLINP EQU     ZPBASE+$120
; --- M3 additions (past the original layout) ---
RESULT  EQU     ZPBASE+$124     ; 5 bytes: FDIV/FADD work field
RESULT2 EQU     ZPBASE+$12A     ; 5 bytes: FMULT multiplier copy / NEXT copies
MANTMP  EQU     ZPBASE+$1D0     ; 4 bytes: M5e mantissa-long staging
                                ; (the pack's MOVE.L at FAC+1/ARG+1
                                ; is odd-addressed; loads/stores go
                                ; through this even scratch instead)
FBUFF   EQU     ZPBASE+$130     ; 48 bytes: FOUT output buffer
EXPSGN  EQU     ZPBASE+$160     ; FIN: exponent sign flag
TMPEXP  EQU     ZPBASE+$161     ; FIN/FOUT: temp exponent
CPRMASK EQU     ZPBASE+$162     ; evaluator: relational mask (performed)
CPRTYP  EQU     ZPBASE+$163     ; evaluator: relational mask (building)
LASTOP  EQU     ZPBASE+$164     ; evaluator: last operator index
POSX    EQU     ZPBASE+$165     ; PRINT: current column
FORSP   EQU     ZPBASE+$166     ; 4 bytes: FOR frame stack pointer
FORRET  EQU     ZPBASE+$170     ; 4 bytes: FORH's parked return addr
NEXTRET EQU     ZPBASE+$174     ; 4 bytes: NEXTH's parked return addr
                                ; (the FOR frame is pushed onto the
                                ; CPU stack, burying the JSR dispatch
                                ; return address; FORH/NEXTH therefore
                                ; exit by JMP through these slots.
                                ; The 6502 original dispatches by JMP
                                ; and never has this problem.)
SGNCPR  EQU     ZPBASE+$16A     ; FADD: sign-compare byte
; --- M5a additions: string heap / GOSUB bookkeeping ---
DSCBUF  EQU     ZPBASE+$198     ; 6 bytes: staging descriptor (the
                                ; original stages descriptors in FAC
                                ; itself; this port's FAC is busy
                                ; holding the descriptor ADDRESS in
                                ; FAC+4..7, so PUTNEW's source lives
                                ; here instead)
STRNG1  EQU     ZPBASE+$1A0     ; 4 bytes: CAT's left descriptor addr
ARGDSC  EQU     ZPBASE+$1A4     ; 4 bytes: stacked operand's string
                                ; descriptor address (evaluator frame)
GOSUBSP EQU     ZPBASE+$1A8     ; 4 bytes: GOSUB frame list head
                                ; (STACKTOP = no frames, as FORSP)
GOSRET  EQU     ZPBASE+$1AC     ; 4 bytes: RETURNH's parked return
GCIDX   EQU     ZPBASE+$1B0     ; GC: scan cursor (INDEX role)
GCLOW   EQU     ZPBASE+$1B4     ; GC: best candidate data ptr (LOWTR)
GCFN    EQU     ZPBASE+$1B8     ; GC: candidate's slot address
                                ; (FNCNAM role; 0 = none found)
GCDSC   EQU     ZPBASE+$1BC     ; GC: descriptor offset in its slot
GCSW    EQU     ZPBASE+$1BE     ; GETSPA: "GC already ran" flag byte
                                ; (the original's DATAFLG bit)
; --- M5b additions: INPUT/READ/CONT bookkeeping ---
VARTXT  EQU     ZPBASE+$1C0     ; 4 bytes: saved variable-list
                                ; pointer (the original's VARTXT)
                                ; while TXTPTR walks the data side
OLDCIP  EQU     ZPBASE+$1C4     ; 4 bytes: CURLINP saved alongside
                                ; OLDTXT/OLDLIN for CONT (the port's
                                ; EXEC needs the line address, which
                                ; the original recomputes from
                                ; TXTPTR; this port keeps it)
INPST   EQU     ZPBASE+$1C8     ; 4 bytes: INPUT statement restart
                                ; pointer (A6 at the char after the
                                ; INPUT token), for ?REDO FROM START
CONTMD  EQU     ZPBASE+$1CC     ; 1 byte: CONT resume mode: 0 = A6
                                ; sits AT a terminator (STOP/END:
                                ; resume via EXEC), 1 = A6 sits one
                                ; byte BEFORE the statement to
                                ; re-run (statement-boundary save:
                                ; resume via FETCH).  The original
                                ; needs no such flag: its TXTPTR
                                ; convention (points at the last
                                ; char read) unifies the two cases.
GETBUF  EQU     ZPBASE+$1CD     ; 2 bytes: GET's one-character
                                ; buffer (the char, then a NUL)
FOUTIDX EQU     ZPBASE+$16B     ; FOUT: write index (STRNG2)
; --- M5c additions: arrays and DEF FN ---
FNPARSE EQU     ZPBASE+$16C     ; 1 byte: GETFNM parse-only flag:
                                ; PTRGET parses the name, then
                                ; returns at PT_FNRET without
                                ; touching the scalar area (the FN
                                ; record lives in the side table)
ARYBLK  EQU     ZPBASE+$178     ; 4 bytes: array block base during
                                ; PTRGET's array search/build/index
ARYDPT  EQU     ZPBASE+$17C     ; 2 bytes: array-path nesting depth
                                ; (indexes SUBBUF levels; nested
                                ; array references in subscripts)
ELMSZ   EQU     ZPBASE+$17E     ; 2 bytes: element size of the
                                ; array PTRGET is currently serving
VHASH   EQU     $008000
LCACHE  EQU     $00C000         ; R1-M3: literal cache; R2-M1:
                                ; 128 entries x 32 bytes (same
                                ; 4KB frame, LTABLE stays $D000)
LTABLE  EQU     $00D000         ; R1-M4: line table, 2048
                                ; entries x 6 bytes {number (2),
                                ; address (4)} -- $D000..$FFFF
LTCOUNT EQU     ZPBASE+$1D4     ; R1-M4: 2 bytes: entries in use
LTVALID EQU     ZPBASE+$1D6     ; R1-M4: 1 byte: table is current
LTMID   EQU     ZPBASE+$1D8     ; R1-M4: 2 bytes: search midpoint
LTSV    EQU     ZPBASE+$1E0     ; R1-M4: 8 bytes: FNDLIN saves
                                ; D1/D2 here (no MOVEM in the
                                ; ASM.BAS subset this port keeps)
; --- GC-C1 additions (2026-11-23): the fast collector's work
; areas, in the mirror region between the ZP page and the FN
; table ($010332..$017FFF is otherwise unused in every variant
; layout; on the hw layouts these are plain RAM below the code).
; Program-invisible: no variable, array or string ever lives
; here, and FRE/CLEAR do not account them.
GCCTAB  EQU     $010E00         ; GC-C1: radix count/position
                                ; table, 256 words ($010E00-010FFF)
GCLIST  EQU     $011000         ; GC-C1: work list, two ping-pong
                                ; halves of GCLCAP entries x 8
                                ; bytes {data ptr, descriptor
                                ; address} -- $011000..$017FFF
GCLCAP  EQU     1792            ; GC-C1: entries per list half;
                                ; a live set larger than this
                                ; falls back to the original
                                ; collector (see GCNEW)
; --- R2-M1 additions: the integer type foundation (D1/D5/D9) ---
; Dual representation: FACTYP=1 (INT) means FACINT holds the
; exact int32 value AND FAC holds its exact FP conversion (this
; port's 32-bit-mantissa FP represents every int32 exactly).
; FACTYP=0 (FP) means FACINT is meaningless.  VALTYP stays the
; binary numeric/string flag it has always been -- integerness
; lives ONLY here, never in VALTYP (every VALTYP test in the
; interpreter is a BMI/BPL sign test, and LET packs
; VALTYP:INTFLG into one word).
FACINT  EQU     ZPBASE+$1E8     ; R2-M1: 4 bytes: FAC's int32 value
ARGINT  EQU     ZPBASE+$1EC     ; R2-M1 reservation, live in
                                ; R2-M2: 4 bytes: ARG's int32 value
                                ; (restored by PERFORM2 from the
                                ; evaluator frame; same dual
                                ; representation contract as FACINT)
FACTYP  EQU     ZPBASE+$1F0     ; R2-M1: 1 byte: 0 = FP, 1 = INT
ARGTYP  EQU     ZPBASE+$1F1     ; R2-M1 reservation, live in
                                ; R2-M2: 1 byte: ARG's type tag
                                ; (0 = FP, 1 = INT)
USRTYP  EQU     ZPBASE+$1F2     ; R2-M4 (D8): 1 byte: the USR
                                ; argument's type tag, mirrored
                                ; from FACTYP by USRFN before it
                                ; calls the user routine (which
                                ; reads it at logical $1F2).  The
                                ; routine declares an INT result
                                ; by setting FACTYP=1 + FACINT
                                ; before its RTS; USRFN clears
                                ; FACTYP before the call, so a
                                ; legacy routine that never
                                ; touches it returns FP in FAC,
                                ; exactly as before R2.
FININT  EQU     ZPBASE+$1F4     ; R2-M1: 4 bytes: FIN's parallel
                                ; int32 accumulator (D1)
FINFLG  EQU     ZPBASE+$1F8     ; R2-M1: 1 byte: FIN's literal is
                                ; still an int32 candidate
; --- R2-M3 additions: integer FOR (D4) build-time state ---
FORVINT EQU     ZPBASE+$1F9     ; R2-M3: 1 byte: FORH's variable
                                ; is a % variable
FORLINT EQU     ZPBASE+$1FA     ; R2-M3: 1 byte: the FOR limit's
                                ; FACTYP (1 = INT)
FORSINT EQU     ZPBASE+$1FB     ; R2-M3: 1 byte: the FOR step's
                                ; FACTYP (1 = INT; for a default
                                ; step, copied from FORLINT)
FORILIM EQU     ZPBASE+$1FC     ; R2-M3: 4 bytes: the FOR limit's
                                ; FACINT (valid when FORLINT=1)
INTTAG  EQU     $49             ; R2-M1: the tag byte ('I') stored
                                ; at value-field offset +5 of a
                                ; plain scalar/array element whose
                                ; packed FP value is an exact int32
                                ; held as an INT (D5).  FP packed
                                ; values use only +0..+4 and string
                                ; descriptors use +5 as pad, so the
                                ; byte is free for numeric slots;
                                ; FRM_VARIABLE validates it by
                                ; converting the FP shadow back, so
                                ; a stale tag can never invent a
                                ; value the FP shadow does not hold.
SUBBUF  EQU     ZPBASE+$200     ; 256 bytes: subscript workspace,
                                ; 8 levels of 32 bytes (one per
                                ; array-path nesting depth):
                                ; +0 ndims byte, +2.. 15 subscript
                                ; words in declaration order
FNTOP   EQU     ZPBASE+$300     ; 4 bytes: end of the FN definition
                                ; table (next free record)
GCEND   EQU     ZPBASE+$304     ; 4 bytes: GC scan 3: end of the
                                ; array block currently being walked
FOUTEXP EQU     ZPBASE+$16C     ; FOUT: decimal exponent (EXPON)
FOUTIND EQU     ZPBASE+$16D     ; FOUT: digit/dot counter (INDX)
FINSGN  EQU     ZPBASE+$16E     ; FIN: negative flag (SERLEN)
CPRSTR  EQU     ZPBASE+$16F     ; evaluator: relational string flag
; --- M5d additions: math pack temps, RND state, POKE/WAIT ---
TEMPF1  EQU     ZPBASE+$308     ; 5 bytes: packed FP temp 1
                                ; (POLYX saves its input here;
                                ; TAN's argument rides it too --
                                ; the original shares it the same
                                ; way)
TEMPF2  EQU     ZPBASE+$30E     ; 5 bytes: packed FP temp 2
                                ; (POLY's saved argument)
TEMPF3  EQU     ZPBASE+$314     ; 5 bytes: packed FP temp 3
                                ; (FPWRT's saved exponent; TAN's
                                ; saved sine)
POLYPT  EQU     ZPBASE+$31A     ; 4 bytes: polynomial pointer
DEGREE  EQU     ZPBASE+$31E     ; 1 byte: POLY's counter
RNDX    EQU     ZPBASE+$320     ; 5 bytes: RND state (packed);
                                ; INIT seeds it like the original's
                                ; cold start (see INIT)
OLDOV   EQU     ZPBASE+$325     ; 1 byte: EXP's saved extension
FPWNEG  EQU     ZPBASE+$326     ; 1 byte: FPWRT: negate-result flag
POKER   EQU     ZPBASE+$328     ; 4 bytes: PEEK/POKE/WAIT address
                                ; (physical; the original's POKER
                                ; holds the 16-bit logical address)
ANDMSK  EQU     ZPBASE+$32C     ; 1 byte: WAIT's AND mask
EORMSK  EQU     ZPBASE+$32D     ; 1 byte: WAIT's XOR mask
INTEGR  EQU     ZPBASE+$32E     ; 1 byte: QINT's low byte, kept
                                ; by INTFN (the original's
                                ; INTEGR = CHARAC, set by INT
                                ; from FACLO right after QINT)
PUSHBK  EQU     ZPBASE+$330     ; M5g: console pushback, 1 word:
                                ; +0 valid flag (byte, nonzero =
                                ; occupied), +1 the pushed-back
                                ; character.  BRKCHK stores here;
                                ; MONRDKEY / MONPOLKEY drain it
                                ; before the ACIA (see below)
; --- GC-C1 ZP scratch (past ZPSIZE and past EXT1's USRVEC
; word at +$334; GCNEW initialises all three on every entry,
; so the INIT clear need not cover them)
GCCNT   EQU     ZPBASE+$340     ; GC-C1: 4 bytes: work-list
                                ; entries collected this GARBAG
GCAPP   EQU     ZPBASE+$344     ; GC-C1: 4 bytes: work-list
                                ; append pointer during the
                                ; build scan
GCOVF   EQU     ZPBASE+$348     ; GC-C1: 1 byte: build overflowed
                                ; the work list (fall back)

; --- token values used by name ---
DATATK  EQU     $83
REMTK   EQU     $8F
PRINTK  EQU     $99
NEWK    EQU     $A2
MINUTK  EQU     $AB
MODTK   EQU     $D2             ; R2-M3: MOD operator token (D2);
                                ; appended to RESLST after ELSE
                                ; ($D1) so no existing token moves
IDIVTK  EQU     $D3             ; R2-M3: '\' integer-division
                                ; operator token (D2)

