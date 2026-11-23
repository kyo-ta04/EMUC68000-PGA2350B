        LEA     RNDX,A0         ; M5d: the RND seed.  The original's
        MOVE.B  #$80,(A0)       ; cold start copies the ROM image's
        MOVE.B  #$4F,1(A0)      ; seed ($80,$4F,$C7,$52,$59) into
        MOVE.B  #$C7,2(A0)      ; RNDX along with CHRGET -- one byte
        MOVE.B  #$52,3(A0)      ; short, so the seed's last byte is
        CLR.B   4(A0)           ; never copied and RNDX ends in the
                                ; RAM residue (0 in the sim and in
                                ; the golden harness alike)
        MOVE.L  #TMPDSC,TEMPPT  ; TEMPPT -> the temp descriptor stack
        CLR.L   LASTPT          ; no temp is "last" yet (0 matches no
                                ; descriptor address)
        BSR     SCRATCH
        MOVE.W  #$FFFF,CURLIN   ; direct mode, as the original does
        LEA     BANNER(PC),A0
        BSR     STROUT
        MOVE.B  #$20,D0         ; " nnnnn BYTES FREE"
        BSR     MONCOUT
        MOVE.L  MEMSIZ,D0
        SUB.L   TXTTAB,D0
        BSR     PRTDEC
        LEA     FREEMSG(PC),A0
        BSR     STROUT
        BRA     READY

;---------------------------------------------------------------------
; SCRATCH -- the work of NEW: reset the dynamic pointers and leave
; an empty program (just the 4-byte zero end-marker link).
; TXTTAB itself never changes after INIT (as in the original).
;---------------------------------------------------------------------
SCRATCH BSR     VH_CLEAR        ; R1-M2: the variable hash
                                ; dies with the variables
        BSR     LC_CLEAR        ; R1-M3: and the literal cache
        CLR.B   LTVALID         ; R1-M4: no program, no table
        MOVE.L  #TXTTABV,TXTTAB
        MOVE.L  #TXTTABV+4,VARTAB
        MOVE.L  #TXTTABV+4,ARYTAB
        MOVE.L  #TXTTABV+4,STREND
        MOVE.L  #MEMSIZV,FRETOP
        MOVE.L  #MEMSIZV,FRESPC
        MOVE.L  #MEMSIZV,MEMSIZ
        MOVE.L  #TXTTABV-1,DATPTR ; M5b: READ starts before the
                                ; first line (the original's RESTOR
                                ; state); the program is empty here
        MOVE.L  #FNTABV,FNTOP   ; M5c: FN definitions die with the
        CLR.W   ARYDPT          ; variables (they live in the
                                ; variable area in the original)
        CLR.L   OLDTXT          ; M5b: NEW disallows CONT (STKINI)
        MOVEA.L #TXTTABV,A0
        CLR.L   (A0)            ; end marker: link = 0
        RTS

;---------------------------------------------------------------------
; CLEARC -- the work of CLEAR: liberate variables and arrays,
; free string space, reset the string temporaries (the original's
; STKINI part that matters in M2).
; RUNC -- what RUN does before starting a program: just CLEARC
; here (the original also points TXTPTR at TXTTAB-1; our callers
; set A6 themselves).
;---------------------------------------------------------------------
CLEARC  BSR     VH_CLEAR        ; R1-M2: same for CLEAR/RUN
        MOVE.L  MEMSIZ,FRETOP
        MOVE.L  VARTAB,ARYTAB
        MOVE.L  VARTAB,STREND
        MOVE.L  #TMPDSC,TEMPPT  ; (the original's STKINI resets
                                ; TEMPPT the same way; LASTPT is left
                                ; alone there too, and is harmless: it
                                ; can only equal a slot that PUTNEW
                                ; re-registers before any FRETMS)
        MOVE.L  #FNTABV,FNTOP   ; M5c: CLEAR kills FN definitions
        CLR.W   ARYDPT          ; too (variable area in the original)
        CLR.B   SUBFLG
        MOVE.L  #STACKTOP,FORSP ; variables are gone: FOR frames too
        MOVE.L  #STACKTOP,GOSUBSP ; ... and GOSUB frames
        BSR     RESTOR          ; M5b: the original's CLEARC falls
                                ; into FLOAD, which JSRs RESTOR:
                                ; DATPTR := TXTTAB-1
        CLR.L   OLDTXT          ; M5b: STKINI also disallows CONT
        RTS
RUNC    BSR.S   CLEARC
        BSR     LT_BUILD        ; R1-M4: (re)build the line
                                ; table for the coming run
        RTS

;---------------------------------------------------------------------
; READY / MAIN -- type READY., read a line, and either store it
; (leading line number), execute it (direct statement), or loop.
; M8: READY. is typed ONLY at the READY entry (boot, after a
; direct command, after RUN/END/STOP, on error return) --
; storing a numbered line and blank lines fall back to MAIN
; (INLIN) with no prompt, exactly as in the original (whose
; MAIN loop re-enters below its READY print).  Through M7 the
; port reprinted READY. after every stored line instead (an
; M1-era harness-sync decision, a known deviation from CBM
; BASIC 2); Kyo had it fixed for screenshot use in M8.
;---------------------------------------------------------------------
READY   LEA     STACKTOP,SP     ; clean stack at every READY
        MOVE.L  #STACKTOP,FORSP ; and no FOR frames survive it
        MOVE.L  #STACKTOP,GOSUBSP ; nor GOSUB frames
        CLR.W   ARYDPT          ; M5c: an error or STOP can strand
        CLR.B   FNPARSE         ; the array/FN parse state mid-way;
        CLR.B   SUBFLG          ; the original's STKINI resets the
        CLR.B   DIMFLG          ; same class of flags here
        LEA     RDYMSG(PC),A0
        BSR     STROUT
MAIN    BSR     INLIN           ; D0.W = line length, text in BUF
        TST.W   D0
        BEQ   MAIN            ; empty line: no prompt (original)
        MOVE.W  #$FFFF,CURLIN   ; direct mode until a number says else
        LEA     BUF,A6
        SUBA.L  #$01,A6         ; A6 = BUF-1
        BSR     CHRGET          ; D0 = first char (spaces skipped)
        BEQ   MAIN            ; line of spaces only: blank, no prompt
        CMPI.B  #$30,D0
        BCS   MDIRECT
        CMPI.B  #$39,D0
        BHI   MDIRECT
        BSR     LINGET          ; numbered line: LINNUM is set
        BSR     CRUNCH
        BSR     STORE
        BRA     MAIN          ; stored: next line, no READY.
MDIRECT BSR     CRUNCH
        BRA     FETCH           ; execute the direct line

;---------------------------------------------------------------------
; INLIN -- read one line into BUF with echo.  CR ($0D) terminates
; (CRLF is echoed); LF ($0A) is ignored; BS ($08) / DEL ($7F) erase
; one character.  Returns the length in D0.W; BUF is NUL-terminated.
; Mirrors the original TERMINAL INPUT routine's contract.
;---------------------------------------------------------------------
INLIN   LEA     BUF,A1
        CLR.W   D2              ; character count
INL1    BSR     MONRDKEY        ; D0.B = character
        CMPI.B  #$0D,D0
        BEQ   INLDON
        CMPI.B  #$0A,D0
        BEQ   INL1            ; ignore LF
        CMPI.B  #$08,D0
        BEQ   INLBS
        CMPI.B  #$7F,D0
        BEQ   INLBS
        CMPI.W  #BUFLEN-1,D2
        BGE   INL1            ; buffer full: swallow, no echo
        MOVE.B  D0,(A1)+
        ADDQ.W  #1,D2
        BSR     MONCOUT         ; echo (MONCOUT preserves D0)
        BRA   INL1
INLBS   TST.W   D2
        BEQ   INL1            ; nothing to erase
        SUBQ.W  #1,D2
        SUBA.L  #$01,A1
        MOVE.B  #$08,D0
        BSR     MONCOUT
        MOVE.B  #$20,D0
        BSR     MONCOUT
        MOVE.B  #$08,D0
        BSR     MONCOUT
        BRA   INL1
INLDON  CLR.B   (A1)            ; NUL terminator
        MOVE.B  #$0D,D0
        BSR     MONCOUT
        MOVE.B  #$0A,D0
        BSR     MONCOUT
        MOVE.W  D2,D0
        RTS

;---------------------------------------------------------------------
; CHRGET / CHRGOT -- the text scanner.  A6 (TXTPTR) points at the
; last character read.  CHRGET advances and reads; CHRGOT re-reads.
; Both skip nothing else; CHRGET skips spaces.  See the header for
; the flag contract (Z=1 iff terminator: NUL or ':').
;---------------------------------------------------------------------
CHRGET  ADDQ.L  #1,A6
CHRGOT  MOVE.B  (A6),D0
        BEQ   CGDONE          ; NUL: Z=1 already
        CMPI.B  #$20,D0
        BEQ   CHRGET          ; skip spaces
        CMPI.B  #$3A,D0         ; ':' -> Z=1, else Z=0
CGDONE  RTS

;---------------------------------------------------------------------
; LINGET -- read a line number into LINNUM (0-63999).
; Entered with D0.B = current char (A6 points at it).  If it is not
; a digit, LINNUM is 0 and nothing is consumed.  On exit D0.B is
; the terminating char and A6 points at it.  Overflow is ?SN ERROR.
;---------------------------------------------------------------------
LINGET  MOVEQ   #0,D2           ; accumulator
LGN1    CMPI.B  #$30,D0
        BCS   LGDONE
        CMPI.B  #$39,D0
        BHI   LGDONE
        MOVE.L  D2,D1           ; acc = acc*10 + digit
        LSL.L   #2,D2
        ADD.L   D1,D2
        ADD.L   D2,D2
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        SUBI.B  #$30,D1
        ADD.L   D1,D2
        CMPI.L  #63999,D2
        BHI     SNERR
        BSR     CHRGET
        BRA   LGN1
LGDONE  MOVE.W  D2,LINNUM
        RTS

;---------------------------------------------------------------------
; CRUNCH -- tokenize the line in BUF, in place.
; Entered with A6 pointing at the first character to crunch (for a
; numbered line: the first char after the line number; for a direct
; line: its first char).  The crunched text is written from BUF
; start; the destination never overtakes the source, because a
; keyword of length >= 1 becomes one byte and everything else is
; copied 1:1 (the original's argument).  COUNT (byte) receives the
; crunched length including the terminating NUL.  On exit A6 =
; BUF-1, ready for direct execution.
;
; Rules, mirroring the original CRUNCH:
;   - spaces are stored as-is
;   - '?' becomes the PRINT token
;   - chars '0'..';' are stored straight (digits, ':', ';')
;   - inside a string literal nothing is tokenized
;   - after a REM token only the terminating NUL matters
;   - after a DATA token, ':' re-enables tokenizing (strings in
;     DATA are still respected)
;   - keyword matching is a plain prefix match against RESLST in
;     order (so GOTO wins over GO, INPUT# over INPUT only where the
;     longer word is actually present, and FOR inside BEFORE would
;     crunch too -- the original warns about exactly this)
; State (D7): 0 normal, 1 in string, 2 after REM, 3 in DATA,
; 4 in string inside DATA.
;---------------------------------------------------------------------
CRUNCH  MOVEA.L A6,A3           ; source cursor (at current char)
        LEA     BUF,A4          ; destination cursor
        MOVEQ   #0,D7           ; state = normal
CRNL    MOVE.B  (A3),D0
        BEQ     CRNEND          ; NUL: store it and finish
        TST.B   D7
        BEQ   CRNNORM
        CMPI.B  #2,D7
        BEQ   CRNSTORE        ; after REM: copy verbatim
        CMPI.B  #1,D7
        BEQ   CRNSTR
        CMPI.B  #4,D7
        BEQ   CRNSTRD
        ; state 3 (DATA): copy; ':' -> normal; '"' -> string-in-DATA
        MOVE.B  D0,(A4)+
        ADDQ.L  #1,A3
        CMPI.B  #$3A,D0
        BEQ   CRND0
        CMPI.B  #$22,D0
        BNE   CRNL
        MOVEQ   #4,D7
        BRA   CRNL
CRND0   MOVEQ   #0,D7
        BRA   CRNL
CRNSTR  MOVE.B  D0,(A4)+        ; in string: copy; '"' closes
        ADDQ.L  #1,A3
        CMPI.B  #$22,D0
        BNE   CRNL
        MOVEQ   #0,D7
        BRA   CRNL
CRNSTRD MOVE.B  D0,(A4)+        ; string in DATA: '"' closes to DATA
        ADDQ.L  #1,A3
        CMPI.B  #$22,D0
        BNE   CRNL
        MOVEQ   #3,D7
        BRA   CRNL
CRNSTORE MOVE.B D0,(A4)+
        ADDQ.L  #1,A3
        BRA   CRNL
