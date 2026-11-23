; Configuration -- SIM variant ($0 image).
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; Memory-layout comment + the five variant address EQUs.

; Memory layout (sim image; chosen so nothing collides):
;   $000000-  code image (reset vectors at $0/$4, loaded at RAM $0)
;   $010000   virtual zero page (ZP mirror), $0123 bytes used
;   $020000   TXTTAB (BASIC program text area)
;   $02F000   MEMSIZ (top of user RAM; string space grows down)
;   $030000   stack top (initial SSP)

ZPBASE  EQU     $010000         ; virtual zero page base
TXTTABV EQU     $020000         ; initial TXTTAB value
MEMSIZV EQU     $02F000         ; initial MEMSIZ value
STACKTOP EQU    $030000         ; initial SSP

FNTABV  EQU     $018000         ; M5c: FN definition table base
                                ; (fixed side area in the mirror
                                ; region; see GETFNM for why the
                                ; records do not live in the scalar
                                ; variable area as in the original)
