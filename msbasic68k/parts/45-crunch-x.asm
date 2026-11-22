CRNNORM CMPI.B  #$26,D0         ; '&' (EXT1): maybe an &H literal
        BEQ   CRNAMP            ; (in the EXT1 part): copy it raw so
                                ; &HDEF / &HEND are not tokenized
        CMPI.B  #$22,D0         ; '"' opens a string
        BEQ   CRNQ
