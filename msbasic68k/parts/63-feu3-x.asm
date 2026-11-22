FE_U3   CMPI.B  #$C7,D0         ; CHR$
        BEQ   FE_CHR
        CMPI.B  #$B7,D0         ; USR (EXT1: live; a stub in the
        BEQ   FE_USR            ; faithful flavour)
        CMPI.B  #$CC,D0         ; DEEK (EXT1)
        BEQ   FE_DEEK
        CMPI.B  #$CE,D0         ; LEEK (EXT1)
        BEQ   FE_LEEK
        CMPI.B  #$D0,D0         ; INSTR (EXT1)
        BEQ   FE_INSTR
        BRA     SNERR
