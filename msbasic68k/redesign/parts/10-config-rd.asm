; Configuration -- REDESIGN R1 variant ($0 image, A1 memory model).
; Part of msbasic68k-rd.asm -- assembled only as part of the
; combined source produced by build.py.  Do not assemble this
; file on its own.
; Memory-layout comment + the five variant address EQUs.

; Memory layout (redesign R1; A1 = full 32-bit space):
;   $000000-  code image (reset vectors at $0/$4, loaded at RAM $0)
;   $010000   virtual zero page (ZP mirror), $0123 bytes used
;   $018000   FN definition table
;   $020000   TXTTAB (BASIC program text area)
;   $03F800   MEMSIZ (top of user RAM; string space grows down)
;   $040000   stack top (initial SSP)
; BYTES FREE = 129024.  ACIA $80E000/$80E001, as on the sim.

ZPBASE  EQU     $010000         ; virtual zero page base
TXTTABV EQU     $020000         ; initial TXTTAB value
MEMSIZV EQU     $03F800         ; initial MEMSIZ value
STACKTOP EQU    $040000         ; initial SSP

FNTABV  EQU     $018000         ; M5c: FN definition table base
                                ; (fixed side area in the mirror
                                ; region; see GETFNM for why the
                                ; records do not live in the scalar
                                ; variable area as in the original)
