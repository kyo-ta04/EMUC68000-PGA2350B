        CMPI.B  #$3F,D0         ; '?' is PRINT
        BEQ   CRNQMARK
        CMPI.B  #$20,D0         ; space: stored as-is
        BEQ   CRNSTORE
        CMPI.B  #$30,D0
        BCS   CRNMUST         ; below '0': try a keyword
        CMPI.B  #$3C,D0
        BCS   CRNSTORE        ; '0'..';' stored straight
CRNMUST BSR     MATCHKW         ; D1=1 and D6=token if a word matches
        TST.B   D1
        BEQ   CRNNOM
        MOVE.B  D6,(A4)+        ; store the token byte
        MOVEA.L A2,A3           ; source continues past the word
        CMPI.B  #REMTK,D6
        BEQ   CRNREM
        CMPI.B  #DATATK,D6
        BNE     CRNL
        MOVEQ   #3,D7
        BRA     CRNL
CRNREM  MOVEQ   #2,D7
        BRA     CRNL
CRNNOM  MOVE.B  (A3)+,(A4)+     ; no match: copy the single char
        BRA     CRNL
CRNQ    MOVE.B  D0,(A4)+
        ADDQ.L  #1,A3
        MOVEQ   #1,D7
        BRA     CRNL
CRNQMARK MOVE.B #PRINTK,(A4)+
        ADDQ.L  #1,A3
        BRA     CRNL
CRNEND  MOVE.B  D0,(A4)+        ; store the terminating NUL
        LEA     BUF,A0
        MOVE.L  A4,D0
        SUB.L   A0,D0           ; crunched length incl. NUL
        MOVE.B  D0,COUNT
        LEA     BUF,A6
        SUBA.L  #$01,A6         ; A6 = BUF-1 for direct execution
        RTS

;---------------------------------------------------------------------
; MATCHKW -- try to match a reserved word at (A3) against RESLST.
; Out: D1.B = 1 if matched (D6.B = token, A2 = source position just
; past the word), D1.B = 0 if no word matches.
; Clobbers A1, A2, D1, D2, D6.  The match is a prefix match: the
; entry's last character has its high bit set in the table and must
; equal the source character with the high bit stripped.
;---------------------------------------------------------------------
MATCHKW LEA     RESLST(PC),A1
        MOVEQ   #0,D6
        MOVE.B  #$80,D6         ; token counter
MKWTRY  MOVEA.L A3,A2           ; candidate cursor
MKWM    MOVE.B  (A1),D1         ; table char
        MOVE.B  D1,D2
        ANDI.B  #$7F,D2         ; strip the end-of-word flag
        CMP.B   (A2),D2
        BNE   MKWNEXT         ; mismatch
        ADDQ.L  #1,A2
        ADDQ.L  #1,A1
        TST.B   D1
        BPL   MKWM            ; not the last char: keep comparing
        MOVEQ   #1,D1           ; full word matched
        RTS
MKWNEXT MOVE.B  (A1)+,D1        ; skip to the end of this entry
        BPL   MKWNEXT
        TST.B   (A1)            ; table terminator?
        BEQ   MKWNO
        ADDQ.B  #1,D6           ; next word, next token
        BRA   MKWTRY
MKWNO   MOVEQ   #0,D1
        RTS

;---------------------------------------------------------------------
; FNDLIN -- find the line whose number is in LINNUM.
; Out: A0 = address of that line; if there is no such line, A0 =
; address of the first line with a greater number (or of the end
; marker).  Z=1 iff an exact match was found.
;---------------------------------------------------------------------
FNDLIN  MOVEA.L TXTTAB,A0
FNDL1   TST.L   (A0)
        BEQ   FNDNO           ; end marker: not found
        MOVE.W  4(A0),D0
        CMP.W   LINNUM,D0
        BEQ   FNDRTS          ; exact match, Z=1
        BHI   FNDNO           ; greater line: not found
        MOVEA.L (A0),A0         ; follow the link
        BRA   FNDL1
FNDNO   MOVEQ   #1,D0           ; force Z=0 on the not-found exits
FNDRTS  RTS

;---------------------------------------------------------------------
; STORE -- insert/replace/delete the crunched line in BUF.
; LINNUM is the line number, COUNT the crunched length (incl. NUL).
; An empty crunched text (COUNT=1, first byte 0) only deletes.
; Mirrors the original MAIN1 + BLTU + FINI flow: delete any old
; line with this number, open a gap with BLTU, copy the new line
; in, repair all links with LNKPRG, and finish with RUNC.
;---------------------------------------------------------------------
STORE   BSR     FNDLIN          ; A0 = target or insertion point
        BEQ   STFND           ; (branch on FNDLIN's flags at once:
                                ; any MOVE in between would eat them)
        MOVE.L  A0,LOWTR        ; not found: no old line
        MOVEQ   #0,D5
        BRA   STSIZE
STFND   MOVE.L  A0,LOWTR        ; found: D5 = old line length
        MOVE.L  (A0),D5
        SUB.L   A0,D5
STSIZE  MOVEQ   #0,D4           ; new line total size (0 if none)
        MOVE.B  BUF,D0
        BEQ   STROOM
        MOVEQ   #0,D4
        MOVE.B  COUNT,D4
        ADDQ.L  #6,D4           ; link + number + text
        MOVE.L  D4,D0           ; round up to even (line alignment)
        ANDI.L  #$00000001,D0
        BEQ   STROOM
        ADDQ.L  #1,D4           ; pad byte after the NUL
STROOM  MOVE.L  VARTAB,D0       ; room check before mutating
        SUB.L   D5,D0
        ADD.L   D4,D0           ; would-be new VARTAB
        CMP.L   FRETOP,D0
        BHI     OMERR
        MOVE.L  D0,HIGHDS       ; stash new VARTAB
        TST.L   D5              ; delete the old line, if any
        BEQ   STINS
        MOVEA.L LOWTR,A0
        MOVEA.L (A0),A1         ; source = next line
        MOVE.L  VARTAB,D0
        SUB.L   A1,D0           ; bytes to slide down
        MOVEA.L A0,A2           ; destination = old line start
        BEQ   STINS
STDELL  MOVE.B  (A1)+,(A2)+
        SUBQ.L  #1,D0
        BNE   STDELL
STINS   TST.L   D4              ; insert the new line, if any
        BEQ   STFIN
        MOVEA.L LOWTR,A0        ; insertion point
        MOVE.L  HIGHDS,D0
        SUB.L   D4,D0           ; text end after deletion
        MOVEA.L D0,A1           ; BLTU source end
        MOVE.L  D4,D0           ; BLTU shift = new line size
        BSR     BLTU
        MOVE.W  LINNUM,4(A0)    ; write the header and the text
        LEA     6(A0),A2
        LEA     BUF,A1
        MOVEQ   #0,D0
        MOVE.B  COUNT,D0
STCPY   MOVE.B  (A1)+,(A2)+
        SUBQ.L  #1,D0
        BNE   STCPY
STFIN   MOVE.L  HIGHDS,VARTAB
        MOVE.L  HIGHDS,ARYTAB
        MOVE.L  HIGHDS,STREND
        BSR     LNKPRG
        BSR     RUNC
        RTS

;---------------------------------------------------------------------
; BLTU -- block transfer up: copy the block [A0, A1) to the address
; range starting D0 bytes higher.  Copies backwards, so the block
; may overlap its destination.  (The original's BLTU.)
;---------------------------------------------------------------------
BLTU    MOVEA.L A1,A2           ; destination end = source end + shift
        ADDA.L  D0,A2
        MOVE.L  A1,D1
        SUB.L   A0,D1           ; block length
        BEQ   BLTRTS
BLTLP   MOVE.B  -(A1),-(A2)
        SUBQ.L  #1,D1
        BNE   BLTLP
BLTRTS  RTS

;---------------------------------------------------------------------
; LNKPRG -- repair every link in the program text.  The end of a
; line is found by scanning for its terminating NUL; the next line
; starts right after it, plus one pad byte if that would be odd.
; The walk stops at the end marker, which by construction sits at
; VARTAB-4.  (The original's LNKPRG does the same job for its
; 2-byte links.)
;---------------------------------------------------------------------
LNKPRG  MOVEA.L TXTTAB,A0
        MOVE.L  VARTAB,D0
        SUBQ.L  #4,D0           ; end marker address
LNKL1   CMP.L   A0,D0
        BEQ   LNKRTS          ; at the end marker: done
        LEA     6(A0),A1        ; scan the text for its NUL
LNKL2   TST.B   (A1)+
        BNE   LNKL2           ; A1 = one past the NUL
        MOVE.L  A1,D1           ; align the next line start to even
        SUB.L   A0,D1
        ANDI.L  #$00000001,D1
        BEQ   LNKL3
        ADDQ.L  #1,A1
LNKL3   MOVE.L  A1,(A0)         ; store the link
        MOVEA.L A1,A0
        BRA   LNKL1
LNKRTS  RTS

;---------------------------------------------------------------------
; FETCH / EXEC -- the statement execution core (the original's
; GONE + NEWSTT).  FETCH dispatches the statement at A6; EXEC
; processes the terminator after a statement: ':' fetches the next
; statement on the line, NUL moves to the next line (or back to
; READY at the end of the program / of a direct line).
; Statements are called with A6 primed on the character after the
; token and that character in D0.B.  A statement returns with A6
; pointing at its terminator.  GOTO/RUN/END/LIST drop the return
; address and continue at FETCH or READY directly.
; M5g: both FETCH and EXEC begin with BRKCHK, the CTRL-C check
; the original makes at the head of NEWSTT (JSR ISCNTC there).
; EXEC's head is the exact counterpart (A6 still at the just-
; finished statement's terminator, CURLIN still its line);
; FETCH's head covers the paths that reach a statement without
; returning through EXEC (GOTO, RUN, CONT, THEN-statement).
;---------------------------------------------------------------------
FETCH   BSR     BRKCHK          ; M5g: CTRL-C check (NEWSTT head)
        MOVE.W  CURLIN,D1       ; M5b: the original's NEWSTT stores
        CMPI.W  #$FFFF,D1       ; TXTPTR in OLDTXT at every statement
        BEQ   FTGO              ; boundary (unless direct) -- INPUT's
        MOVE.L  A6,OLDTXT       ; restart and CONT-after-falloff use
        MOVE.W  D1,OLDLIN       ; it.  A6 here points at the ':' of
        MOVE.L  CURLINP,OLDCIP  ; the previous statement or at
        MOVE.B  #1,CONTMD       ; text-1 of a fresh line: in both
                                ; cases one byte BEFORE the statement
                                ; FETCH is about to dispatch, so CONT
                                ; resumes through FETCH (CONTMD=1).
                                ; STOP/END overwrite the save with
                                ; the terminator position (CONTMD=0).
FTGO    BSR     CHRGET          ; D0 = first byte of the statement
        BEQ   EXEC            ; terminator: empty statement
        CMPI.B  #$80,D0
        BCS   FTLET           ; not a token: maybe an implicit LET
