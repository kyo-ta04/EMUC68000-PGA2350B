        DC.B    "G",$CF          ; GO
        DC.B    "DEE",$CB        ; DEEK   (EXT1, $CC)
        DC.B    "DOK",$C5        ; DOKE   (EXT1, $CD)
        DC.B    "LEE",$CB        ; LEEK   (EXT1, $CE)
        DC.B    "LOK",$C5        ; LOKE   (EXT1, $CF)
        DC.B    "INST",$D2       ; INSTR  (EXT1, $D0)
        DC.B    "ELS",$C5        ; ELSE   (EXT1, $D1)
        DC.B    "MO",$C4         ; MOD    (R2-M3, $D2; D2 adopts
                                ; the BASIC-80 operator -- appended
                                ; at the end so no existing token
                                ; is renumbered)
        DC.B    $DC              ; \      (R2-M3, $D3; the single
                                ; character $5C with its high bit)
        DC.B    $00              ; end of list
        DC.B    $00              ; EXT1 pad: the six words above add
                                ; an odd 25 bytes, which would leave
                                ; every following instruction at an
                                ; odd address (the 68K fetches code
                                ; from even addresses only; the
                                ; strict sim faults on an odd entry
                                ; point).  The pad restores parity.
