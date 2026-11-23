; Configuration -- REDESIGN HW variant ($0 resident image for
; the EMUC68000-PGA2350B dual/triple-boot firmware menu).
; Part of msbasic68k-rdhw.asm -- assembled only as part of the
; combined source produced by build.py.  Do not assemble this
; file on its own.
; Memory-layout comment + the five variant address EQUs.
;
; The EQUs are IDENTICAL to the rd variant (10-config-rd.asm)
; by design, not by accident.  The R0 A1 layout was drawn on
; the board's own map from the start (redesign-r0-design.md
; section 1): the RP2350B emulates 256KB RAM indexed by
; (address & $3FFFF), the sim's bus model is bit-identical
; (RAMMASK/MEMADRS_MASK $3FFFF in both emu.c and the
; firmware), and the boot-menu loader only places the image
; at $0 and lets the CPU take its own reset vectors -- it
; imposes no memory-map constraint of its own.  The phase1
; resident's MEMSIZ $02F000 / BYTES FREE 61440 was that
; interpreter's own sizing choice, never a loader or board
; requirement; capping the redesign to it would resurrect
; the "ASM.BAS does not fit" problem A1 was created to
; remove (boss text alone is 46,478 bytes).  Every redesign
; side area already sits inside the emulated 256KB and is
; either wiped at INIT/CLEAR (ZP, VHASH, LCACHE), bounded
; by a ZP pointer (FNTAB via FNTOP), zeroed per use
; (GCCTAB), or guarded by a ZP flag (LTABLE via LTVALID),
; so the firmware's zero-initialised memory[] is not a
; hidden dependency either.  Full audit:
; redesign-hw-flavour-2026-11-23.md.
;
; This separate config part exists so that any future
; board-specific adjustment lands here and never perturbs
; the accepted rd build; build.py pins the rdhw image to
; the rd image's size/sum so the two cannot drift apart
; silently.

; Memory layout (redesign A1 = board resident layout):
;   $000000-  code image (reset vectors at $0/$4, loaded at RAM $0)
;   $008000   variable hash table (512 entries x 8 bytes)
;   $00C000   literal cache (128 entries x 32 bytes)
;   $00D000   line table (2048 entries x 6 bytes)
;   $010000   virtual zero page (ZP mirror), $0332 bytes cleared
;   $010E00   GC-C1 radix count table; $011000-$017FFF GC work list
;   $018000   FN definition table
;   $020000   TXTTAB (BASIC program text area)
;   $03F800   MEMSIZ (top of user RAM; string space grows down)
;   $040000   stack top (initial SSP; 2KB stack reservation
;             $03F800-$03FFFF against MEMSIZ)
; BYTES FREE = 129024.  ACIA $80E000/$80E001 and tape device
; $80E100, both decoded by full address, as on the sim.

ZPBASE  EQU     $010000         ; virtual zero page base
TXTTABV EQU     $020000         ; initial TXTTAB value
MEMSIZV EQU     $03F800         ; initial MEMSIZ value
STACKTOP EQU    $040000         ; initial SSP

FNTABV  EQU     $018000         ; M5c: FN definition table base
                                ; (fixed side area in the mirror
                                ; region; see GETFNM for why the
                                ; records do not live in the scalar
                                ; variable area as in the original)
