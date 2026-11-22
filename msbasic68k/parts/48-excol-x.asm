EXCOL   CMPI.B  #$3A,D0         ; ':' -> another statement follows
        BEQ   FETCH
        CMPI.B  #$D1,D0         ; ELSE token (EXT1): the ELSE clause
        BNE     SNERR           ; begins.  MS Extended needs no ':'
        SUBQ.L  #1,A6           ; before ELSE.  FETCH wants TXTPTR
        BRA     FETCH           ; one byte BEFORE the statement, so
                                ; step back: its CHRGET then lands
                                ; exactly on the ELSE token and the
                                ; EXT dispatch skips the line's rest.
