
;---------------------------------------------------------------------
; INIT -- cold start.  Mirrors the original SYSTEM INITIALIZATION:
; clear volatile storage, set up the string temporaries pointer,
; SCRATCH the program area, type the banner and fall into READY.
; (The original probes RAM to find MEMSIZ; the sim memory map is
; fixed, so MEMSIZ is set from MEMSIZV instead.)
;---------------------------------------------------------------------
