; Configuration -- HW variant ($30000 landing zone).
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; Memory-layout comment + the five variant address EQUs.

; Memory layout (HW variant):
;   $030000-  code image (HWENTRY at $30000, entered by CALL)
;   $034000   virtual zero page (ZP mirror)
;   $035000   TXTTAB (BASIC program text area)
;   $03F000   MEMSIZ (top of user RAM; string space grows down)
;   $040000   stack top (initial SSP)

ZPBASE  EQU     $034000         ; virtual zero page base
TXTTABV EQU     $035000         ; initial TXTTAB value
MEMSIZV EQU     $03F000         ; initial MEMSIZ value
STACKTOP EQU    $040000         ; initial SSP

FNTABV  EQU     $034800         ; M5c: FN definition table base
                                ; (fixed side area in the mirror
                                ; region; see GETFNM for why the
                                ; records do not live in the scalar
                                ; variable area as in the original)
