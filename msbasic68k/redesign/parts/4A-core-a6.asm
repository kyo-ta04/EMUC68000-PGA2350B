
; GOTO -- LINGET the target, skip the rest of the statement
; (quote handling in the skip is an M5 refinement; the original's
; REMN is quote-aware), find the line and continue there.
GOTOH   BSR     LINGET
GTOSK   MOVE.B  (A6),D1
        BEQ   GTOF
        CMPI.B  #$3A,D1
        BEQ   GTOF
        BSR     CHRGET
        BRA   GTOSK
GTOF    BSR     FNDLIN
        BNE     USERR           ; no such line: ?US ERROR
        MOVE.W  LINNUM,CURLIN
        MOVE.L  A0,CURLINP
        LEA     5(A0),A6
        ADDQ.L  #4,SP           ; drop the FETCH return address
        BRA     FETCH

; RUN -- no argument: CLEARC and start at the first line.
; RUN <number>: CLEARC and start at that line (the original goes
; through GOTO).  An empty program just returns to READY.
RUNH    TST.B   D0
        BEQ   RUNA
        CMPI.B  #$3A,D0
        BEQ   RUNA
        CMPI.B  #$30,D0
        BCS     SNERR
        CMPI.B  #$39,D0
        BHI     SNERR
        BSR     LINGET
        BSR     CLEARC
        BSR     FNDLIN
        BNE     USERR
        MOVE.W  LINNUM,CURLIN
        MOVE.L  A0,CURLINP
        LEA     5(A0),A6
        ADDQ.L  #4,SP
        BRA     FETCH
RUNA    BSR     RUNC
        MOVEA.L TXTTAB,A0
        TST.L   (A0)
        BEQ   RUNRTS          ; empty program: nothing to run
        MOVE.W  4(A0),CURLIN
        MOVE.L  A0,CURLINP
        LEA     5(A0),A6
        ADDQ.L  #4,SP
        BRA     FETCH
RUNRTS  RTS

;---------------------------------------------------------------------
; OUTDO -- PRINT's output primitive: type the char in D0.B and
; track the column in POSX (CR resets it; LF does not move it).
; Clobbers D0 only via MONCOUT (which preserves registers).
; OUTSP -- type one space (the original's OUTSP; CBM types $1D,
; cursor-right, on its screen device -- v1.1 types a real space,
; and so do we; see m3-results.md, item Y-1).
; NUMSPC -- the byte typed after a printed number.  CBM BASIC 2
; on its screen device uses $1D (cursor right); the generic v1.1
; target uses a real space.  Kept as a one-byte constant so the
; choice (m3-results.md, item Y-1, awaiting Kyo's call) can be
; flipped in exactly one place.  Zone padding and TAB/SPC keep
; using OUTSP's real space either way.
;---------------------------------------------------------------------
NUMSPC  EQU     $20
OUTDO   CMPI.B  #$0D,D0
        BEQ   ODCR
        CMPI.B  #$0A,D0
        BEQ   ODDO
        ADDQ.B  #1,POSX
ODDO    BRA     MONCOUT
ODCR    CLR.B   POSX
        BRA     MONCOUT
OUTSP   MOVE.B  #$20,D0
        BRA   OUTDO

;---------------------------------------------------------------------
; PRINT -- the original's PRINT (print.s), M4 form: items are
; string literals, numeric/string expressions (FRMEVL + FOUT),
; ';' (pack), ',' (comma zones), TAB(/SPC(.  The comma zones use
; the original's algorithm and the REALIO=3 constants of the
; base text: zone width CLMWID=10, and at/past NCMPOS =
; ((LINLEN/CLMWID)-1)*CLMWID = ((40/10)-1)*10 = 30 a comma just
; types a CRLF and goes on with the next item (COMPRT).
; Two terminator states, as in the original: after an item (or at
; entry) a terminator ends with CRDO; right after a separator it
; ends quietly.  The state is a word on the stack: 0 = CRDO state,
; 1 = quiet state.  (A bare literal is printed directly, as in
; M2; any other string expression prints through its descriptor.)
;---------------------------------------------------------------------
PRINTH  BEQ   PRINTH_T          ; entry terminator (Z from FETCH's
        MOVE.W  #0,-(SP)        ; priming CHRGET; test BEFORE the
        BRA   PRITEM            ; MOVE, which would rewrite Z)
PRINTH_T MOVE.W #0,-(SP)        ; state = CRDO
        BRA   PRTERM
PRITEM  CMPI.B  #$A3,D0         ; TAB(
        BEQ   PRTAB
        CMPI.B  #$A6,D0         ; SPC(
        BEQ   PRTAB
        CMPI.B  #$2C,D0         ; ','
        BEQ   PRZONE
        CMPI.B  #$3B,D0         ; ';'
        BEQ   PRSEMI
        BSR     FRMEVL          ; everything else is an expression,
                                ; string literals included: the
                                ; original's PRINT2 has no literal
                                ; fast path, it FRMEVLs every item.
                                ; (M3/M4 had a PRLIT shortcut here;
                                ; it could not see a following '+',
                                ; so PRINT "A"+"B" was ?SN ERROR.
                                ; M5a removes it -- CAT makes the
                                ; evaluator path complete.)
        TST.B   VALTYP
        BMI   PRSTRG          ; string result: print via descriptor
        TST.B   FACTYP          ; R2-M1 (D9): an INT result prints
        BNE   PR_I1             ; from FACINT via FOUT_INT -- FOUT
        BSR     FOUT            ; itself would destroy FACSIGN and
        BRA   PR_W              ; render big values in E notation
PR_I1   BSR     FOUT_INT        ; INT: FACINT -> FBUFF (same bytes)
PR_W    BSR     PRWIDTH         ; line-wrap check (original's, at 80)
        LEA     FBUFF,A0
PRFB    MOVE.B  (A0)+,D0
        BEQ   PRFBD
        BSR     OUTDO
        BRA   PRFB
PRFBD   MOVE.B  #NUMSPC,D0      ; the number's trailing byte
        BSR     OUTDO           ; (NUMSPC: see the OUTSP comment)
        BRA   PRANEXT
PRSTRG  BSR     FREFAC          ; the original's STRPRT frees the
                                ; FAC temp first (FREFAC), then types
                                ; from the captured pointer: D2.W =
                                ; length, A1 = data; move it to A0
        MOVEA.L A1,A0
        BRA   PRSG2
PRSGL   MOVE.B  (A0)+,D0
        BSR     OUTDO
PRSG2   SUBQ.W  #1,D2
        BCC   PRSGL
        ; fall through into PRANEXT (a BRA to the next instruction
        ; is mis-encoded by asm68k-py: zero displacement)
