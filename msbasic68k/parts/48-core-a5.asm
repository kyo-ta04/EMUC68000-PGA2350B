EXEC    BSR     BRKCHK          ; M5g: CTRL-C check (NEWSTT head)
        MOVE.B  (A6),D0         ; ...and the terminator is processed
        BNE   EXCOL
        MOVE.W  CURLIN,D0       ; end of line: direct or program?
        CMPI.W  #$FFFF,D0
        BEQ     READY           ; direct line finished
        MOVEA.L CURLINP,A0
        MOVEA.L (A0),A0         ; next line (or the end marker)
        TST.L   (A0)
        BEQ     READY           ; end marker: program finished
        MOVE.L  A0,CURLINP
        MOVE.W  4(A0),CURLIN
        LEA     5(A0),A6        ; A6 = text-1 of the new line
        BRA   FETCH
