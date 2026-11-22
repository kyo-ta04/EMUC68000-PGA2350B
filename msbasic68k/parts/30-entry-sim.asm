; Entry -- SIM variant: reset vectors at $0.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; The image boots from the reset vector pair.

        ORG     $000000
        DC.L    STACKTOP        ; reset SSP
        DC.L    INIT            ; reset PC

