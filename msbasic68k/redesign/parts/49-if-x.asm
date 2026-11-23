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
;
; EXT1: ELSE (MS Extended semantics).  On a FALSE condition,
; ELSESCAN looks for an ELSE token at nesting depth 0 in the
; rest of the line; if one is found, execution continues with
; the statement(s) after it (a line number goes to GOTOH, as
; on the THEN side).  If none is found, the behaviour is the
; faithful one: skip to the line's NUL and let EXEC advance.
; On a TRUE condition the THEN side runs as a normal statement
; sequence, and an ELSE token later dispatched by FETCH simply
; skips the rest of the line (see the EXT1 FETCH part) -- the
; classic MS arrangement.  ELSE binds to the nearest unmatched
; IF: the scan counts IF tokens.
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
IF_FALSE MOVEQ  #0,D7           ; EXT1: ELSE nesting depth = 0
        ; ...and fall through into ELSESCAN, the scan for an
        ; ELSE at depth 0 (A6 is at the first byte after THEN,
        ; or at the GOTO token when THEN was omitted).  A BRA
        ; to the next instruction would be mis-encoded by
        ; asm68k-py (a zero displacement picks up the target's
        ; first word -- the trap SGNFN's comment documents).

;---------------------------------------------------------------------
; ELSESCAN -- raw-byte scan for an ELSE token at depth 0.
; Entered from IF_FALSE with A6 at the first unscanned byte and
; the FETCH dispatch return on the stack (exactly IFH's own
; stack state).  Quotes are skipped as strings; a REM token
; ends the search (the rest is a comment: REMH finishes the
; line); a DATA token is skipped with DATAN itself, so the
; DATA skip discipline (':' or NUL, quotes respected) is the
; interpreter's own.  Outcomes:
;   miss:  A6 at the line's NUL, RTS (to EXEC, like REMH's).
;   hit:   a line number goes to GOTOH; anything else drops
;          the dispatch return and continues at FETCH, exactly
;          like IF_STMT.
;---------------------------------------------------------------------
ELSESCAN MOVE.B (A6),D0
        BEQ   ESC_RTS           ; NUL: no ELSE on this line
        CMPI.B  #$22,D0         ; '"' opens a string: skip it
        BEQ   ESC_QT
        CMPI.B  #$8F,D0         ; REM token: rest is a comment
        BEQ   ESC_REM
        CMPI.B  #$83,D0         ; DATA token: skip the statement
        BEQ   ESC_DATA
        CMPI.B  #$8B,D0         ; IF token: one more nesting level
        BEQ   ESC_IF
        CMPI.B  #$D1,D0         ; ELSE token
        BEQ   ESC_ELSE
        ADDQ.L  #1,A6
        BRA   ELSESCAN
ESC_RTS RTS                     ; A6 at the NUL: EXEC advances
ESC_REM BRA   REMH              ; REMH skips to the NUL, RTS to EXEC
ESC_DATA ADDQ.L #1,A6           ; step past the DATA token, then
        BSR   DATAN             ; DATAN skips to ':' or NUL
        BRA   ELSESCAN          ; re-examine the terminator byte
ESC_IF  ADDQ.W  #1,D7
        ADDQ.L  #1,A6
        BRA   ELSESCAN
ESC_ELSE TST.W  D7
        BEQ   ESC_HIT           ; depth 0: this ELSE is ours
        SUBQ.W  #1,D7           ; it closes an inner IF: skip it
        ADDQ.L  #1,A6
        BRA   ELSESCAN
ESC_QT  ADDQ.L  #1,A6           ; opening quote consumed
ESC_QT1 MOVE.B  (A6),D0
        BEQ   ESC_RTS           ; unterminated string: A6 at the NUL
        ADDQ.L  #1,A6
        CMPI.B  #$22,D0
        BNE   ESC_QT1
        BRA   ELSESCAN          ; past the closing quote
ESC_HIT BSR     CHRGET          ; step past ELSE; D0 = next char
        CMPI.B  #$30,D0         ; '0'
        BCS   ESC_STMT
        CMPI.B  #$39,D0         ; '9'
        BHI   ESC_STMT
        BRA     GOTOH           ; line-number form: A6/D0 primed on
                                ; the first digit (GOTOH's entry)
ESC_STMT SUBQ.L #1,A6           ; statement form: exactly IF_STMT
        ADDQ.L  #4,SP
        BRA     FETCH
