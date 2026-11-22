; Machine layer.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; MONCOUT / MONRDKEY / MONPOLKEY / ISCNTC / BRKCHK + PUSHBK, CRDO / STROUT, PRTDEC / DIV10.
;---------------------------------------------------------------------
; Machine layer -- the three console primitives of the original.
; ACIA: status $80E001 (bit0 = receive ready, bit1 = transmit ready,
; always 1 in the sim), data $80E000.
; M5g adds the console input discipline the CTRL-C check needs:
; a 1-byte pushback (PUSHBK) drained by MONRDKEY / MONPOLKEY
; before the ACIA, and BRKCHK / BRKGO for the break itself.
; All console input flows through this layer.
;---------------------------------------------------------------------
; MONCOUT -- output the character in D0.B, polling TDRE.
; Preserves all registers.
MONCOUT MOVE.L  D1,-(SP)
MCO1    MOVE.B  ACIASTA,D1
        ANDI.B  #$02,D1
        BEQ   MCO1
        MOVE.B  D0,ACIADAT
        MOVE.L  (SP)+,D1
        RTS

; MONRDKEY -- blocking input: returns the character in D0.B.
; M5g: a byte BRKCHK pushed back is returned before the ACIA
; is touched, so type-ahead survives the boundary check.
MONRDKEY TST.B  PUSHBK         ; a pushed-back byte waiting?
        BEQ     MRD1
        MOVE.B  PUSHBK+1,D0
        CLR.W   PUSHBK
        RTS
MRD1    MOVE.B  ACIASTA,D0
        ANDI.B  #$01,D0
        BEQ     MRD1
        MOVE.B  ACIADAT,D0
        RTS

; MONPOLKEY -- non-blocking input (M5g): Z=0 with the next
; character in D0.B if one is available (the pushback slot
; first, then the ACIA), Z=1 if none is.  The availability is
; reported through a scratch flag, not the character, so a
; waiting NUL still reads as "available".  Clobbers D0, D1.
MONPOLKEY TST.B PUSHBK         ; a pushed-back byte waiting?
        BEQ     MPK1
        MOVE.B  PUSHBK+1,D0
        CLR.W   PUSHBK
        MOVEQ   #1,D1           ; "available": tested below
        BRA     MPK2
MPK1    MOVE.B  ACIASTA,D0
        ANDI.B  #$01,D0
        BEQ     MPKRTS          ; Z=1: nothing waiting
        MOVE.B  ACIADAT,D0
        MOVEQ   #1,D1
MPK2    TST.B   D1              ; Z=0: D0.B holds a character
MPKRTS  RTS

; ISCNTC -- non-blocking check (the original asks "was STOP pressed?";
; here: is a character waiting?).  Returns with Z=1 if no character
; is pending, Z=0 if one is.  A pushed-back byte counts as pending.
; Clobbers D0.
ISCNTC  TST.B   PUSHBK
        BNE     ISCY
        MOVE.B  ACIASTA,D0
        ANDI.B  #$01,D0
        RTS
ISCY    MOVEQ   #1,D0           ; Z=0: a character is pending
        RTS

;---------------------------------------------------------------------
; BRKCHK -- the statement-boundary CTRL-C check (M5g; the
; original's JSR ISCNTC at the head of NEWSTT, called from the
; heads of FETCH and EXEC).  The serial ACIA has no separate
; STOP channel, so the check looks at the HEAD of the console
; input stream only:
;   - pushback occupied: that byte is the head; BRKCHK itself
;     put it there, so it is known not to be $03 -- done.
;   - ACIA empty: done.
;   - ACIA has a byte: read it.  $03 (CTRL-C) branches to
;     BRKGO (the break path; never returns).  Any other byte
;     is pushed back, so the next MONRDKEY / MONPOLKEY
;     consumer still receives it, in order: the check never
;     eats type-ahead.
; Clobbers D0 only (BRKGO may clobber more; it never returns).
;---------------------------------------------------------------------
BRKCHK  TST.B   PUSHBK
        BNE     BRKRTS          ; head is a known non-$03 byte
        MOVE.B  ACIASTA,D0
        ANDI.B  #$01,D0
        BEQ     BRKRTS          ; nothing waiting
        MOVE.B  ACIADAT,D0
        CMPI.B  #$03,D0
        BNE     BRKPB
        BRA     BRKGO           ; CTRL-C: break (no return)
BRKPB   MOVE.B  D0,PUSHBK+1     ; not CTRL-C: push it back
        MOVE.B  #1,PUSHBK
BRKRTS  RTS

;---------------------------------------------------------------------
; CRDO -- type a CRLF pair.  (The original's CRDO.)
; STROUT -- type the NUL-terminated string pointed to by A0.
; Clobbers A0 and D0.
;---------------------------------------------------------------------
CRDO    MOVE.B  #$0D,D0
        BSR     MONCOUT
        MOVE.B  #$0A,D0
        BSR     MONCOUT
        CLR.B   POSX            ; the original's CRDO resets the column
        RTS
STROUT  MOVE.B  (A0)+,D0
        BEQ   STROK
        BSR     MONCOUT
        BRA   STROUT
STROK   RTS

;---------------------------------------------------------------------
; PRTDEC -- print the unsigned 32-bit value in D0 in decimal,
; no leading spaces.  Uses DIV10.  Clobbers D0-D3.
;---------------------------------------------------------------------
PRTDEC  TST.L   D0
        BNE   PRTD1
        MOVE.B  #$30,D0         ; value is zero: just "0"
        BSR     MONCOUT
        RTS
PRTD1   CLR.W   D3              ; digit count
PRTLP   BSR     DIV10           ; D0 = quotient, D1 = remainder
        ADDI.B  #$30,D1
        MOVE.B  D1,-(SP)        ; stack the digit (byte push: SP -= 2)
        ADDQ.W  #1,D3
        TST.L   D0
        BNE   PRTLP
PRTPOP  MOVE.B  (SP)+,D0
        BSR     MONCOUT
        SUBQ.W  #1,D3
        BNE   PRTPOP
        RTS

; DIV10 -- D0.L unsigned / 10 -> quotient in D0.L, remainder in D1.L.
; Two-step DIVU so no 32-bit divide is needed.  Clobbers D1, D2.
DIV10   MOVE.L  D0,D1
        SWAP    D1
        ANDI.L  #$0000FFFF,D1   ; D1 = high word of value
        DIVU    #10,D1          ; D1: high=remainder, low=quot-high
        MOVE.L  D1,D2
        MOVE.W  D0,D2           ; D2 = (remainder<<16) | low word
        DIVU    #10,D2          ; D2: high=remainder(digit), low=quot-low
        MOVE.L  D1,D0
        SWAP    D0              ; D0 = quot-high << 16
        MOVE.W  D2,D0           ; D0 = full quotient
        SWAP    D2
        MOVE.L  D2,D1
        ANDI.L  #$0000FFFF,D1   ; D1 = the digit
        RTS

