        CMPI.B  #NEWK,D0
        BHI     SNERR           ; a token, but not a statement token
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        SUBI.W  #$80,D1         ; statement index 0..34
        ADD.W   D1,D1
        ADD.W   D1,D1           ; *4: STMDSP holds longwords
        LEA     STMDSP(PC),A0
        ADDA.W  D1,A0
        MOVEA.L (A0),A0
        BSR     CHRGET          ; prime the next char for the handler
        JSR     (A0)            ; handler returns here...
