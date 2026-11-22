;=====================================================================
; EXT1 -- extension phase, batch 1 (EXT flavours only; this part
; is not in the faithful builds at all).  Features follow MS
; Extended BASIC (CoCo) forms and semantics, implemented from
; scratch for this port -- no Searle or MS 6809 code is used.
;
;   &H hex literals        FE_HEX (+ CRNAMP on the CRUNCH side)
;   USR                    USRFN, vector USRVEC (see below)
;   DEEK / DOKE            DEEKFN / DOKEH (16-bit, big-endian)
;   LEEK / LOKE            LEEKFN / LOKEH (32-bit, big-endian)
;   INSTR                  FE_INSTR
;   ELSE                   ELSESCAN (in the IF part) + FT_ELSE
;
; USRVEC -- the USR dispatch vector: a WORD at ZPBASE+$334,
; holding the LOGICAL address of the user routine (physical =
; ZPBASE + logical, the PEEK/POKE mapping).  The slot sits just
; past ZPSIZE, so INIT's clear loop never touches it; the EXT
; INIT part clears it explicitly at cold start, and NEW leaves
; it alone (a set vector survives, like the original's RAM
; USRLOC).  0 = unset.  Host setup (from EhBASIC on the board,
; or any POKE): write the routine's logical address as two
; bytes, high byte at logical $334, low byte at logical $335 --
; e.g. for a routine at logical $6000: POKE 820,96: POKE 821,0
; (820 = $334).  The routine is called with A0 pointing at FAC
; (the argument; the result is whatever it leaves in FAC and
; FACSIGN) and must return with RTS.
;=====================================================================
USRVEC  EQU     ZPBASE+$334     ; EXT1: USR vector (word, logical)

;---------------------------------------------------------------------
; FCERR -- ?FC ERROR.  The faithful core maps the original's FC
; class onto ?IQ in shared helpers (see GETADR, MID), but the
; original's USR mechanism literally starts with the vector
; pointing AT the FC error routine (m6502.asm: USRLOC initially
; ADR(FCERR)), and MS Extended raises FC for an INSTR start
; below 1 -- so EXT1 gives the class its own stub.
;---------------------------------------------------------------------
FCERR   MOVE.W  #$4643,D2       ; "FC"
        BRA     ERROR

;---------------------------------------------------------------------
; UFLOAT -- FAC := the unsigned 32-bit integer in D0.L.
; The mantissa field is staged through MANTMP with byte stores
; (FAC+1 is an odd address; the M5e discipline).  Exponent 160
; makes the 40-bit field (value << 8) read as the value itself;
; NORMALIZE then shifts it into canonical form (and a zero
; value falls out as ZERO_FAC through NORMALIZE's own path).
;---------------------------------------------------------------------
UFLOAT  CLR.B   VALTYP          ; numeric result
        MOVE.L  D0,MANTMP
        MOVE.B  MANTMP,FAC+1
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        CLR.B   FACOV
        CLR.B   FACSIGN
        MOVE.B  #$A0,FAC        ; exponent 160
        BRA     NORMALIZE

;---------------------------------------------------------------------
; WORDVAL -- FAC := the unsigned word in D0.W (0..65535).
; 0..32767 take GIVAYF (whose signed result is then exact);
; 32768..65535 go through UFLOAT so they stay positive (the
; PEEK/DEEK family reports unsigned values).
;---------------------------------------------------------------------
WORDVAL TST.W   D0
        BPL     GIVAYF
        MOVEQ   #0,D1
        MOVE.W  D0,D1
        MOVE.L  D1,D0
        BRA     UFLOAT

;---------------------------------------------------------------------
; FE_HEX -- the &H hex literal, entered from FE_VAR with A6 at
; '&' and D0 = '&'.  '&' 'H' must follow, then 1..8 hex digits
; (uppercase A-F, like the port's uppercase-only keywords).
; The value is UNSIGNED (a deliberate departure from CoCo's
; 16-bit signed reading: logical addresses here are $30000-
; class, so &H30000 must be a plain positive number): up to
; 32767 it takes the integer path (GIVAYF), above that it is
; floated exactly (UFLOAT) -- the same value the equivalent
; decimal literal produces.  The exit contract is FIN's: A6/D0
; hold the character that ended the literal.  No digits, or a
; 9th digit, is ?SN ERROR.
;---------------------------------------------------------------------
FE_HEX  BSR     CHRGET          ; step past '&': D0 = next char
        CMPI.B  #$48,D0         ; 'H' must follow
        BNE     SNERR
        MOVEQ   #0,D2           ; D2.L = the accumulated value
        MOVEQ   #0,D5           ; D5.W = the digit count
FHX_LP  BSR     CHRGET          ; next character
        MOVEQ   #0,D1
        MOVE.B  D0,D1           ; classify (upper bits zeroed)
        CMPI.B  #$30,D1
        BCS     FHX_END         ; below '0': terminator
        CMPI.B  #$39,D1
        BLS     FHX_DIG         ; '0'..'9'
        CMPI.B  #$41,D1
        BCS     FHX_END         ; between '9' and 'A': terminator
        CMPI.B  #$46,D1
        BHI     FHX_END         ; above 'F': terminator
        SUBI.B  #$37,D1         ; 'A'..'F' -> 10..15
        BRA     FHX_ACC
FHX_DIG SUBI.B  #$30,D1         ; '0'..'9' -> 0..9
FHX_ACC ADDQ.W  #1,D5
        CMPI.W  #8,D5
        BHI     SNERR           ; a 9th digit: ?SN ERROR
        LSL.L   #4,D2
        ADD.L   D1,D2
        BRA     FHX_LP
FHX_END TST.W   D5
        BEQ     SNERR           ; &H with no digits: ?SN ERROR
        MOVE.L  #$7FFF,D1
        CMP.L   D1,D2
        BHI     FHX_BIG
        MOVE.W  D2,D0
        BRA     GIVAYF          ; <= 32767: integer path
FHX_BIG MOVE.L  D2,D0
        BRA     UFLOAT          ; > 32767: exact unsigned float

;---------------------------------------------------------------------
; CRNAMP -- CRUNCH side of &H (entered from the EXT CRNNORM
; with D0 = '&', A3 at '&', A4 = destination).  If the next
; character is 'H', '&', 'H' and the following hex digits are
; copied VERBATIM: without this, CRUNCH's prefix matching
; would tokenize the digit run (&HDEF -> DEF token, &HEND ->
; END token) and corrupt the literal.  Anything else falls
; back to ordinary keyword matching (CRNMUST) -- '&' itself
; matches no keyword, exactly as in the faithful flavour.
;---------------------------------------------------------------------
CRNAMP  MOVE.B  1(A3),D0        ; the character after '&'
        CMPI.B  #$48,D0         ; 'H'?
        BNE     CRNMUST         ; no: ordinary keyword matching
        MOVE.B  #$26,(A4)+      ; copy '&'
        ADDQ.L  #1,A3
        MOVE.B  #$48,(A4)+      ; copy 'H'
        ADDQ.L  #1,A3
CRNHX   MOVE.B  (A3),D0         ; copy the hex digits verbatim
        CMPI.B  #$30,D0
        BCS     CRHX_END
        CMPI.B  #$39,D0
        BLS     CRHX_CP         ; '0'..'9'
        CMPI.B  #$41,D0
        BCS     CRHX_END
        CMPI.B  #$46,D0
        BHI     CRHX_END        ; not a hex digit: done
CRHX_CP MOVE.B  D0,(A4)+
        ADDQ.L  #1,A3
        BRA     CRNHX
CRHX_END BRA    CRNL             ; the terminator is reprocessed
                                ; by the main loop (state stays 0)

;---------------------------------------------------------------------
; Statement tails for the EXT FETCH dispatch.  Each loads its
; handler and joins FT_PRIME, which reproduces the dispatch's
; own contract (prime with CHRGET, JSR, continue at EXEC).
; ELSE as a statement (reached on the TRUE path of an IF, or
; standing alone) skips the rest of the line: REMH is exactly
; that handler.
;---------------------------------------------------------------------
FT_ELSE LEA     REMH(PC),A0
        BRA     FT_PRIME
FT_DOKE LEA     DOKEH(PC),A0
        BRA     FT_PRIME
FT_LOKE LEA     LOKEH(PC),A0
FT_PRIME BSR    CHRGET          ; prime the next char
        JSR     (A0)            ; handler returns here...
        BRA     EXEC            ; ...and EXEC processes the
                                ; terminator, as after a dispatch

;---------------------------------------------------------------------
; Function dispatch stubs (from the EXT FE_U3): USR, DEEK and
; LEEK take the standard one-argument numeric shape (FE_UFN:
; CHKOPN, FRMEVL, CHKCLS, CHKNUM, then JSR (A2) -- so a string
; argument is ?TM ERROR before the handler runs).  INSTR has
; its own argument shape and is entered directly.
;---------------------------------------------------------------------
FE_USR  LEA     USRFN(PC),A2
        BRA     FE_UFN
FE_DEEK LEA     DEEKFN(PC),A2
        BRA     FE_UFN
FE_LEEK LEA     LEEKFN(PC),A2
        BRA     FE_UFN

;---------------------------------------------------------------------
; USRFN -- the USR function (the original's USR, m6502.asm:
; the argument is in FAC, the call goes through a RAM vector,
; the result is what the routine leaves in FAC).  An unset
; vector (0) is ?FC ERROR -- the original initializes its
; vector to the FCERR routine itself, so an unconfigured USR
; has always reported FC.  A string argument is ?TM ERROR
; (FE_UFN's CHKNUM already ran).  The routine is called with
; A0 pointing at FAC and must RTS back.
;---------------------------------------------------------------------
USRFN   MOVEQ   #0,D0
        MOVE.B  USRVEC,D0       ; vector high byte
        LSL.W   #8,D0
        MOVE.B  USRVEC+1,D0     ; vector low byte (logical addr)
        TST.W   D0
        BEQ     FCERR           ; unset: ?FC ERROR
        MOVEA.L #ZPBASE,A1
        ADDA.L  D0,A1           ; logical -> physical entry point
        LEA     FAC,A0          ; A0 -> FAC (argument / result)
        JSR     (A1)
        RTS

;---------------------------------------------------------------------
; DEEKFN / LEEKFN -- the 16/32-bit peeks.  The address goes
; through GETADR (the PEEK/POKE logical mapping and its range
; errors, unchanged).  The value is assembled BYTE BY BYTE, so
; an odd logical address is as safe as an even one (the port's
; no-odd-access discipline holds for user addresses too -- no
; address error on the real CPU).  Big-endian, unsigned:
; DEEK returns 0..65535, LEEK 0..4294967295 (exact in FAC).
;---------------------------------------------------------------------
DEEKFN  BSR     GETADR          ; A0 = physical address
        MOVEQ   #0,D0
        MOVE.B  (A0),D0         ; high byte
        LSL.W   #8,D0
        MOVE.B  1(A0),D0        ; low byte
        BRA     WORDVAL         ; unsigned word -> FAC
LEEKFN  BSR     GETADR
        MOVEQ   #0,D0
        MOVE.B  (A0),D0
        LSL.L   #8,D0
        MOVE.B  1(A0),D0
        LSL.L   #8,D0
        MOVE.B  2(A0),D0
        LSL.L   #8,D0
        MOVE.B  3(A0),D0        ; big-endian long, byte-assembled
        BRA     UFLOAT          ; unsigned long -> FAC

;---------------------------------------------------------------------
; GETWORD -- convert FAC to a word in D2.W (GETBYTE's mirror:
; the integer must satisfy 0 <= v <= 65535, else ?IQ ERROR).
; Leaves D0.B = CHRGOT's current char, as GETBYTE does.
;---------------------------------------------------------------------
GETWORD BSR     CHKNUM
        TST.B   FACSIGN
        BMI     GWERR
        BSR     QINT
        TST.B   FAC+1
        BNE     GWERR
        TST.B   FAC+2
        BNE     GWERR
        MOVEQ   #0,D2
        MOVE.B  FAC+3,D2        ; high byte
        LSL.W   #8,D2
        MOVE.B  FAC+4,D2        ; low byte
        BRA     CHRGOT
GWERR   BRA     IQERR

;---------------------------------------------------------------------
; DOKEH / LOKEH -- the 16/32-bit pokes, POKEH's exact shape:
; FRMNUM, GETADR (the shared logical mapping), comma, FRMNUM,
; range-checked conversion, byte-wise big-endian store (odd
; addresses safe).  DOKE's value must be 0..65535 (GETWORD);
; LOKE's must satisfy 0 <= v < 2^32: negative or exponent
; above 160 is ?IQ ERROR, and QINT then leaves the exact
; 32-bit value in FAC+1..FAC+4.
;---------------------------------------------------------------------
DOKEH   BSR     FRMNUM          ; address -> FAC
        BSR     GETADR          ; A0 = physical address
        MOVE.L  A0,-(SP)        ; (FRMNUM below clobbers A0)
        MOVE.B  #$2C,D0         ; ','
        BSR     SYNCHR
        BSR     FRMNUM          ; value -> FAC
        BSR     GETWORD         ; D2.W = the word (0..65535)
        MOVEA.L (SP)+,A0
        MOVE.W  D2,D0
        LSR.W   #8,D0
        MOVE.B  D0,(A0)         ; high byte first (big-endian)
        MOVE.B  D2,1(A0)        ; low byte
        RTS
LOKEH   BSR     FRMNUM          ; address -> FAC
        BSR     GETADR          ; A0 = physical address
        MOVE.L  A0,-(SP)
        MOVE.B  #$2C,D0         ; ','
        BSR     SYNCHR
        BSR     FRMNUM          ; value -> FAC (FRMNUM type-checks)
        TST.B   FACSIGN
        BMI     IQERR           ; negative: ?IQ ERROR
        CMPI.B  #$A0,FAC
        BHI     IQERR           ; exponent > 160: value >= 2^32
        BSR     QINT            ; FAC+1..FAC+4 = the 32-bit value
        MOVEA.L (SP)+,A0        ; (QINT preserves A0; the parked
                                ; copy is popped for symmetry)
        MOVE.B  FAC+1,(A0)
        MOVE.B  FAC+2,1(A0)
        MOVE.B  FAC+3,2(A0)
        MOVE.B  FAC+4,3(A0)     ; big-endian, byte by byte
        RTS

;---------------------------------------------------------------------
; FE_INSTR -- INSTR([start,] target$, seek$) (MS Extended):
; the 1-based position of the first occurrence of seek$ in
; target$ at or after start, or 0 when there is none.  An
; empty seek$ matches at start itself; a start beyond the
; target's length finds nothing (0).  A start below 1 is ?FC
; ERROR (the MS Extended ruling); a start of 32768 or more
; takes AYINT's ?IQ, the port's word-conversion discipline.
; Argument parsing follows FE_MID's pattern (values parked on
; the stack across nested evaluations; the target descriptor
; address rides in STRNG1 afterwards).  The search reads both
; descriptors directly -- no allocation happens during it --
; and the two argument temps are freed afterwards, seek first
; (it is the most recent temp), target second, before the
; numeric result is set up with GIVAYF.
;---------------------------------------------------------------------
FE_INSTR BSR    CHRGET          ; step past the INSTR token
        MOVE.W  #1,-(SP)        ; start position (default 1)
        BSR     CHKOPN
        BSR     FRMEVL          ; first argument
        TST.B   VALTYP
        BMI     INS_T1          ; string: it is the target
        BSR     AYINT           ; numeric: the start position
        MOVEQ   #0,D0
        MOVE.B  FAC+3,D0
        LSL.W   #8,D0
        MOVE.B  FAC+4,D0        ; D0.W = start (signed word)
        TST.W   D0
        BLE     FCERR           ; start < 1: ?FC ERROR
        MOVE.W  D0,(SP)         ; replace the parked default
        MOVE.B  #$2C,D0
        BSR     SYNCHR          ; ','
        BSR     FRMEVL          ; the target string
INS_T1  BSR     CHKSTR          ; ?TM ERROR if it is numeric
        MOVE.L  FAC+4,-(SP)     ; park the target descriptor addr
        MOVE.B  #$2C,D0
        BSR     SYNCHR          ; ','
        BSR     FRMEVL          ; the seek string
        BSR     CHKSTR
        BSR     CHKCLS
        MOVE.L  (SP)+,STRNG1    ; target descriptor address
        MOVE.W  (SP)+,D3        ; D3.W = start position (>= 1)
        MOVEA.L FAC+4,A2        ; seek descriptor
        MOVEQ   #0,D6
        MOVE.B  4(A2),D6        ; D6.W = seek length
        MOVEA.L (A2),A1         ; A1 = seek data
        MOVEA.L STRNG1,A0
        MOVEQ   #0,D7
        MOVE.B  4(A0),D7        ; D7.W = target length
        MOVEA.L (A0),A0         ; A0 = target data
        MOVEQ   #0,D4           ; D4.W = result (0 = not found)
        TST.W   D7
        BEQ     INS_FREE        ; empty target: 0
        CMP.W   D7,D3
        BHI     INS_FREE        ; start beyond the target: 0
        TST.W   D6
        BEQ     INS_HIT0        ; empty seek: matches at start
        MOVE.W  D7,D2
        SUB.W   D6,D2           ; D2.W = last possible offset
        BMI     INS_FREE        ; seek longer than target: 0
        MOVE.W  D3,D1
        SUBQ.W  #1,D1           ; D1.W = current offset (0-based)
INS_OL  CMP.W   D2,D1
        BHI     INS_FREE        ; past the last offset: 0
        MOVE.W  D1,D0           ; target index
        MOVEQ   #0,D5           ; seek index
INS_IL  CMP.W   D6,D5
        BEQ     INS_HIT         ; all seek bytes matched
        MOVE.B  0(A0,D0.W),D3   ; (D3 is dead once the empty-seek
        CMP.B   0(A1,D5.W),D3   ; check above has passed)
        BNE     INS_NX
        ADDQ.W  #1,D0
        ADDQ.W  #1,D5
        BRA     INS_IL
INS_NX  ADDQ.W  #1,D1
        BRA     INS_OL
INS_HIT MOVE.W  D1,D4
        ADDQ.W  #1,D4           ; result = offset + 1 (1-based)
        BRA     INS_FREE
INS_HIT0 MOVE.W D3,D4           ; empty seek: result = start
INS_FREE BSR    FREFAC          ; free the seek temp (the most
                                ; recent one), then the target's
        MOVEA.L STRNG1,A0
        BSR     FRETMP          ; (a non-temp frees as a no-op)
        MOVE.W  D4,D0
        BRA     GIVAYF          ; result -> FAC (exact to 255)
