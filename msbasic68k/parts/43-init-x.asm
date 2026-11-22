INIT    LEA     ZPBASE,A0
        MOVE.W  #ZPSIZE,D0
INICLR  CLR.B   (A0)+
        SUBQ.W  #1,D0
        BNE   INICLR
        CLR.W   ZPBASE+$334     ; EXT1: USR vector := unset (0).
                                ; The slot sits just past ZPSIZE, so
                                ; the loop above never clears it; on
                                ; the HW route the landing-zone page
                                ; can hold residue, so clear it here.
                                ; NEW does not touch it (the vector
                                ; survives, like the original's RAM
                                ; USRLOC).
