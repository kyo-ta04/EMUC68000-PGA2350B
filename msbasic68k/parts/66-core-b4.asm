FREEMSG DC.B    " BYTES FREE"
        DC.B    $0D,$0A,$00
RDYMSG  DC.B    $0D,$0A
        DC.B    "READY."
        DC.B    $0D,$0A,$00
ERRTXT  DC.B    " ERROR"
        DC.B    $00
INTXT   DC.B    " IN "
        DC.B    $00
BRKTXT  DC.B    "BREAK"
        DC.B    $00
TRYAGN  DC.B    "?REDO FROM START"
        DC.B    $00
EXIGNT  DC.B    "?EXTRA IGNORED"
        DC.B    $00
