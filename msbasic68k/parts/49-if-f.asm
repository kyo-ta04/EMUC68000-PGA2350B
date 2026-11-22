;---------------------------------------------------------------------
; IF -- the original's IF (m6502.asm "IF ... THEN" code).
; Evaluate the condition; the character after it must be the
; GOTO token (THEN omitted) or the THEN token.  FACEXP = 0 is
; false: skip the rest of the LINE (the original's REMN -- an
; IF governs the whole line remainder, ':'-separated statements
; included) and let EXEC advance to the next line.  True: a line
; number goes to GOTO (the original's DOCOND digit test), and
; anything else is executed as a statement (the original's
; GONE3).  "IF c GOTO n" reaches the statement path with TXTPTR
; on the GOTO token, which FETCH then dispatches to GOTOH.
;---------------------------------------------------------------------
IFH     BSR     FRMEVL          ; condition -> FAC (A6 primed by
                                ; FETCH on the first character)
        BSR     CHRGOT          ; the terminator character
        CMPI.B  #$89,D0         ; GOTO token: no THEN needed
        BEQ     IF_OK
        MOVE.B  #$A7,D0         ; THEN token
        BSR     SYNCHR          ; must match; advances past THEN
IF_OK   TST.B   FAC             ; FACEXP: 0 = false, else true
        BEQ     IF_FALSE
        BSR     CHRGOT          ; char after THEN (or the GOTO
                                ; token itself, if THEN was omitted)
        CMPI.B  #$30,D0         ; '0'
        BCS     IF_STMT
        CMPI.B  #$39,D0         ; '9'
        BHI     IF_STMT
        BRA     GOTOH           ; A6/D0 primed on the first digit:
                                ; exactly GOTOH's entry state (it
                                ; drops the dispatch return itself)
IF_STMT SUBQ.L  #1,A6           ; FETCH wants TXTPTR one byte before
        ADDQ.L  #4,SP           ; the statement; drop this handler's
        BRA     FETCH           ; dispatch return (as GOTOH does)
IF_FALSE BRA    REMH             ; skip to the line's NUL; EXEC then
                                ; moves to the next line
