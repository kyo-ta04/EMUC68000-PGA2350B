
; FTLET -- FETCH helper: a statement that does not start with a
; token.  A letter means an implicit LET (the original falls into
; LET the same way); anything else is a syntax error.  A6 points
; at the letter and D0.B holds it, which is exactly LETCORE's
; entry state.  The JSR returns into EXEC, like a dispatched
; handler.
FTLET   CMPI.B  #$41,D0         ; 'A'
        BCS     SNERR
        CMPI.B  #$5A,D0         ; 'Z'
        BHI     SNERR
        JSR     LETCORE         ; A6/D0 already at the first letter
        BRA     EXEC

;---------------------------------------------------------------------
; Statement handlers.  Entry: D0.B = current char, A6 points at it.
;---------------------------------------------------------------------
SNSTUB  BRA     SNERR           ; unimplemented statement (for now)

; NEW -- if the rest of the statement is empty, SCRATCH.
NEWH    TST.B   D0
        BEQ   NEWD
        CMPI.B  #$3A,D0
        BNE   NEWRTS
NEWD    BSR     SCRATCH
NEWRTS  RTS

; CLR (CLEAR) -- if the rest is empty, CLEARC.
CLEARH  TST.B   D0
        BEQ   CLRD
        CMPI.B  #$3A,D0
        BNE   CLRRTS
CLRD    BSR     CLEARC
CLRRTS  RTS

; END -- if the rest is empty, end execution (back to READY).
; Like STOP (STOPC is shared in the original), END saves the
; continue context first: OLDTXT at the terminator after END,
; so a later CONT resumes through EXEC (CONTMD=0) and simply
; runs off the program again.  Direct mode saves nothing.
ENDH    TST.B   D0
        BEQ   ENDD
        CMPI.B  #$3A,D0
        BNE   ENDRTS
ENDD    MOVE.W  CURLIN,D0
        CMPI.W  #$FFFF,D0
        BEQ   ENDGO           ; direct: no save (the original's
                                ; DIRIS path)
        MOVE.L  A6,OLDTXT
        MOVE.W  D0,OLDLIN
        MOVE.L  CURLINP,OLDCIP
        CLR.B   CONTMD
ENDGO   ADDQ.L  #4,SP           ; drop the FETCH return address
        BRA     READY
ENDRTS  RTS

; REM -- skip to the end of the line (only NUL terminates).
REMH    TST.B   (A6)
        BEQ   REMRTS
        ADDQ.L  #1,A6
        BRA   REMH
REMRTS  RTS

; DATA -- skip to the end of the statement (':' or NUL terminate;
; quotes are respected, as in the original's DATAN).
DATAN   MOVEQ   #0,D1           ; quote flag
DTN1    MOVE.B  (A6),D0
        BEQ   DTNRTS          ; NUL always terminates
        TST.B   D1
        BNE   DTNQ
        CMPI.B  #$3A,D0
        BEQ   DTNRTS          ; ':' terminates outside quotes
        CMPI.B  #$22,D0
        BNE   DTNADV
        MOVEQ   #1,D1           ; enter a quote
        BRA   DTNADV
DTNQ    CMPI.B  #$22,D0
        BNE   DTNADV
        MOVEQ   #0,D1           ; leave the quote
DTNADV  ADDQ.L  #1,A6
        BRA   DTN1
DTNRTS  RTS

