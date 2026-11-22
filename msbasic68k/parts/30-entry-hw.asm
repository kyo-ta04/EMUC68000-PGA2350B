; Entry -- HW variant: HWENTRY stub at $30000.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; Entered via EhBASIC CALL $30000; never returns.

        ORG     $030000
HWENTRY MOVE.W  #$2700,SR       ; HW entry (CALL $30000): supervisor
                                ; mode, all interrupts masked -- the
                                ; board is polled I/O and nothing may
                                ; preempt the REPL
        LEA     STACKTOP,A7     ; HW: private stack at the zone top.
                                ; The caller's return address is
                                ; abandoned: the REPL never returns
                                ; (exit is a board reset)
        BRA     INIT            ; HW: cold start

