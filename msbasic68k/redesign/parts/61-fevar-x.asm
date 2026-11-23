FE_VAR  CMPI.B  #$26,D0         ; '&' (EXT1): &H hex literal
        BEQ     FE_HEX          ; (in the EXT1 part)
        CMPI.B  #$41,D0         ; variables start with a letter
        BCS     SNERR
        CMPI.B  #$5A,D0
        BHI     SNERR
        BRA     FRM_VARIABLE
