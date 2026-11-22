PRANEXT MOVE.W  #0,(SP)         ; after an item: CRDO state
        BSR     CHRGOT          ; (A6 already at D0's char; harmless)
        TST.B   D0
        BEQ   PRTERM
        CMPI.B  #$3A,D0
        BEQ   PRTERM
        CMPI.B  #$D1,D0         ; ELSE token (EXT1): the PRINT ends
        BEQ   PRTERM            ; here; EXEC/EXCOL hands the ELSE
        BRA     PRITEM          ; token to FETCH, which skips the
                                ; rest of the line (true-path ELSE)
PRTERM  TST.W   (SP)
        BNE   PRDONE          ; quiet state: no CRLF
        BSR     CRDO
PRDONE  ADDQ.L  #2,SP
        RTS
PRSEMI  MOVE.W  #1,(SP)         ; quiet state
        BSR     CHRGET
        BEQ   PRTERM
        CMPI.B  #$D1,D0         ; ELSE token (EXT1): as PRANEXT
        BEQ   PRTERM
        BRA     PRITEM
PRZONE  MOVE.W  #1,(SP)
        MOVE.B  POSX,D0
        CMPI.B  #70,D0          ; at/past the last zone start
        BCC   PRZCR             ; (NCMPOS): newline first.  The
                                ; terminal is 80 columns (LINLEN=80,
                                ; zone width 10), so the last zone
                                ; starts at ((80/10)-1)*10 = 70.
                                ; M1-M4 used 30, the base text's
                                ; REALIO=3 (40-column) value; Kyo's
                                ; 2026-11-19 decision unifies the
                                ; terminal model at 80 columns, in
                                ; line with PRWIDTH's wrap at 80.
        MOVE.B  D0,D1           ; D1 = POSX mod 10
PRZMOD  CMPI.B  #10,D1
        BCS   PRZSP
        SUBI.B  #10,D1
        BRA   PRZMOD
PRZSP   MOVEQ   #10,D2
        SUB.B   D1,D2           ; count = 10 - (POSX mod 10), >= 1
PRZ1    BSR     OUTSP           ; print first, then count down:
        SUBQ.B  #1,D2           ; exactly D2 spaces (the M3 loop
        BNE   PRZ1              ; decremented first and lost one)
        BRA   PRZNXT
PRZCR   BSR     CRDO
PRZNXT  BSR     CHRGET
        BEQ   PRTERM
        CMPI.B  #$D1,D0         ; ELSE token (EXT1): as PRANEXT
        BEQ   PRTERM
        BRA     PRITEM
