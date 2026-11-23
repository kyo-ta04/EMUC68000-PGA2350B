FE_VAR  CMPI.B  #$41,D0         ; variables start with a letter
        BCS     SNERR
        CMPI.B  #$5A,D0
        BHI     SNERR
        BRA     FRM_VARIABLE
