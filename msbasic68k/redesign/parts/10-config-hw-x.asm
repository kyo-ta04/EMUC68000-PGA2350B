; Configuration -- EXT1 HW variant ($30000 landing zone).
; Part of msbasic68k-hw-ext.asm -- assembled only as part
; of the combined source produced by build.py.  Do not
; assemble this file on its own.
; Memory-layout comment + the five variant address EQUs.

; Memory layout (EXT1 HW variant):
;   $030000-  code image (HWENTRY at $30000, entered by CALL)
;   $034400   virtual zero page (ZP mirror)
;   $035000   TXTTAB (BASIC program text area)
;   $03F000   MEMSIZ (top of user RAM; string space grows down)
;   $040000   stack top (initial SSP)
;
; The ONLY difference from the faithful HW layout is ZPBASE:
; the EXT1 code image is 131 bytes too large for the faithful
; 16 KB code budget (it would end at $34082), so the zero page
; moves up by $400, to $34400 (the FN table at $34800, TXTTAB,
; MEMSIZ, the stack top and BYTES FREE = 40960 are unchanged).
; The logical page (PEEK/POKE/DEEK/LEEK/USR vector) is ZPBASE-
; relative by design, so no user-visible semantics change.

ZPBASE  EQU     $034400         ; virtual zero page base (EXT1)
TXTTABV EQU     $035000         ; initial TXTTAB value
MEMSIZV EQU     $03F000         ; initial MEMSIZ value
STACKTOP EQU    $040000         ; initial SSP

FNTABV  EQU     $034800         ; M5c: FN definition table base
                                ; (fixed side area in the mirror
                                ; region; see GETFNM for why the
                                ; records do not live in the scalar
                                ; variable area as in the original)
