;---------------------------------------------------------------------
; CHR$ -- the original's CHRSTR: convert the argument to a byte
; (CONINT: 0..255, else ?IQ ERROR) and build a one-character
; string in string space (GETSPA, so a shortage runs GC first).
; The descriptor is staged in DSCBUF and pushed onto the temp
; descriptor stack by PUTNEW, as for a string literal (FE_STR);
; its address is left in FAC+4 with VALTYP set.
;---------------------------------------------------------------------
FE_CHR  BSR     CHRGET          ; step past the CHR$ token
        BSR     CHKOPN
        BSR     FRMEVL          ; argument -> FAC
        BSR     CHKCLS
        BSR     CHKNUM          ; ?TM ERROR on a string argument
        BSR     GETBYTE         ; D2.B = the byte
        MOVE.W  D2,-(SP)        ; GETSPA (and a GC inside it) may
        MOVEQ   #1,D0           ; clobber D2: park the character
        BSR     GETSPA          ; FRESPC = the byte's address
        MOVE.W  (SP)+,D2
        MOVEA.L FRESPC,A0
        MOVE.B  D2,(A0)         ; the character itself
        MOVE.B  #1,DSCBUF+4     ; descriptor: length 1, pointer to
        MOVE.L  FRESPC,DSCBUF   ; the character
        MOVE.L  #DSCBUF,FAC+4
        MOVE.B  #$FF,VALTYP
        BRA     PUTNEW          ; push it as a temp; RTS via PUTNEW
;---------------------------------------------------------------------
; String literal (the original's STRLIT/STRLT2): stage the
; descriptor in DSCBUF and push it as a temp with PUTNEW.  A
; literal in program text is shared in place; a literal whose
; data sits below TXTTAB lives in the input buffer (a direct
; statement) and would be overwritten by the next line read, so
; it is copied into string space first -- the original tests the
; literal's page against the input buffer's for the same reason.
;---------------------------------------------------------------------
FE_STR  MOVE.L  A6,D0
        ADDQ.L  #1,D0           ; body starts after the quote
        MOVEA.L D0,A1
FE_SS   MOVE.B  (A1),D1
        BEQ   FE_SD
        CMPI.B  #$22,D1
        BEQ   FE_SD
        ADDQ.L  #1,A1
        BRA   FE_SS
FE_SD   MOVE.L  A1,D1
        SUB.L   D0,D1           ; length (a byte, as in the original)
        MOVE.L  D0,STRNG1       ; park the literal's start NOW: the
                                ; CHRGET below rewrites D0 (an early
                                ; M5a bug had the copy read from the
                                ; clobbered value -- the ZP base --
                                ; and faithfully copy its zeros)
        MOVE.B  D1,DSCBUF+4     ; staged descriptor: length, pointer
        MOVE.L  D0,DSCBUF
        MOVE.L  #DSCBUF,FAC+4   ; FAC+4..7 := descriptor address
        MOVE.B  #$FF,VALTYP
        MOVEA.L A1,A6           ; at the closing quote or NUL
        TST.B   (A6)
        BEQ   FE_NQ
        BSR     CHRGET          ; step past the closing quote
FE_NQ   MOVE.L  STRNG1,D0       ; literal below the program area?
        CMP.L   TXTTAB,D0
        BCC   FE_PN             ; no: program text, share it
        MOVEQ   #0,D2           ; yes: copy it into string space
        MOVE.B  D1,D2           ; (STRINI and a GC inside it keep
        MOVE.W  D2,D0           ; A6 and STRNG1, but not D2)
        MOVE.W  D2,-(SP)
        BSR     STRINI          ; DSCBUF := {length, string space}
        MOVE.W  (SP)+,D2
        MOVEA.L STRNG1,A0       ; copy the literal's bytes up
        MOVEA.L FRESPC,A1
        BSR     MOVSTR
FE_PN   BRA     PUTNEW          ; push the descriptor as a temp

;---------------------------------------------------------------------
; The remaining performers.  TAND/ORPERF: integer AND/OR via
; AYINT on both sides (TAND/OR).  EQUOP: NOT (EQUL's performer).
; RELOPS: relational comparison (RELOPS/NUMCMP); string
; comparison is M4.  FPWRT (^) arrived in M5d (see FPWR below).
;---------------------------------------------------------------------
TAND    BSR     AYINT
        MOVE.B  FAC+3,D6
        MOVE.B  FAC+4,D7
        BSR     CP_A2F
        BSR     AYINT
        AND.B   FAC+3,D6
        AND.B   FAC+4,D7
        MOVE.B  D6,D0
        LSL.W   #8,D0
        MOVE.B  D7,D0
        BRA     GIVAYF
ORPERF  BSR     AYINT
        MOVE.B  FAC+3,D6
        MOVE.B  FAC+4,D7
        BSR     CP_A2F
        BSR     AYINT
        OR.B    FAC+3,D6
        OR.B    FAC+4,D7
        MOVE.B  D6,D0
        LSL.W   #8,D0
        MOVE.B  D7,D0
        BRA     GIVAYF
EQUOP   BSR     AYINT
        MOVE.B  FAC+3,D0
        EORI.B  #$FF,D0
        LSL.W   #8,D0
        MOVE.B  FAC+4,D0
        EORI.B  #$FF,D0
        BRA     GIVAYF
RELOPS  MOVE.B  CPRSTR,D0
        BSR     CHKVAL
        TST.B   CPRSTR
        BNE     STRCMP          ; M5a: string comparison (STRCMP
                                ; frees both operand temps, compares
                                ; lexicographically, and finishes
                                ; through the same mask mapping as
                                ; the numeric path's REL_T)
        MOVE.B  ARISGN,D0       ; pack ARG's sign into its byte1
        ORI.B   #$7F,D0
        AND.B   D0,ARG+1
        LEA     ARG,A0
        BSR     FCOMP           ; D0: 1 / 0 / $FF (packed vs FAC)
        MOVEQ   #4,D1           ; map to the mask bit: FAC>ARG: 4,
        CMPI.B  #1,D0           ; equal: 2, FAC<ARG: 1
        BEQ   REL_T
        MOVEQ   #2,D1
        TST.B   D0
        BEQ   REL_T
        MOVEQ   #1,D1
REL_T   AND.B   CPRMASK,D1
        BNE   REL_TRUE
        MOVEQ   #0,D0
        BRA   REL_F
REL_TRUE MOVEQ  #-1,D0
REL_F   CLR.B   VALTYP
        BRA     FLOAT_BYTE      ; FAC := -1 (true) or 0 (false)
; (The ^ performer FPWR itself lives in the M5d section below.)

;---------------------------------------------------------------------
; LETCORE -- variable = expression.  (LET.)  LETH is the
; statement entry.  The target's VALTYP/INTFLG are saved across
; the evaluation (FRMEVL's PTRGET overwrites them), then the
; original's type checks apply.  String assignment is PUTSTR
; (M5a; FORPNT still holds the target's value address).
;---------------------------------------------------------------------
LETCORE MOVEQ   #1,D5           ; create the variable if needed
        BSR     PTRGET
        MOVE.L  VARPNT,FORPNT
        MOVE.B  #$B2,D0         ; '=' token
        BSR     SYNCHR
        MOVE.W  VALTYP,-(SP)    ; target VALTYP:INTFLG
        BSR     FRMEVL
        MOVE.W  (SP)+,D7
        TST.B   VALTYP
        BMI   LET_RS          ; result is a string
        TST.W   D7
        BMI     TMERR           ; target string, result numeric
        TST.B   D7
        BMI   LET_INT         ; integer target
        MOVEA.L FORPNT,A0
        BRA     ST_FAC          ; FP target: store rounded
LET_RS  TST.W   D7
        BPL     TMERR           ; target numeric, result string
        BRA     PUTSTR          ; M5a: the original's PUTSTR rules
                                ; (copy a variable-owned string-space
                                ; string first, take over a temp,
                                ; share anything else); RTS via it
LET_INT BSR     ROUND_FAC       ; integer target: the original's
        BSR     AYINT           ; LET rounds the FAC first, then
        MOVEA.L FORPNT,A0       ; AYINT range-checks and QINT floors
        MOVE.B  FAC+3,(A0)      ; it into the two value bytes
        MOVE.B  FAC+4,1(A0)
        RTS
LETH    BRA     LETCORE         ; FETCH already primed the first
                                ; letter (A6/D0), as for implicit LET

;---------------------------------------------------------------------
; FOR frames.  The original keeps FOR frames on the CPU stack;
; this port does the same, but links them with a FORSP pointer
; (the original's raw stack scan does not translate to a stack
; that also holds 4-byte return addresses).  A frame is 44 bytes:
;   +0  marker byte $81        +2  FORPNT (long)
;   +6  step value (5 bytes, at stride 2: exp,m1,m2,m3,m4)
;   +16 step sign byte         +18 limit (5 bytes, stride 2,
;                                  sign packed into m1)
;   +28 CURLIN (long)          +32 CURLINP (long)
;   +36 resume TXTPTR (long)   +40 previous FORSP (long)
; FORSP = STACKTOP means "no frames".  Frame contents and the
; NEXT exit test are the original's (FOR/NEXT in flow1.s/eval.s).
;---------------------------------------------------------------------
GTFORPNT MOVEA.L FORSP,A2       ; find the frame for FORPNT
        SUBA.L  A3,A3           ; A3 := predecessor (0 = topmost)
GT_L    CMPA.L  #STACKTOP,A2
        BEQ   GT_NF
        TST.L   FORPNT
        BNE   GT_CMP
        MOVE.L  2(A2),FORPNT    ; bare NEXT: adopt the top frame
GT_CMP  MOVE.L  2(A2),D0
        CMP.L   FORPNT,D0
        BEQ   GT_FD
        MOVEA.L A2,A3
        MOVEA.L 40(A2),A2
        BRA   GT_L
GT_FD   MOVEQ   #1,D0
        RTS
GT_NF   MOVEQ   #0,D0
        RTS
PSH_FAC5 MOVEA.L (SP)+,A0       ; park the return address: the
        BSR     ROUND_FAC       ; five data bytes are pushed UNDER
        MOVE.B  FAC+4,-(SP)     ; it (the exponent ends up lowest),
        MOVE.B  FAC+3,-(SP)     ; then the return address goes back
        MOVE.B  FAC+2,-(SP)     ; on top
        MOVE.B  FAC+1,-(SP)
        MOVE.B  FAC,-(SP)
        MOVE.L  A0,-(SP)
        RTS
FORH    MOVE.L  (SP)+,FORRET    ; park the dispatch return address:
        MOVE.B  #$80,SUBFLG     ; the frame pushed below would bury
        BSR     LETCORE         ; it (FETCH already primed the first
                                ; letter: A6/D0 as PTRGET wants)
        CLR.B   SUBFLG
        BSR     GTFORPNT        ; re-entering FOR for the same
        TST.B   D0              ; variable discards the old frame
        BEQ   FOR_NF
        MOVE.L  40(A2),D0       ; (unlink it from the FORSP list;
        MOVE.L  A3,D1           ; the bytes stay as inert stack
        BNE   FOR_UL          ; garbage, as in the original the
        MOVE.L  D0,FORSP        ; discarded frame is not reused)
        BRA   FOR_NF
FOR_UL  MOVE.L  D0,40(A3)
FOR_NF  MOVE.L  A6,-(SP)        ; find the statement terminator
        BSR     DATAN           ; (the loop's resume point)
        MOVE.L  A6,D3
        MOVE.L  (SP)+,A6
        MOVE.L  FORSP,-(SP)     ; frame: previous FORSP
        MOVE.L  D3,-(SP)        ; resume TXTPTR
        MOVE.L  CURLINP,-(SP)
        MOVE.L  CURLIN,-(SP)
        MOVE.B  #$A4,D0         ; TO token
        BSR     SYNCHR
        BSR     CHKNUM
        BSR     FRMNUM          ; limit -> FAC
        MOVE.B  FACSIGN,D0      ; pack the limit's sign into m1
        ORI.B   #$7F,D0
        AND.B   D0,FAC+1
        BSR     PSH_FAC5        ; push the limit
        BSR     CHRGOT          ; STEP ?
        CMPI.B  #$A9,D0
        BNE   FOR_DS
        BSR     CHRGET
        BSR     FRMNUM          ; step -> FAC
        BRA   FOR_ST
FOR_DS  LEA     CON_ONE(PC),A0  ; default step 1
        BSR     LD_FAC
FOR_ST  BSR     SIGN_FAC        ; push step sign, then step value
        MOVE.B  D0,-(SP)
        BSR     PSH_FAC5
        MOVE.L  FORPNT,-(SP)
        MOVE.B  #$81,-(SP)      ; the FOR token marker
        MOVE.L  SP,FORSP
        MOVEA.L FORRET,A0       ; exit by jump, not RTS: the frame
        JMP     (A0)            ; now occupies the stack top
NEXTH   MOVE.L  (SP),NEXTRET    ; park the dispatch return address:
        CLR.L   FORPNT          ; exiting pops the frame AND the
                                ; stacked return address (see NX_EXIT)
                                ; bare NEXT unless a variable named
        CMPI.B  #$41,D0         ; FETCH already primed the char
        BCS   NX_GO             ; after the NEXT token (A6/D0)
        CMPI.B  #$5A,D0
        BHI   NX_GO
        MOVEQ   #0,D5
        BSR     PTRGET
        MOVE.L  VARPNT,FORPNT
NX_GO   BSR     GTFORPNT
        TST.B   D0
        BNE   NX_FD
        BRA     NFERR           ; ?NEXT WITHOUT FOR ERROR
NX_FD   LEA     RESULT,A1       ; step value (frame stride 2) ->
        MOVE.B  6(A2),(A1)      ; contiguous, then FAC := step
        MOVE.B  8(A2),1(A1)
        MOVE.B  10(A2),2(A1)
        MOVE.B  12(A2),3(A1)
        MOVE.B  14(A2),4(A1)
        MOVEA.L A1,A0
        BSR     LD_FAC
        MOVE.B  16(A2),FACSIGN  ; the frame's step sign byte
        MOVE.L  A2,-(SP)        ; FADD_CORE clobbers A1/A2: the
        MOVEA.L FORPNT,A0       ; frame pointer rides out the
        BSR     LD_ARG          ; add on the stack
        BSR     FADD_CORE       ; FAC := variable + step
        MOVEA.L FORPNT,A0
        BSR     ST_FAC          ; store it back
        MOVEA.L (SP)+,A2
        LEA     RESULT,A1       ; compare against the limit
        MOVE.B  18(A2),(A1)
        MOVE.B  20(A2),1(A1)
        MOVE.B  22(A2),2(A1)
        MOVE.B  24(A2),3(A1)
        MOVE.B  26(A2),4(A1)
        MOVEA.L A1,A0
        BSR     FCOMP
        MOVE.B  16(A2),D1       ; exit iff FCOMP result - step
        SUB.B   D1,D0           ; sign byte == 0 (the original's
        BEQ   NX_EXIT         ; SEC/SBC test, verbatim)
        MOVE.L  A2,FORSP        ; loop back: this frame is the
        MOVE.L  28(A2),CURLIN   ; top again (frames pushed after
        MOVE.L  32(A2),CURLINP  ; it are dropped from the list)
        MOVEA.L 36(A2),A6
        RTS                     ; back to EXEC at the resume point
NX_EXIT MOVE.L  40(A2),FORSP    ; pop this frame (and any above)
        LEA     44(A2),SP       ; and reclaim its stack bytes (the
        BSR     CHRGOT          ; 6502 original does this with TXS)
        CMPI.B  #$2C,D0         ; ',' -> another NEXT variable
        BNE   NX_DONE
        BSR     CHRGET
        MOVEQ   #0,D5
        BSR     PTRGET
        MOVE.L  VARPNT,FORPNT
        BRA     NX_GO
NX_DONE MOVEA.L NEXTRET,A0      ; exit by jump through the parked
        JMP     (A0)            ; return address (SP was reset)

;=====================================================================
; M5a -- GOSUB/RETURN, the string heap (temp descriptor stack,
; GETSPA/GARBAG), string assignment, concatenation and comparison,
; and FRE.  Everything here follows the original's algorithms
; (string.s / flow2.s / misc1.s / misc2.s in the mist64 map);
; descriptors are DSCLEN (6) bytes here (4-byte pointer at +0,
; length byte at +4, pad at +5) where the original's are 3, and
; descriptor ADDRESSES ride in FAC+4..7 as a longword.
;=====================================================================

;---------------------------------------------------------------------
; GOSUB / RETURN -- the original keeps the return context on the
; CPU stack and finds it by scanning for the GOSUB token; the
; scan does not translate (this stack also holds 4-byte return
; addresses), so -- the same redesign as M3's FOR -- frames are
; linked through GOSUBSP instead.  A frame is 22 bytes:
;   +0  previous GOSUBSP (long)   +4  saved FORSP (long)
;   +8  CURLINP (long)            +12 CURLIN+OLDLIN (long)
;   +16 resume TXTPTR (long)      +20 marker word $8D00
; The resume TXTPTR points AT the ':' or NUL that ended the
; GOSUB statement; RETURN restores it and returns into EXEC,
; which processes the terminator.  The FETCH dispatch return
; address is dropped when the frame is pushed (GOTOH does the
; same), and RETURN discards everything above the frame --
; including FOR frames opened inside the subroutine, whose
; FORSP comes back from the frame, exactly as the original's
; stack reset behaves.  The original's CHKMEM stack check has
; no counterpart here (the sim stack is deep); noted in the
; M5a memo.
;---------------------------------------------------------------------
GOSUBH  BSR     LINGET          ; target line -> LINNUM
GSBSK   MOVE.B  (A6),D1         ; scan to the statement terminator
        BEQ   GSBF              ; (GOTOH's GTOSK scan, verbatim)
        CMPI.B  #$3A,D1
        BEQ   GSBF
        BSR     CHRGET
        BRA   GSBSK
GSBF    ADDQ.L  #4,SP           ; drop the FETCH return address
        MOVE.W  #$8D00,-(SP)    ; marker (GOSUB token $8D)
        MOVE.L  A6,-(SP)        ; resume TXTPTR (at the terminator)
        MOVE.L  CURLIN,-(SP)    ; CURLIN+OLDLIN
        MOVE.L  CURLINP,-(SP)
        MOVE.L  FORSP,-(SP)
        MOVE.L  GOSUBSP,-(SP)   ; previous head
        MOVE.L  SP,GOSUBSP
        BSR     FNDLIN
        BNE     USERR           ; no such line: ?US ERROR
        MOVE.W  LINNUM,CURLIN
        MOVE.L  A0,CURLINP
        LEA     5(A0),A6
        BRA     FETCH
RETURNH MOVE.L  (SP)+,GOSRET    ; park the return into EXEC (the
                                ; frame restore rewrites SP)
        MOVE.L  GOSUBSP,D0
        CMPI.L  #STACKTOP,D0
        BEQ     RGERR           ; no GOSUB in progress: ?RG ERROR
        MOVEA.L D0,A0           ; frame base
        MOVE.L  0(A0),GOSUBSP
        MOVE.L  4(A0),FORSP
        MOVE.L  8(A0),CURLINP
        MOVE.L  12(A0),CURLIN   ; CURLIN+OLDLIN together
        MOVEA.L 16(A0),A6       ; resume TXTPTR
        LEA     22(A0),SP       ; discard the frame and everything
                                ; pushed inside the subroutine
        MOVE.L  GOSRET,-(SP)
        RTS                     ; return into EXEC

;---------------------------------------------------------------------
; GETSPA -- allocate D0.W bytes at the bottom of string space
; (FRETOP grows down).  Out: FRESPC = the block's address.
; On shortage, run GARBAG once and retry; still short is
; ?OM ERROR.  (The original carries the "already collected"
; state in DATAFLG's high bit across the retry; GCSW is the
; same flag, kept local to this routine.)
;---------------------------------------------------------------------
GETSPA  MOVEQ   #0,D1
        MOVE.W  D0,D1           ; D1 = length, zero-extended
        CLR.B   GCSW
GS_TRY  MOVE.L  FRETOP,D2
        SUB.L   D1,D2
        CMP.L   STREND,D2
        BCS   GS_FAIL           ; new top would cross STREND
        MOVE.L  D2,FRETOP
        MOVE.L  D2,FRESPC
        RTS
GS_FAIL TST.B   GCSW
        BNE     OMERR
        MOVE.B  #$80,GCSW
        MOVE.L  D1,-(SP)        ; GARBAG clobbers D1: park length
        BSR     GARBAG
        MOVE.L  (SP)+,D1
        BRA     GS_TRY

;---------------------------------------------------------------------
; GARBAG -- the original's collector, verbatim in structure:
; FRETOP restarts at MEMSIZ and, pass after pass, the live
; string with the highest data address below FRETOP is moved
; up against FRETOP and its descriptor updated, until no
; unmoved live string remains.  Descriptor owners scanned:
; the temp descriptor stack, the simple variables, and (M5c)
; string array elements; the scan order and candidate rule
; match the original's.
; A descriptor is a candidate when its string is non-empty,
; its data pointer is >= the best-so-far pointer (GCLOW,
; starting at STREND -- which also excludes program-text
; literals) and < FRETOP (not yet moved).
;---------------------------------------------------------------------
GARBAG  MOVE.L  MEMSIZ,FRETOP
        MOVE.L  MEMSIZ,FRESPC
GB_FIND CLR.L   GCFN            ; no candidate yet
        MOVE.L  STREND,GCLOW
        MOVE.L  #TMPDSC,GCIDX   ; scan 1: temp descriptors
GB_T1   MOVE.L  GCIDX,D0
        CMP.L   TEMPPT,D0
        BEQ   GB_T2
        MOVEA.L GCIDX,A1
        MOVEQ   #0,D4           ; descriptor offset in slot: 0
        MOVEQ   #DSCLEN,D5      ; slot stride
        BSR     GC_CHK
        BRA   GB_T1
GB_T2   MOVE.L  VARTAB,GCIDX    ; scan 2: simple variables
GB_V1   MOVE.L  GCIDX,D0
        CMP.L   ARYTAB,D0
        BEQ   GB_T3
        MOVEA.L GCIDX,A1
        MOVE.B  (A1),D0         ; the original's CHECK_SIMPLE_
        BMI   GB_VBUMP          ; VARIABLE test, on the port's name
        MOVE.B  1(A1),D0        ; encoding: first byte's high bit
        BPL   GB_VBUMP          ; set = integer; second byte's high
        MOVEQ   #2,D4           ; bit clear = FP; else a string,
        MOVEQ   #8,D5           ; descriptor at slot+2, stride 8
        BSR     GC_CHK
        BRA   GB_V1
GB_VBUMP MOVE.L GCIDX,D0
        ADDQ.L  #8,D0
        MOVE.L  D0,GCIDX
        BRA   GB_V1
GB_T3   MOVE.L  ARYTAB,GCIDX    ; scan 3 (M5c): array elements.
GB_A1   MOVE.L  GCIDX,D0        ; Only string arrays hold
        CMP.L   STREND,D0       ; descriptors; the name encoding
        BEQ   GB_MOVE           ; tells the type as in scan 2
        MOVEA.L GCIDX,A1        ; (first byte marked = integer,
        MOVEQ   #0,D0           ; second byte clear = FP, else
        MOVE.W  2(A1),D0        ; string).  GCEND := the next
        MOVE.L  GCIDX,GCEND     ; block's base.
        ADD.L   D0,GCEND
        MOVE.B  (A1),D0
        BMI   GB_ANX            ; integer array: no descriptors
        MOVE.B  1(A1),D0
        BPL   GB_ANX            ; FP array: no descriptors
        MOVEQ   #0,D0           ; string array: step the cursor
        MOVE.B  4(A1),D0        ; to the first element
        ADD.L   D0,D0
        ADDQ.L  #6,D0
        ADD.L   D0,GCIDX
GB_AE   MOVE.L  GCIDX,D0
        CMP.L   GCEND,D0
        BCC   GB_A1             ; block done (cursor = next base)
        MOVEA.L GCIDX,A1
        MOVEQ   #0,D4           ; descriptor offset in element: 0
        MOVEQ   #DSCLEN,D5      ; element stride (descriptor size)
        BSR     GC_CHK          ; advances the cursor by DSCLEN
        BRA   GB_AE
GB_ANX  MOVE.L  GCEND,GCIDX
        BRA   GB_A1
GB_MOVE TST.L   GCFN
        BEQ   GB_DONE           ; nothing left to move: done
        MOVEA.L GCFN,A1         ; the winning descriptor's length
        MOVEQ   #0,D1
        MOVE.B  GCDSC,D1
        MOVEQ   #0,D2
        MOVE.B  4(A1,D1.W),D2   ; D2 = length
        MOVEA.L GCLOW,A0        ; block [GCLOW, GCLOW+len) moves up
        MOVE.L  GCLOW,D0        ; by (FRETOP-len) - GCLOW bytes
        ADD.L   D2,D0
        MOVEA.L D0,A1           ; BLTU: A1 = source end
        MOVE.L  FRETOP,D0
        SUB.L   D2,D0           ; destination start
        SUB.L   GCLOW,D0        ; BLTU shift
        BSR     BLTU
        MOVEA.L GCFN,A1         ; descriptor := destination start
        MOVEQ   #0,D1
        MOVE.B  GCDSC,D1
        MOVE.L  FRETOP,D0
        SUB.L   D2,D0
        MOVE.L  D0,0(A1,D1.W)
        MOVE.L  D0,FRETOP       ; the moved string is now the top
        BRA   GB_FIND
GB_DONE RTS

; GC_CHK -- one descriptor owner.  Entry: A1 = slot start,
; D4.W = descriptor offset within the slot, D5.L = slot stride.
; GCIDX always advances by the stride; a candidate updates
; GCLOW/GCFN/GCDSC.  Clobbers D0/D1.
GC_CHK  MOVE.L  GCIDX,D0
        ADD.L   D5,D0
        MOVE.L  D0,GCIDX
        MOVEQ   #0,D1
        MOVE.B  4(A1,D4.W),D1   ; length
        BEQ   GC_RTS            ; empty string: never a candidate
        MOVE.L  0(A1,D4.W),D0   ; data pointer
        CMP.L   FRETOP,D0
        BCC   GC_RTS            ; at/above FRETOP: already moved
        CMP.L   GCLOW,D0
        BCS   GC_RTS            ; below the best candidate so far
        MOVE.L  D0,GCLOW
        MOVE.L  A1,GCFN
        MOVE.B  D4,GCDSC
GC_RTS  RTS

;---------------------------------------------------------------------
; STRINI -- make room for a string of D0.W bytes and stage its
; descriptor in DSCBUF; DSCPNT remembers the descriptor address
; currently in FAC+4 (the operand the caller is about to free
; with FRETMP).  FAC+4 ends pointing at DSCBUF.
; MOVSTR -- copy D2.W bytes from A0 to A1, advancing FRESPC by
; the count (the original's MOVSTR/MOVSTR1 side effect; CAT's
; second copy lands right behind the first because of it).
;---------------------------------------------------------------------
STRINI  MOVE.L  FAC+4,DSCPNT
        MOVE.B  D0,DSCBUF+4     ; length byte (D0.W <= 255)
        BSR     GETSPA
        MOVE.L  FRESPC,DSCBUF
        MOVE.L  #DSCBUF,FAC+4
        MOVE.B  #$FF,VALTYP
        RTS
MOVSTR  MOVE.W  D2,D0           ; count rides in D0 (D2 is the loop)
        BRA   MS_2
MS_1    MOVE.B  (A0)+,(A1)+
MS_2    SUBQ.W  #1,D2
        BCC   MS_1
        ADD.L   D0,FRESPC       ; FRESPC += original count
        RTS

;---------------------------------------------------------------------
; The temp descriptor stack (PUTNEW/FRETMS/FRETMP/FREFAC).
; PUTNEW pushes the descriptor staged in DSCBUF (the original
; pushes FAC's own bytes; DSCBUF is this port's staging, see
; the ZP notes) and points FAC+4 at the new slot.  A full
; stack (NUMTMP=3 in use) is ?ST ERROR (FORMULA TOO COMPLEX).
; FRETMS releases the slot only if it is the LAST temp pushed;
; FRETMP additionally pops the string space when the freed
; temp's data starts exactly at FRETOP, and returns the
; descriptor's contents (D2.W = length, A1 = data pointer).
; FREFAC is FRETMP on the descriptor in FAC+4.
;---------------------------------------------------------------------
PUTNEW  MOVE.L  TEMPPT,D0
        MOVE.L  #TMPDSC+18,D1
        CMP.L   D1,D0
        BEQ     STERR           ; all 3 temp slots in use: ?ST
        MOVEA.L D0,A0
        MOVE.L  DSCBUF,(A0)
        MOVE.B  DSCBUF+4,4(A0)
        MOVE.L  D0,FAC+4
        MOVE.B  #$FF,VALTYP
        MOVE.L  D0,LASTPT
        ADDQ.L  #DSCLEN,D0
        MOVE.L  D0,TEMPPT
        RTS
FRETMS  CMPA.L  LASTPT,A0       ; entry: A0 = descriptor address
        BNE   FRM_RTS           ; not the last temp: Z=0, done
        MOVE.L  A0,TEMPPT       ; release: TEMPPT steps back over
        MOVE.L  A0,D1           ; it and LASTPT over the previous
        SUBQ.L  #DSCLEN,D1
        MOVE.L  D1,LASTPT
        MOVEQ   #0,D1           ; Z=1: released
FRM_RTS RTS
FRETMP  MOVEQ   #0,D2           ; entry: A0 = descriptor address
        MOVE.B  4(A0),D2        ; out: D2.W = length, A1 = data
        MOVEA.L (A0),A1
        BSR     FRETMS
        BNE   FRT_RTS           ; not released: no space pop
        CMPA.L  FRETOP,A1       ; data starts at FRETOP? then it
        BNE   FRT_RTS           ; was the newest allocation: pop
        ADD.L   D2,FRETOP       ; it back (FRETOP += length)
FRT_RTS RTS
FREFAC  MOVEA.L FAC+4,A0
        BRA     FRETMP

;---------------------------------------------------------------------
; PUTSTR -- string LET's store (the original's PUTSTR).  Entry:
; FORPNT = the target variable's value address, FAC+4 = the
; source descriptor address.  If the source string's data is
; in string space (>= FRETOP) AND its descriptor is a
; variable's (>= VARTAB), copy the data into fresh space
; first: GARBAG updates only ONE descriptor per data block,
; so two variables must never share one.  Otherwise (a temp
; descriptor, or data outside string space such as a program
; literal) the variable simply takes the descriptor over,
; releasing the temp slot if there is one.
;---------------------------------------------------------------------
PUTSTR  MOVE.L  FAC+4,DSCPNT    ; source descriptor (a ZP slot:
        MOVEA.L DSCPNT,A0       ; GETSPA/GC cannot clobber it)
        MOVE.L  (A0),D0         ; source data pointer
        CMP.L   FRETOP,D0
        BCS   PS_TAKE           ; below string space: share it
        CMPA.L  VARTAB,A0
        BCS   PS_TAKE           ; a temp descriptor: take it over
        MOVEQ   #0,D0           ; copy path: allocate, then copy
        MOVE.B  4(A0),D0        ; (the source descriptor is a
        BSR     GETSPA          ; variable's, so a GC inside
        MOVE.L  FRESPC,STRNG1   ; GETSPA updates it in place;
        MOVEA.L DSCPNT,A2       ; re-read it afterwards)
        MOVEQ   #0,D2
        MOVE.B  4(A2),D2        ; length
        MOVEA.L (A2),A0         ; source data (current address)
        MOVEA.L STRNG1,A1       ; destination block
        BSR     MOVSTR
        MOVEA.L FORPNT,A1       ; variable descriptor := the copy
        MOVE.B  4(A2),4(A1)
        MOVE.L  STRNG1,(A1)
        RTS
PS_TAKE MOVEA.L DSCPNT,A0
        BSR     FRETMS          ; release the temp slot, if any
        MOVEA.L DSCPNT,A0
        MOVEA.L FORPNT,A1
        MOVE.B  4(A0),4(A1)
        MOVE.L  (A0),(A1)
        RTS

;---------------------------------------------------------------------
; CAT -- string concatenation, entered from EV_OPDEC with the
; left operand in FAC (descriptor address in FAC+4).  Follows
; the original's CAT step for step: the left descriptor
; address rides the CPU stack across FRM_ELEMENT (a nested
; CAT in parentheses needs STRNG1 for itself), the total
; length is checked (>255 is ?LS ERROR), STRINI allocates the
; result and remembers the right descriptor in DSCPNT, the
; left data is copied in (MOVINS), the right temp is freed
; (FRETMP -- whose A1/D2 outputs feed the second copy,
; MOVSTR1), the left temp is freed, and the result descriptor
; is pushed with PUTNEW.  Control returns to the evaluator's
; operator scan (EV_OP), as the original jumps to FRMEVL2.
;---------------------------------------------------------------------
CAT     MOVE.L  FAC+4,-(SP)     ; left descriptor address
        BSR     FRM_ELEMENT     ; right operand -> FAC
        BSR     CHKSTR          ; ?TM ERROR if it is numeric
        MOVE.L  (SP)+,STRNG1    ; left descriptor address
        MOVEA.L STRNG1,A0
        MOVEQ   #0,D0
        MOVE.B  4(A0),D0        ; left length
        MOVEA.L FAC+4,A0
        MOVEQ   #0,D1
        MOVE.B  4(A0),D1        ; right length
        ADD.W   D1,D0
        CMPI.W  #255,D0
        BHI     LSERR           ; STRING TOO LONG
        BSR     STRINI          ; allocate; DSCPNT := right desc;
                                ; result descriptor staged in DSCBUF
        MOVEA.L STRNG1,A0       ; copy the left data in (MOVINS)
        MOVEQ   #0,D2
        MOVE.B  4(A0),D2
        MOVEA.L (A0),A0
        MOVEA.L FRESPC,A1
        BSR     MOVSTR          ; FRESPC advances past the left part
        MOVEA.L DSCPNT,A0       ; free the right temp; A1/D2 now
        BSR     FRETMP          ; hold its data pointer and length
        MOVEA.L A1,A0           ; copy the right data in (MOVSTR1)
        MOVEA.L FRESPC,A1
        BSR     MOVSTR
        MOVEA.L STRNG1,A0       ; free the left temp
        BSR     FRETMP
        BSR     PUTNEW          ; result descriptor -> temp stack
        BRA     EV_OP

;---------------------------------------------------------------------
; STRCMP -- string RELOPS.  Entered from RELOPS with the right
; operand's descriptor in FAC+4 and the left's in ARGDSC (both
; already type-checked by CHKVAL/CPRSTR).  The original frees
; the right temp first (FREFAC) and parks its data pointer and
; length on the stack, then frees the left (FRETMP) and
; compares: byte by byte over the shorter length, the first
; differing byte decides; a prefix tie is decided by length.
; The outcome uses the numeric path's encoding (1 = left <
; right, 0 = equal, $FF = left > right) and its mask mapping
; (REL_T, duplicated here at SC_MAP).
;---------------------------------------------------------------------
STRCMP  BSR     FREFAC          ; right: D2.W = length, A1 = data
        MOVE.L  A1,-(SP)
        MOVE.W  D2,-(SP)
        MOVEA.L ARGDSC,A0       ; left descriptor
        BSR     FRETMP          ; left: D2.W = length, A1 = data
        MOVE.W  (SP)+,D3        ; D3 = right length
        MOVEA.L (SP)+,A0        ; A0 = right data
        MOVE.W  D2,D4           ; D4 = min(left, right) length
        CMP.W   D3,D4
        BLS   SC_N
        MOVE.W  D3,D4
SC_N    MOVE.W  D4,D5           ; D5 = bytes left to compare
SC_LP   TST.W   D5
        BEQ   SC_LEN
        MOVE.B  (A1)+,D0
        CMP.B   (A0)+,D0
        BNE   SC_NE
        SUBQ.W  #1,D5
        BRA   SC_LP
SC_NE   BCS   SC_LT             ; left byte < right byte
        MOVEQ   #-1,D0          ; left byte > right byte
        BRA   SC_MAP
SC_LEN  CMP.W   D3,D2           ; prefix tie: length decides
        BEQ   SC_EQ
        BCS   SC_LT             ; left shorter: left < right
        MOVEQ   #-1,D0
        BRA   SC_MAP
SC_LT   MOVEQ   #1,D0
        BRA   SC_MAP
SC_EQ   MOVEQ   #0,D0
SC_MAP  MOVEQ   #4,D1           ; the REL_T mapping: outcome 1 ->
        CMPI.B  #1,D0           ; mask bit 4, 0 -> 2, $FF -> 1
        BEQ   SC_T
        MOVEQ   #2,D1
        TST.B   D0
        BEQ   SC_T
        MOVEQ   #1,D1
SC_T    AND.B   CPRMASK,D1
        BNE   SC_TRUE
        MOVEQ   #0,D0
        BRA   SC_F
SC_TRUE MOVEQ   #-1,D0
SC_F    CLR.B   VALTYP
        BRA     FLOAT_BYTE      ; FAC := -1 (true) or 0 (false)

;---------------------------------------------------------------------
; FRE -- FREFN: free the argument's temp if it is a string,
; run GARBAG, and float FRETOP-STREND as a SIGNED word through
; GIVAYF (the original's note applies verbatim: values over
; 32767 come out negative; with this memory map FRE(0) is
; 61436 bytes, reported as -4100).
;---------------------------------------------------------------------
FREFN   TST.B   VALTYP
        BEQ   FRF_1             ; numeric argument: nothing to free
        BSR     FREFAC
FRF_1   BSR     GARBAG
        MOVE.L  FRETOP,D0
        SUB.L   STREND,D0
        BRA     GIVAYF

;=====================================================================
; M5b -- DATA/READ/RESTORE, INPUT, ON...GOTO/GOSUB, STOP/CONT,
; GET.  The INPUT/READ pair shares the original's single item
; engine (INLOOP in the original): one pointer walks the
; variable list (A6, saved in VARTXT while the data side is
; active) and INPPTR walks the data -- a line in BUF for INPUT,
; the DATA statements for READ.  INPFLG selects the flavour:
; 0 = INPUT, $80 = READ (the original encodes READ as a
; negative flag byte too).  Invariant, as in the original:
; INPPTR always points AT a terminator (',' ':' or NUL) that
; precedes the next datum; for INPUT it starts at the ','
; sentinel planted in BUFM1.
;=====================================================================

;---------------------------------------------------------------------
; ERRDIR -- INPUT and GET are illegal in direct mode (the
; original's ERRDIR): CURLIN = $FFFF is ?ID ERROR.
;---------------------------------------------------------------------
ERRDIR  MOVE.W  CURLIN,D0
        CMPI.W  #$FFFF,D0
        BEQ     IDERR
        RTS

;---------------------------------------------------------------------
; RESTOR / RESTORE -- DATPTR := TXTTAB-1 ("before the first
; line").  RESTORE with trailing garbage is a no-op, like CLR.
;---------------------------------------------------------------------
RESTOR  MOVE.L  TXTTAB,D0
        SUBQ.L  #1,D0
        MOVE.L  D0,DATPTR
        RTS
RESTOREH TST.B  D0
        BEQ     RES_DO
        CMPI.B  #$3A,D0
        BNE     RES_RTS
RES_DO  BSR     RESTOR
RES_RTS RTS

;---------------------------------------------------------------------
; BRKGO -- the CTRL-C break (M5g).  BRKCHK branches here with
; A6 at the current statement boundary and CURLIN naming the
; line that owns it.  Mirrors the original's STOPC (and this
; port's STP_DO below): in a program, save the continue
; context -- OLDTXT := A6, OLDLIN/OLDCIP alongside -- then
; print BREAK IN <line> and go to READY.  The resume mode
; follows A6's position, exactly the distinction FETCH's own
; boundary save makes: at a ':' or NUL terminator (reached
; from EXEC) CONTMD=0 (CONT resumes through EXEC); at text-1
; of the current line (reached from FETCH, e.g. a GOTO loop)
; CONTMD=1 (CONT resumes through FETCH).  In direct mode
; nothing is saved and only BREAK prints (the original's
; DIRIS path, like STOPH).  Never returns; READY resets the
; stack, so the abandoned BSR return address is harmless.
;---------------------------------------------------------------------
BRKGO   MOVE.W  CURLIN,D0
        CMPI.W  #$FFFF,D0
        BEQ     BRK_PRT         ; direct: no save (DIRIS)
        MOVE.L  A6,OLDTXT
        MOVE.W  D0,OLDLIN
        MOVE.L  CURLINP,OLDCIP
        CLR.B   CONTMD          ; at a terminator: resume via EXEC
        MOVEA.L CURLINP,A0
        LEA     5(A0),A0        ; text-1 of the current line
        CMPA.L  A0,A6
        BNE     BRK_PRT
        MOVE.B  #1,CONTMD       ; at text-1: resume via FETCH
BRK_PRT BSR     CRDO            ; the STP_BRK print sequence:
        LEA     BRKTXT(PC),A0   ; "BREAK"
        BSR     STROUT
        MOVE.W  CURLIN,D0
        CMPI.W  #$FFFF,D0
        BEQ     BRK_OUT         ; direct: no IN-line suffix
        LEA     INTXT(PC),A0
        BSR     STROUT
        MOVE.B  #$20,D0
        BSR     MONCOUT
        MOVEQ   #0,D0
        MOVE.W  CURLIN,D0
        BSR     PRTDEC
BRK_OUT BRA     READY

;---------------------------------------------------------------------
; STOP -- save the continue context (OLDTXT at the terminator
; after STOP, CONTMD=0), print BREAK and go to READY.  The
; original shares this code with END (STOPC); ENDH above does
; the same save without the BREAK text.  Trailing garbage
; makes STOP a no-op (the original's CONTRT return), and in
; direct mode nothing is saved but BREAK still prints.
;---------------------------------------------------------------------
STOPH   TST.B   D0
        BEQ     STP_DO
        CMPI.B  #$3A,D0
        BNE     STP_RTS
STP_DO  MOVE.W  CURLIN,D0
        CMPI.W  #$FFFF,D0
        BEQ     STP_BRK         ; direct: no save (DIRIS)
        MOVE.L  A6,OLDTXT
        MOVE.W  D0,OLDLIN
        MOVE.L  CURLINP,OLDCIP
        CLR.B   CONTMD          ; CONT resumes via EXEC
STP_BRK BSR     CRDO
        LEA     BRKTXT(PC),A0   ; "BREAK"
        BSR     STROUT
        MOVE.W  CURLIN,D0       ; in a program, the original's
        CMPI.W  #$FFFF,D0       ; ENDCON->ERRFIN tail appends the
        BEQ     STP_OUT         ; INPRT suffix (" IN  20"); direct
        LEA     INTXT(PC),A0    ; mode skips it, like ERROR does
        BSR     STROUT
        MOVE.B  #$20,D0         ; (LINPRT's leading space, as in
        BSR     MONCOUT         ; ERROR's suffix)
        MOVEQ   #0,D0
        MOVE.W  CURLIN,D0
        BSR     PRTDEC
STP_OUT ADDQ.L  #4,SP           ; drop the FETCH dispatch return
        BRA     READY
STP_RTS RTS

;---------------------------------------------------------------------
; CONT -- resume where STOP/END (CONTMD=0: OLDTXT at a
; terminator, resume via EXEC) or the last statement boundary
; (CONTMD=1: OLDTXT one byte before a statement, resume via
; FETCH -- the INPUT-empty-line and ran-off-the-end cases)
; left off.  OLDTXT = 0 (boot, NEW, CLEAR, RUN, any error)
; is ?CN ERROR.  Trailing garbage makes CONT a no-op, as in
; the original (CONTRT).
; Deviation: READY resets FORSP/GOSUBSP (a port convention
; since M3), so a STOP inside a FOR loop or subroutine can
; be CONTinued into the following statements, but the loop /
; return context is gone; the original preserves its whole
; stack.  Straight-line STOP/CONT is exact.
;---------------------------------------------------------------------
CONTH   TST.B   D0
        BEQ     CT_DO
        CMPI.B  #$3A,D0
        BNE     CT_RTS
CT_DO   TST.L   OLDTXT
        BEQ     CNERR           ; nothing to continue
        MOVE.W  OLDLIN,CURLIN
        MOVE.L  OLDCIP,CURLINP
        MOVEA.L OLDTXT,A6
        ADDQ.L  #4,SP           ; drop the FETCH dispatch return
        TST.B   CONTMD
        BNE     CT_F
        BRA     EXEC
CT_F    BRA     FETCH
CT_RTS  RTS

;---------------------------------------------------------------------
; ON -- ON <byte> GOTO|GOSUB n1,n2,...  The value is a byte
; (GETBYT: outside 0..255 is ?IQ ERROR).  The list is walked
; with LINGET: the value-th number dispatches through GOTOH /
; GOSUBH (whose entry state -- A6/D0 on the first digit -- is
; arranged by the CHRGET before the branch); value 0 or a
; value past the end of the list falls through to the next
; statement (RTS into EXEC with A6 at the terminator).
;---------------------------------------------------------------------
ONH     BSR     FRMNUM          ; the selector -> FAC
        BSR     GETBYTE         ; D2.B = value; D0 = current char
        MOVE.B  D0,D6           ; D6 = the GOTO/GOSUB token
        CMPI.B  #$89,D6         ; GOTO token
        BEQ     ON_OK
        CMPI.B  #$8D,D6         ; GOSUB token
        BNE     SNERR
ON_OK   MOVE.B  D2,D7           ; D7 = countdown (LINGET and the
                                ; FP core leave D6/D7 alone)
ON_LOOP SUBQ.B  #1,D7
        BEQ     ON_GO           ; this number is the target
        BSR     CHRGET          ; step past the token (first time)
                                ; or the ',' (later) to a digit
        BSR     LINGET          ; skip the number; D0 = terminator
        CMPI.B  #$2C,D0         ; ',' -> another number follows
        BEQ     ON_LOOP
        RTS                     ; fell off the list: next statement
ON_GO   BSR     CHRGET          ; step to the target's first digit
        CMPI.B  #$8D,D6
        BEQ     ON_GSB
        BRA     GOTOH           ; (drops the dispatch return)
ON_GSB  BRA     GOSUBH          ; (likewise)

;---------------------------------------------------------------------
; QINLIN -- type "? " and read a line into BUF (the original's
; QINLIN: OUTQST + OUTSPC + INLIN).
;---------------------------------------------------------------------
QINLIN  MOVE.B  #$3F,D0         ; '?'
        BSR     OUTDO
        MOVE.B  #$20,D0
        BSR     OUTDO
        BRA     INLIN           ; D0.W = length; RTS via INLIN

;---------------------------------------------------------------------
; INPUT -- optional prompt literal, then "? " and a line,
; then the shared INLOOP over the variable list.  The first
; line being empty is the original's STPEND path: execution
; stops silently at READY, and FETCH's statement-boundary
; save (CONTMD=1) lets CONT re-run this very statement.
; ?REDO FROM START (a bad item terminator in INPUT mode)
; restarts the whole statement from INPST, prompt included,
; as the original restarts through NEWSTT from OLDTXT.
;---------------------------------------------------------------------
INPUTH  BSR     ERRDIR          ; direct mode: ?ID ERROR
        MOVE.L  A6,INPST        ; A6 at the char after the token:
                                ; the REDO restart point
        CLR.B   INPFLG          ; INPUT flavour
INP_RESTART                     ; ?REDO FROM START lands here
        MOVEA.L INPST,A6
        BSR     CHRGOT          ; D0 = char after the token
        CMPI.B  #$22,D0         ; '"' -> a prompt literal
        BNE     INP_READ
        LEA     1(A6),A1        ; type the literal's characters
INP_PL  MOVE.B  (A1),D0
        BEQ     INP_PD          ; NUL: unterminated (SYNCHR fails)
        CMPI.B  #$22,D0
        BEQ     INP_PD
        BSR     OUTDO
        ADDQ.L  #1,A1
        BRA     INP_PL
INP_PD  MOVEA.L A1,A6           ; at the closing quote (or NUL)
        BSR     CHRGET          ; step past it
        MOVE.B  #$3B,D0         ; ';'
        BSR     SYNCHR          ; required after a prompt
INP_READ BSR    QINLIN          ; "? " and a line into BUF
        TST.B   BUF
        BEQ     INP_EMPTY       ; empty first line: stop silently
        MOVE.B  #$2C,BUFM1      ; plant the ',' sentinel at BUF-1
        MOVE.L  #BUFM1,INPPTR   ; (the original stores 44 there)
        BSR     CHRGOT          ; re-prime D0 at the first variable
                                ; (QINLIN clobbered it; A6 survived)
        BRA     INLOOP
INP_EMPTY ADDQ.L #4,SP          ; drop the FETCH dispatch return
        BRA     READY

;---------------------------------------------------------------------
; READ -- the same INLOOP with the READ flavour: the data
; side is DATPTR and exhaustion searches for the next DATA
; statement (FNDDATA).  READ is legal in direct mode (the
; original has no ERRDIR here).
;---------------------------------------------------------------------
READH   MOVE.B  #$80,INPFLG     ; READ flavour (negative, as the
                                ; original's BIT tests expect)
        MOVE.L  DATPTR,INPPTR
        ; fall through into INLOOP (A6/D0 primed by FETCH; a BRA
        ; to the next instruction would encode with displacement
        ; 0, which asm68k-py mis-encodes -- the M5a lesson)

;---------------------------------------------------------------------
; INLOOP -- the shared INPUT/READ item engine (the original's
; INLOOP..VAREND).  Per variable: PTRGET (create mode), park
; the list pointer in VARTXT, switch to the data side, fetch
; one item, assign it, validate the item terminator, then
; look for ',' in the variable list.
;---------------------------------------------------------------------
INLOOP  CMPI.B  #$41,D0         ; a variable starts with a letter
        BCS     SNERR           ; (the original's PTRGET check)
        CMPI.B  #$5A,D0
        BHI     SNERR
        MOVEQ   #1,D5           ; create the variable if needed
        BSR     PTRGET
        MOVE.L  VARPNT,FORPNT   ; assignment target (PUTSTR / the
                                ; numeric store both use FORPNT)
        MOVE.L  A6,VARTXT       ; park the variable-list pointer
        MOVEA.L INPPTR,A6       ; switch to the data side
        MOVE.B  (A6),D0         ; the byte INPPTR points at is a
        BEQ     IN_NEED         ; terminator by invariant: NUL or
        CMPI.B  #$3A,D0         ; ':' means "no item here yet"
        BEQ     IN_NEED
        BRA     DATBK1          ; ',' (or the sentinel): item next
IN_NEED BSR     NEEDDATA        ; INPUT: "?? " + another line;
                                ; READ: find the next DATA
        ; fall through into DATBK1 (see PRSG2's note on BRA)
DATBK1  BSR     CHRGET          ; D0/A6 = first character of item
        TST.B   VALTYP
        BMI     STRITEM
        BSR     INPFIN          ; numeric item -> FAC
        BSR     INPASSIGN_NUM   ; store it (FORPNT, INTFLG-aware)
        BRA     STRDN2
STRITEM BSR     INPSTR          ; string item -> FAC (a temp)
        BSR     PUTSTR          ; assign it (FORPNT)
        ; fall through into STRDN2 (see READH's note on BRA)
STRDN2  BSR     CHRGOT          ; the item's terminator must be
        BEQ     TRMOK           ; NUL or ':' ...
        CMPI.B  #$2C,D0         ; ... or ','
        BEQ     TRMOK
        BRA     TRMNOK          ; anything else is bad data
TRMOK   MOVE.L  A6,INPPTR       ; the data pointer rests here
        MOVEA.L VARTXT,A6       ; back to the variable list
        BSR     CHRGOT
        BEQ     VAREND          ; terminator: list exhausted
        CMPI.B  #$2C,D0         ; ',' -> another variable
        BNE     SNERR           ; (the original's CHKCOM)
        BSR     CHRGET          ; prime the next name
        BRA     INLOOP
TRMNOK  TST.B   INPFLG          ; bad data: INPUT retries, READ errs
        BMI     TMN_READ
        LEA     TRYAGN(PC),A0   ; "?REDO FROM START"
        BSR     STROUT
        BSR     CRDO
        BRA     INP_RESTART     ; re-run the whole INPUT statement
TMN_READ MOVE.W DATLIN,CURLIN   ; the error is reported in the
        BRA     SNERR           ; DATA line, as in the original
VAREND  TST.B   INPFLG
        BMI     VE_READ
        MOVEA.L INPPTR,A0       ; INPUT: unused data on the line?
        TST.B   (A0)
        BEQ     VE_OUT          ; NUL: clean end
        LEA     EXIGNT(PC),A0   ; "?EXTRA IGNORED"
        BSR     STROUT
        BSR     CRDO
VE_OUT  RTS                     ; back into EXEC
VE_READ MOVE.L  INPPTR,DATPTR   ; READ: put the data pointer away
        RTS

;---------------------------------------------------------------------
; NEEDDATA -- the item fetch found a terminator where a
; datum should be.  INPUT reads another line: an extra '?'
; (making the prompt "?? ") and QINLIN, and the data pointer
; restarts at the BUF sentinel.  READ searches forward for
; the next DATA statement (FNDDATA).  Either way, returns
; with A6 positioned so DATBK1's CHRGET lands on the first
; character of the item (the DATA token, or BUFM1).
;---------------------------------------------------------------------
NEEDDATA TST.B  INPFLG
        BMI     FNDDATA         ; (BRA, not BSR: FNDDATA's RTS
                                ; returns into INLOOP's fall-through)
        MOVE.B  #$3F,D0         ; the extra '?'
        BSR     OUTDO
        BSR     QINLIN          ; "? " and the continuation line
        MOVE.L  #BUFM1,INPPTR
        LEA     BUFM1,A6
        RTS

;---------------------------------------------------------------------
; FNDDATA -- search forward for the next DATA statement.
; Entry: A6 = the data pointer, at a ':' or NUL inside the
; program, or at TXTTAB-1 (before the first line, where
; DATLIN need not be valid).  Statements are skipped with
; DATAN (quote-aware); every line entered updates DATLIN.
; Exit: A6 at the DATA token.  Running off the end of the
; program is ?OD ERROR.  (The original's DATLOP.)
;---------------------------------------------------------------------
FNDDATA MOVE.L  TXTTAB,D0
        SUBQ.L  #1,D0           ; TXTTAB-1 ?
        CMP.L   A6,D0
        BEQ     FD_FIRST
        MOVE.B  (A6),D0
        BEQ     FD_NEXTL        ; NUL: leave this line
        MOVEA.L A6,A5           ; ':': the next statement starts
        ADDQ.L  #1,A5           ; right after it, same line
        BRA     FD_SCAN         ; (DATLIN already names the line)
FD_FIRST MOVEA.L TXTTAB,A5      ; the first line
        TST.L   (A5)
        BEQ     ODERR           ; no program at all
        MOVE.W  4(A5),DATLIN
        LEA     6(A5),A5        ; its first statement
        BRA     FD_SCAN
FD_NEXTL MOVE.L A6,D0           ; the next line starts at the
        ADDQ.L  #1,D0           ; first even address past this
        MOVE.L  D0,D1           ; line's terminating NUL (line
        ANDI.L  #$00000001,D1   ; starts are even; at most one
        BEQ     FD_NL1          ; pad byte follows the NUL)
        ADDQ.L  #1,D0
FD_NL1  MOVEA.L D0,A5
        TST.L   (A5)
        BEQ     ODERR           ; the end marker: out of data
        MOVE.W  4(A5),DATLIN
        LEA     6(A5),A5
FD_SCAN CMPI.B  #$83,(A5)       ; DATA token?
        BEQ     FD_FOUND
        MOVEA.L A5,A6
        BSR     DATAN           ; skip this statement; A6 ends
                                ; at its ':' or NUL
        MOVE.B  (A6),D0
        BEQ     FD_NEXTL
        MOVEA.L A6,A5           ; ':' -> the next statement
        ADDQ.L  #1,A5
        BRA     FD_SCAN
FD_FOUND MOVEA.L A5,A6          ; A6 at the DATA token
        RTS

;---------------------------------------------------------------------
; INPFIN -- FIN with the original's leading-sign handling.
; The evaluator's FIN leaves a leading '-' to the unary
; operator machinery, but DATA/INPUT text is raw (never
; tokenized), and the original's FIN itself consumes a
; leading '-' or '+' (SGNFLG -> NEGOP at FINQNG).  INPFIN
; restores that for the item parser.
;---------------------------------------------------------------------
INPFIN  CMPI.B  #$2D,D0         ; '-'
        BEQ     INF_N
        CMPI.B  #$2B,D0         ; '+'
        BEQ     INF_P
        BRA     FIN
INF_N   BSR     CHRGET
        BSR     FIN
        BRA     NEGOP           ; apply the sign; RTS via NEGOP
INF_P   BSR     CHRGET
        BRA     FIN

;---------------------------------------------------------------------
; INPSTR -- scan one string item on the data side and build
; its descriptor as a temp (PUTNEW), ready for PUTSTR.
; Entry: A6/D0 = the item's first character.  A quoted item
; runs to its closing quote (or NUL); an unquoted item runs
; to ',', ':' or NUL -- leading spaces were already skipped
; by DATBK1's CHRGET, trailing spaces are data, exactly as
; in the original's STRLT2 use.  Exit: A6 at the terminator
; (unquoted) or one past the closing quote (quoted), which
; is where STRDN2 validates from.  Data below TXTTAB lives
; in BUF and is copied into string space first (the next
; line read would overwrite it); program text is shared.
;---------------------------------------------------------------------
INPSTR  MOVE.L  A6,STRNG1       ; provisional start (unquoted)
        CMPI.B  #$22,D0         ; '"' ?
        BNE     IS_U
        ADDQ.L  #1,STRNG1       ; quoted: start past the quote
        LEA     1(A6),A1
        MOVEQ   #0,D2           ; length
IS_Q1   MOVE.B  (A1),D1
        BEQ     IS_BUILD        ; NUL: unterminated; resume at NUL
        CMPI.B  #$22,D1
        BEQ     IS_QQ           ; closing quote
        ADDQ.L  #1,A1
        ADDQ.W  #1,D2
        BRA     IS_Q1
IS_QQ   ADDQ.L  #1,A1           ; resume one past the quote
        BRA     IS_BUILD
IS_U    MOVEA.L A6,A1           ; unquoted: scan from A6
        MOVEQ   #0,D2
IS_U1   MOVE.B  (A1),D1
        BEQ     IS_BUILD        ; NUL
        CMPI.B  #$2C,D1
        BEQ     IS_BUILD        ; ','
        CMPI.B  #$3A,D1
        BEQ     IS_BUILD        ; ':'
        ADDQ.L  #1,A1
        ADDQ.W  #1,D2
        BRA     IS_U1
IS_BUILD MOVE.L A1,-(SP)        ; park the resume position (the
                                ; build below clobbers A1)
        MOVE.L  STRNG1,D0
        CMP.L   TXTTAB,D0
        BCC     IS_SHARE        ; program text: share in place
        MOVE.W  D2,-(SP)        ; BUF data: copy into string space
        MOVEQ   #0,D0
        MOVE.W  D2,D0
        BSR     STRINI          ; DSCBUF := {len, fresh block}
        MOVE.W  (SP)+,D2
        MOVEA.L STRNG1,A0
        MOVEA.L FRESPC,A1
        BSR     MOVSTR
        BRA     IS_PUSH
IS_SHARE MOVE.B D2,DSCBUF+4     ; staged descriptor: length,
        MOVE.L  STRNG1,DSCBUF   ; data pointer
        MOVE.L  #DSCBUF,FAC+4
        MOVE.B  #$FF,VALTYP
IS_PUSH BSR     PUTNEW          ; push it as a temp; FAC+4 -> it
        MOVEA.L (SP)+,A6        ; the resume position
        RTS

;---------------------------------------------------------------------
; INPASSIGN_NUM -- store the FAC number into the variable at
; FORPNT: ST_FAC for a floating target, AYINT + two bytes
; for an integer (%) target -- LET's two stores, verbatim.
;---------------------------------------------------------------------
INPASSIGN_NUM
        TST.B   INTFLG
        BMI     IAN_I
        MOVEA.L FORPNT,A0
        BRA     ST_FAC          ; RTS via ST_FAC
IAN_I   BSR     AYINT
        MOVEA.L FORPNT,A0
        MOVE.B  FAC+3,(A0)
        MOVE.B  FAC+4,1(A0)
        RTS

;---------------------------------------------------------------------
; GET -- GET var: one keystroke, never waiting (the original
; reads through its one-character buffer with INPFLG=64).
; No key waiting means numeric 0 / string "".  A numeric
; variable receives the FIN parse of the single character
; (a digit key gives its digit, anything else 0) -- NOT the
; character code; a string variable receives the character
; itself.  GET# (a channel) is not part of Phase 1: the '#'
; simply fails PTRGET's letter check path with ?SN ERROR.
;---------------------------------------------------------------------
GETH    BSR     ERRDIR          ; direct mode: ?ID ERROR
        BSR     CHRGOT          ; ERRDIR clobbered D0 (it loads
                                ; CURLIN there): re-prime the
                                ; current character for PTRGET
        CMPI.B  #$41,D0         ; the variable starts with a letter
        BCS     SNERR
        CMPI.B  #$5A,D0
        BHI     SNERR
        MOVEQ   #1,D5           ; create the variable if needed
        BSR     PTRGET
        MOVE.L  VARPNT,FORPNT
        BSR     MONPOLKEY       ; M5g: is a character waiting?
                                ; (the pushback slot first, then
                                ; the ACIA; Z=1 means none)
        BEQ     GT_NK
        BRA     GT_HV           ; D0.B = the character
GT_NK   MOVEQ   #0,D0           ; no key: the NUL character
GT_HV   MOVE.B  D0,GETBUF
        CLR.B   GETBUF+1        ; GETBUF = the char + NUL
        TST.B   VALTYP
        BMI     GT_STR
        MOVE.L  A6,-(SP)        ; numeric: parse GETBUF with FIN;
        LEA     GETBUF,A6       ; the statement's A6 (at its
        SUBQ.L  #1,A6           ; terminator) is parked meanwhile
        BSR     CHRGET          ; D0 = the char (or NUL)
        BSR     INPFIN
        BSR     CHRGOT          ; D0 = the terminator FIN stopped
        BEQ     GT_ASN          ; at: NUL is fine, and so is ','
        CMPI.B  #$2C,D0         ; (the original's INPUT_MORE
        BEQ     GT_ASN          ; accepts both) -- anything else
        MOVE.W  #$FFFF,CURLIN   ; is the original's GET trap in
        BRA     SNERR           ; INPUTERR: it poisons CURLIN so
                                ; the ?SYNTAX ERROR prints with no
                                ; " IN n" suffix, then SYNERR
GT_ASN  BSR     INPASSIGN_NUM
        MOVEA.L (SP)+,A6
        RTS
GT_STR  MOVE.B  GETBUF,D2
        BEQ     GT_E            ; no key: the empty string
        MOVE.W  D2,-(SP)        ; build the character in string
        MOVEQ   #1,D0           ; space, exactly as CHR$ does
        BSR     GETSPA
        MOVE.W  (SP)+,D2
        MOVEA.L FRESPC,A0
        MOVE.B  D2,(A0)
        MOVE.B  #1,DSCBUF+4
        MOVE.L  FRESPC,DSCBUF
        BRA     GT_P
GT_E    CLR.B   DSCBUF+4        ; length 0 (pointer never read)
        MOVE.L  FRESPC,DSCBUF
GT_P    MOVE.L  #DSCBUF,FAC+4
        MOVE.B  #$FF,VALTYP
        BSR     PUTNEW
        BRA     PUTSTR          ; assign to FORPNT; RTS via PUTSTR

;=====================================================================
; M5d -- the rest of the math pack and the function table:
; FPWRT (^), SQR, LOG, EXP, SIN/COS/TAN/ATN, RND, the polynomial
; evaluator, POS, PEEK/POKE/WAIT, and the remaining string
; functions (LEN, ASC, VAL, STR$, LEFT$/RIGHT$/MID$).
;
; The algorithms are the original's, step for step, including
; its constant tables (converted from the math pack's RADIX 8
; listing to hex; every constant is the 5-byte ADDPRC form).
; Two port notes:
;  - The original has ONE extension byte (FACOV), living on
;    the FAC side; an ARG field is always [mantissa][0].
;    The port's FADD core consults each operand's own slot
;    (FACOV / ARGEXT), so ARGEXT must be 0 wherever the
;    original's shared-byte semantics are in play (EXP's
;    FSUBT sets FACOV := OLDOV and ARGEXT := 0 -- loading
;    both slots with OLDOV cancels the extension in the
;    subtraction and loses the fraction's low byte).
;  - MOVMF/MOVAF/MOVEF/MOVFA in the original all zero FACOV
;    after the copy/store ("zero it since rounded"); the
;    port's ST_FAC / CP_F2A(R) / CP_A2F do the same.
;=====================================================================

;---------------------------------------------------------------------
; NEGOP_F -- FAC := -FAC, but a zero FAC keeps its positive
; sign: the original's NEGOP tests FACEXP first.  (The
; evaluator's NEGOP performer flips unconditionally; the math
; pack's internal negations all use this form.)
; MOV1F / MOV2F -- FAC -> TEMPF1 / TEMPF2, rounded (ST_FAC),
; with FACOV cleared (the original's MOVMF side effect).
; FSUB_MEM -- FAC := (packed value at A0) - FAC: load ARG from
; memory, then FSUB_CORE (which flips FACSIGN and recomputes
; SGNCPR from ARISGN).
;---------------------------------------------------------------------
NEGOP_F TST.B   FAC
        BEQ     NF_R
        EORI.B  #$FF,FACSIGN
NF_R    RTS
MOV1F   MOVEA.L #TEMPF1,A0
        BRA     MOVMF2
MOV2F   MOVEA.L #TEMPF2,A0
MOVMF2  BSR     ST_FAC
        CLR.B   FACOV
        RTS
FSUB_MEM BSR    LD_ARG
        BRA     FSUB_CORE

;---------------------------------------------------------------------
; POLY / POLYX -- the original's polynomial evaluators.
; A0 points at a table: a degree byte N, then N+1 packed
; constants, HIGHEST degree first.  POLY evaluates
; C0*x^N + C1*x^(N-1) + ... + CN by Horner's rule; POLYX
; evaluates P(x^2)*x (odd polynomials: SIN, ATN, LOG).
; The multiply operand alternation is the original's: the
; first FMULT uses the leading constant, later ones the saved
; argument in TEMPF2.
;---------------------------------------------------------------------
POLYX   MOVE.L  A0,POLYPT
        BSR     MOV1F           ; TEMPF1 := x
        MOVEA.L #TEMPF1,A0
        BSR     FMULT_MEM       ; FAC := x * x
        BSR     POLY1
        MOVEA.L #TEMPF1,A0
        BRA     FMULT_MEM       ; FAC := P(x^2) * x
POLY    MOVE.L  A0,POLYPT
POLY1   BSR     MOV2F           ; TEMPF2 := x
        MOVEA.L POLYPT,A0
        MOVE.B  (A0)+,DEGREE
        MOVE.L  A0,POLYPT
        BSR     FMULT_MEM       ; FAC := x * C0
POLY2   MOVE.L  POLYPT,D0
        ADDQ.L  #5,D0
        MOVE.L  D0,POLYPT
        MOVEA.L D0,A0
        BSR     FADD_MEM        ; FAC += C(i)
        SUBQ.B  #1,DEGREE
        BEQ     POLY_R          ; done: no trailing multiply
        MOVEA.L #TEMPF2,A0
        BSR     FMULT_MEM       ; FAC *= x
        BRA     POLY2
POLY_R  RTS

;---------------------------------------------------------------------
; MLDEXP -- scale FAC by 2^(S-128): FACEXP := FACEXP + S - 128,
; where D0.B = S (the caller's saved scale byte) and ARISGN
; becomes the result sign.  Out-of-range high is ?OV ERROR;
; zero or negative (or S = 0, the original's entry test) is
; FAC := 0.  (MLDEXP / MULDIV's exponent fixup.)
;---------------------------------------------------------------------
MLDEXP  TST.B   D0
        BEQ     ZERO_FAC        ; S = 0: underflow (tail call)
        MOVEQ   #0,D1
        MOVE.B  FAC,D1
        MOVEQ   #0,D2
        MOVE.B  D0,D2
        ADD.W   D2,D1
        SUBI.W  #128,D1         ; R = S + FACEXP - 128
        CMPI.W  #255,D1
        BHI     OVERR
        TST.W   D1
        BLE     ZERO_FAC        ; R <= 0: underflow to zero
        MOVE.B  D1,FAC
        MOVE.B  ARISGN,FACSIGN
        RTS

;---------------------------------------------------------------------
; LOG -- natural log.  FAC <= 0 is ?IQ ERROR (the original's
; FCERR).  LN(F*2^N) = (N + LOG2(F)) * LN(2), with F reduced
; to [0.5,1) and LOG2(F) from the POLYX approximation of
; (F-SQR(.5))/(F+SQR(.5)) -- computed by the original's own
; detour: 1 - SQR(2)/(F+SQR(.5)).
; FINLOG -- FAC += the integer in D0.W (LOG's N), shaped
; exactly like the original: the sum's other operand is the
; rounded FAC in ARG with NO extension byte.
;---------------------------------------------------------------------
LOG_FN  BSR     SIGN_FAC
        BEQ     IQERR           ; LOG(0)
        BMI     IQERR           ; LOG of a negative
        MOVEQ   #0,D7
        MOVE.B  FAC,D7
        SUBI.W  #128,D7         ; N = FACEXP - 128
        MOVE.W  D7,-(SP)
        MOVE.B  #$80,FAC        ; F in [0.5,1)
        LEA     SQRHLF(PC),A0
        BSR     FADD_MEM        ; FAC += SQR(0.5)
        LEA     SQRTWO(PC),A0
        BSR     FDIV_MEM        ; FAC := SQR(2) / FAC
        LEA     FONE(PC),A0
        BSR     FSUB_MEM        ; FAC := 1 - FAC
        LEA     LOGCN2(PC),A0
        BSR     POLYX           ; LOG2 approximation
        LEA     NEGHLF(PC),A0
        BSR     FADD_MEM        ; FAC += -1/2
        MOVE.W  (SP)+,D0
        BSR     FINLOG          ; FAC += N
        LEA     LOG2C(PC),A0
        BRA     FMULT_MEM       ; FAC *= LN(2)
FINLOG  MOVE.W  D0,-(SP)        ; park N (CP_F2AR clobbers D0)
        BSR     CP_F2AR         ; ARG := FAC (rounded, as MOVAF)
        CLR.B   ARGEXT          ; MOVAF leaves no extension
        MOVE.W  (SP)+,D0
        BSR     GIVAYF          ; FAC := N (signed)
        MOVE.B  ARISGN,D0       ; SGNCPR := ARG sign xor FAC sign
        MOVE.B  FACSIGN,D1
        EOR.B   D1,D0
        MOVE.B  D0,SGNCPR
        BRA     FADD_CORE

;---------------------------------------------------------------------
; EXP -- e^x via 2^(x*LOG2(e)): the integer part of
; y = x*LOG2(e) scales the result at the end (MLDEXP); the
; fractional part goes through the POLY approximation of
; 2^(1-frac) evaluated at (INT(y)+1)*LN(2) - y... in the
; original's own arrangement: FAC := -frac(y), POLY, scale.
; The pre-INT extension byte, biased by +$50, is saved in
; OLDOV and restored into BOTH extension slots for the
; fraction subtraction (see the section header note).
; MLDVEX -- the original's overflow/underflow fork: a positive
; argument overflows (?OV ERROR), a negative one underflows
; to zero.
;---------------------------------------------------------------------
EXP_FN  LEA     LOGEB2(PC),A0
        BSR     FMULT_MEM       ; FAC := y = x * LOG2(e)
        MOVE.B  FACOV,D0
        ADDI.B  #$50,D0         ; the rounding bias (ADCI 120 oct)
        BCC     EXP_S1
        BSR     INC_FAC_M       ; carried: increment the mantissa
        BNE     EXP_S1
        MOVE.B  #$80,FAC+1      ; mantissa wrapped (RNDSHF):
        CLR.B   FAC+2           ; $80000000, exponent + 1
        CLR.B   FAC+3
        CLR.B   FAC+4
        CLR.B   FACOV
        ADDQ.B  #1,FAC
        BEQ     OVERR
EXP_S1  MOVE.B  D0,OLDOV
        BSR     CP_F2A          ; MOVEF: ARG := y (no rounding)
        CLR.B   FACOV           ; (the original zeroes FACOV)
        CMPI.B  #136,FAC        ; |y| >= 128 (210 octal): too big
        BCC     MLDVEX
        BSR     INTFN           ; FAC := INT(y), INTEGR saved
        MOVE.B  INTEGR,D6       ; the integer's low byte
        MOVE.B  D6,D0
        ADDI.B  #$81,D0
        BEQ     MLDVEX          ; INTEGR = 127: overflow
        MOVEQ   #0,D7
        MOVE.B  D6,D7
        ADDI.B  #$80,D7         ; scale byte = INTEGR + 128
        MOVE.W  D7,-(SP)        ; (PHA in the original)
        MOVE.B  FAC,D0          ; swap FAC <-> ARG: exponent,
        MOVE.B  ARG,FAC         ; mantissa, extension, sign
        MOVE.B  D0,ARG
        MOVE.B  FAC+1,D0
        MOVE.B  ARG+1,FAC+1
        MOVE.B  D0,ARG+1
        MOVE.B  FAC+2,D0
        MOVE.B  ARG+2,FAC+2
        MOVE.B  D0,ARG+2
        MOVE.B  FAC+3,D0
        MOVE.B  ARG+3,FAC+3
        MOVE.B  D0,ARG+3
        MOVE.B  FAC+4,D0
        MOVE.B  ARG+4,FAC+4
        MOVE.B  D0,ARG+4
        MOVE.B  FACOV,D0
        MOVE.B  ARGEXT,FACOV
        MOVE.B  D0,ARGEXT
        MOVE.B  FACSIGN,D0
        MOVE.B  ARISGN,FACSIGN
        MOVE.B  D0,ARISGN
        MOVE.B  OLDOV,FACOV     ; the saved extension rules the
        CLR.B   ARGEXT          ; fraction subtraction: in the
                                ; original the extension is ONE
                                ; shared byte on the FAC side and
                                ; ARG's field is [mantissa][0] --
                                ; loading ARGEXT with OLDOV too
                                ; made the subtraction cancel it
                                ; (EXP(50) lost f's low byte)
        BSR     FSUB_CORE       ; FAC := y - INT(y)
        BSR     NEGOP_F         ; FAC := -frac
        LEA     EXPCON(PC),A0
        BSR     POLY            ; FAC := 2^(1-frac) approximation
        CLR.B   ARISGN          ; MLDEXP: result sign positive
        MOVE.W  (SP)+,D0        ; the scale byte
        BRA     MLDEXP
MLDVEX  TST.B   FACSIGN
        BMI     ZERO_FAC        ; negative: underflow to zero
        BRA     OVERR           ; positive: ?OV ERROR

;---------------------------------------------------------------------
; FPWR -- the ^ performer: ARG = base x, FAC = exponent y.
; (FPWRT.)  y = 0: the result is EXP(0) = 1, by falling into
; EXP with FAC = 0.  x = 0 (y <> 0): the result is 0, even
; for negative y -- the original checks in this order.
; Otherwise x^y = EXP(y * LOG(x)); a negative x is made
; positive for the LOG only when y is an integer, and the
; result is negated when that integer is odd (the parity of
; INTEGR's low byte; INTFN's magnitude form has the same
; low-bit parity as the original's two's complement).
; SQR -- x^0.5 through FPWR (MOVAF, then FAC := 1/2).
;---------------------------------------------------------------------
FPWR    TST.B   FAC
        BEQ     EXP_FN          ; y = 0 -> 1 (tail)
        TST.B   ARG
        BNE     FPW_1
        BRA     ZERO_FAC        ; x = 0 -> 0 (tail)
FPW_1   MOVEA.L #TEMPF3,A0
        BSR     ST_FAC          ; TEMPF3 := y (MOVMF: rounded)
        CLR.B   FACOV
        CLR.B   FPWNEG
        MOVE.B  ARISGN,D7       ; MOVFA1's sign byte: x's sign
        TST.B   ARISGN
        BPL     FPW_2           ; x > 0: nothing to check
        BSR     INTFN           ; FAC := INT(y)
        MOVEA.L #TEMPF3,A0
        BSR     FCOMP           ; INT(y) against y
        MOVE.B  D0,D7           ; 0 = integer (x becomes positive
                                ; via MOVFA1), $FF = not (x stays
                                ; negative; LOG will error)
        TST.B   D0
        BNE     FPW_2
        MOVE.B  INTEGR,D0       ; INTEGR parity
        ANDI.B  #1,D0
        MOVE.B  D0,FPWNEG
FPW_2   BSR     CP_A2F          ; FAC := x (MOVFA)
        MOVE.B  D7,FACSIGN      ; MOVFA1: the sign byte rules
        BSR     LOG_FN          ; FAC := LOG(x)
        MOVEA.L #TEMPF3,A0
        BSR     FMULT_MEM       ; FAC := y * LOG(x)
        BSR     EXP_FN          ; FAC := x^y
        TST.B   FPWNEG
        BEQ     FPW_R
        BRA     NEGOP_F         ; odd integer exponent: negate
FPW_R   RTS
SQR_FN  BSR     CP_F2AR         ; MOVAF: ARG := x (rounded)
        LEA     CON_HALF(PC),A0
        BSR     LD_FAC          ; FAC := 0.5
        BRA     FPWR

;---------------------------------------------------------------------
; SIN / COS / TAN / ATN -- the original's range reduction:
; divide by 2*PI, keep the fraction, fold into the first
; quadrant with 1/4-turn arithmetic, and evaluate the odd
; polynomial.  TANSGN (the ZP byte at $13) records the
; quadrant-II/III flip for TAN, exactly as in the original.
; SIN1_PT is a genuine mid-routine entry: TAN's cosine pass
; (COSC) pushes TANSGN as a stand-in for SIN's saved sign and
; enters there, with FAC = |TEMPF1| -- which by then holds
; SIN's polynomial input, because POLYX stored it there.
; That sharing is the original's design, not an accident.
;---------------------------------------------------------------------
COS_FN  LEA     PI2(PC),A0
        BSR     FADD_MEM        ; FAC += PI/2
        ; fall into SIN_FN
SIN_FN  BSR     CP_F2AR         ; MOVAF: ARG := x
        LEA     TWOPI(PC),A0
        BSR     LD_FAC          ; FAC := 2*PI (FDIVF's load)
        MOVE.B  ARISGN,D0       ; SGNCPR := sign(x) xor sign(2PI)
        MOVE.B  FACSIGN,D1
        EOR.B   D1,D0
        MOVE.B  D0,SGNCPR
        BSR     FDIV_CORE       ; FAC := x / (2*PI)
        BSR     CP_F2AR         ; MOVAF: ARG := quotient
        BSR     INTFN           ; FAC := INT(quotient)
        BSR     FSUB_CORE       ; FAC := fraction (ARG - FAC)
        LEA     FR4(PC),A0
        BSR     FSUB_MEM        ; FAC := 1/4 - fraction
        MOVE.B  FACSIGN,D0
        MOVE.W  D0,-(SP)        ; PHA: save the sign
        TST.B   FACSIGN         ; (the MOVE.W above clobbers N
        BPL     SIN1_PT         ; with D0's bit 15 -- the 6502's
                                ; PHA leaves the flags alone, so
                                ; the sign must be re-tested here)
                                ; first quadrant
        BSR     FADDH           ; FAC += 1/2
        TST.B   FACSIGN
        BMI     SIN2_PT         ; still negative: quadrant IV
        EORI.B  #$FF,TANSGN     ; quadrants II/III: flip TANSGN
SIN1_PT BSR     NEGOP_F         ; negate (FAC is >= 0 here)
SIN2_PT LEA     FR4(PC),A0
        BSR     FADD_MEM        ; FAC += 1/4
        MOVE.W  (SP)+,D0        ; PLA: the saved sign
        TST.B   D0
        BPL     SIN3_PT
        BSR     NEGOP_F         ; negative quadrant: negate
SIN3_PT LEA     SINCON(PC),A0
        BRA     POLYX
TAN_FN  BSR     MOV1F           ; TEMPF1 := x
        CLR.B   TANSGN
        BSR     SIN_FN          ; FAC := SIN(x); TEMPF1 := the
                                ; polynomial input (POLYX did it)
        MOVEA.L #TEMPF3,A0
        BSR     ST_FAC          ; TEMPF3 := SIN(x)
        CLR.B   FACOV
        MOVEA.L #TEMPF1,A0
        BSR     LD_FAC          ; FAC := the reduced argument
        CLR.B   FACSIGN         ; start off positive
        MOVEQ   #0,D0
        MOVE.B  TANSGN,D0
        BSR     COSC_PT         ; FAC := COS(x) (mid-SIN entry)
        MOVEA.L #TEMPF3,A0
        BRA     FDIV_MEM        ; FAC := SIN / COS
; COSC -- the original's two-instruction bridge: PHA the
; TANSGN byte, then JMP (not JSR) into SIN1, so the saved
; byte rides ON TOP of this call's return address and
; SIN2_PT's pop finds the byte, not the return address.
; (A plain BSR into SIN1_PT inverts that order and the pop
; eats the return address -- the ?NF ERROR that gave it away.)
COSC_PT MOVE.W  D0,-(SP)        ; PHA
        BRA     SIN1_PT         ; JMP SIN1
ATN_FN  MOVEQ   #0,D7
        MOVE.B  FACSIGN,D7
        MOVE.W  D7,-(SP)        ; PHA: save the sign
        TST.B   FACSIGN         ; (re-test: MOVE.W clobbers N)
        BPL     ATN_1
        BSR     NEGOP_F         ; FAC := |x|
ATN_1   MOVEQ   #0,D7
        MOVE.B  FAC,D7
        MOVE.W  D7,-(SP)        ; PHA: save the exponent
        CMPI.B  #$81,FAC
        BCS     ATN_2           ; |x| < 1: no reciprocal
        LEA     FONE(PC),A0
        BSR     FDIV_MEM        ; FAC := 1 / x
ATN_2   LEA     ATNCON(PC),A0
        BSR     POLYX           ; FAC := ATN(reduced)
        MOVE.W  (SP)+,D7        ; the saved exponent
        CMPI.B  #$81,D7
        BCS     ATN_3           ; was < 1: no correction
        LEA     PI2(PC),A0
        BSR     FSUB_MEM        ; FAC := PI/2 - FAC
ATN_3   MOVE.W  (SP)+,D7        ; the saved sign
        TST.B   D7
        BPL     ATN_R
        BRA     NEGOP_F         ; negative argument: negate
ATN_R   RTS

;---------------------------------------------------------------------
; RND -- the original's generator (REALIO=3 form).
; Argument > 0: the next value of the sequence,
;   RNDX := byte-reversed-normalized(RNDX * RMULZC + RADDZC).
; Argument < 0: RNDX := the same transform of the argument
; (a deterministic reseed).
; Argument = 0: the original reads its timer/entropy cells
; and normalizes them into RNDX.  This port has no free
; running timer; the corresponding cells read as zero here
; and in the golden harness alike, so the path collapses to
; FAC := 0 and RNDX := 0 -- which is what the code below
; does, in the original's shape (STRNEX on zero bytes).
; The transform: clear the sign, move the exponent into the
; extension byte, set the exponent to $80 (result in [0,1)),
; reverse the four mantissa bytes, normalize, store to RNDX.
; (For REALIO=3 BOTH byte pairs are reversed.)
;---------------------------------------------------------------------
RND_FN  BSR     SIGN_FAC
        BMI     RND_1           ; negative: seed from FAC
        BNE     RND_NX          ; positive: next in sequence
        BSR     ZERO_FAC        ; zero: the "timer" path (above)
        MOVEA.L #RNDX,A0
        BRA     ST_FAC          ; RNDX := 0 (tail)
RND_NX  MOVEA.L #RNDX,A0
        BSR     LD_FAC          ; FAC := RNDX
        LEA     RMULZC(PC),A0
        BSR     FMULT_MEM       ; FAC *= RMULZC
        LEA     RADDZC(PC),A0
        BSR     FADD_MEM        ; FAC += RADDZC
RND_1   MOVE.B  FAC+1,D0        ; reverse the mantissa bytes
        MOVE.B  FAC+4,FAC+1
        MOVE.B  D0,FAC+4
        MOVE.B  FAC+2,D0
        MOVE.B  FAC+3,FAC+2
        MOVE.B  D0,FAC+3
        CLR.B   FACSIGN         ; make it positive
        MOVE.B  FAC,FACOV       ; exponent -> extension byte
        MOVE.B  #$80,FAC        ; result in [0,1)
        BSR     NORMALIZE
        MOVEA.L #RNDX,A0
        BRA     ST_FAC          ; RNDX := FAC (rounded; tail)

;---------------------------------------------------------------------
; POS -- the print head column (POSX, this port's TRMPOS).
; The argument is evaluated by the caller and ignored, as in
; the original.
; PEEK -- GETADR the argument, float the byte.
; GETADR -- the original's address conversion: a negative
; value or an exponent >= 145 is ?IQ ERROR; the integer's
; low 16 bits are the LOGICAL address.  Logical addresses
; name this port's virtual 64KB page: physical = ZPBASE +
; logical, so logical 0 is the virtual zero page (PEEK of
; the interpreter's own pointers works in logical terms),
; and the page's free RAM serves POKE/PEEK round trips.
; The ACIA is NOT reachable through this mapping in Phase 1.
;---------------------------------------------------------------------
POSFN   MOVEQ   #0,D0
        MOVE.B  POSX,D0
        BRA     GIVAYF
PEEKFN  BSR     GETADR
        MOVEQ   #0,D0
        MOVE.B  (A0),D0
        BRA     GIVAYF
GETADR  TST.B   FACSIGN
        BMI     IQERR           ; negative address: FCERR
        CMPI.B  #$91,FAC        ; exponent 145: value >= 131072
        BCC     IQERR
        BSR     QINT            ; integer into FAC+1..FAC+4
        MOVEQ   #0,D0
        MOVE.B  FAC+3,D0        ; low 16 bits, as the original
        LSL.W   #8,D0           ; takes FACMO/FACLO
        MOVE.B  FAC+4,D0
        MOVEA.L #ZPBASE,A0
        ADDA.L  D0,A0           ; logical -> physical
        RTS

;---------------------------------------------------------------------
; POKE address,byte -- GETNUM's shape: FRMNUM, GETADR, comma,
; GETBYT (CONINT, via GETBYTE).
; WAIT address,mask1[,mask2] -- poll until
; ((byte XOR mask2) AND mask1) <> 0; mask2 defaults to 0.
; The poll does not check CTRL-C, as in the original.
;---------------------------------------------------------------------
POKEH   BSR     FRMNUM          ; address -> FAC
        BSR     GETADR          ; A0 = physical address
        MOVE.L  A0,-(SP)        ; (FRMNUM below clobbers A0)
        MOVE.B  #$2C,D0         ; ','
        BSR     SYNCHR
        BSR     FRMNUM          ; value -> FAC
        BSR     GETBYTE         ; D2.B = the byte (CONINT)
        MOVEA.L (SP)+,A0
        MOVE.B  D2,(A0)
        RTS
WAITH   BSR     FRMNUM
        BSR     GETADR
        MOVE.L  A0,POKER
        MOVE.B  #$2C,D0
        BSR     SYNCHR
        BSR     FRMNUM
        BSR     GETBYTE         ; D2.B = mask1; D0 = current char
        MOVE.B  D2,ANDMSK
        CLR.B   EORMSK          ; mask2 defaults to 0
        CMPI.B  #$2C,D0         ; ',' -> a mask2 follows
        BNE     WAIT_P
        MOVE.B  #$2C,D0
        BSR     SYNCHR
        BSR     FRMNUM
        BSR     GETBYTE
        MOVE.B  D2,EORMSK
WAIT_P  MOVEA.L POKER,A0
        MOVE.B  (A0),D0
        MOVE.B  EORMSK,D1       ; (EOR takes a register source
        EOR.B   D1,D0           ; only -- a memory source is
                                ; silently mis-assembled)
        AND.B   ANDMSK,D0
        BEQ     WAIT_P
        RTS

;---------------------------------------------------------------------
; LEN / ASC / VAL / STR$ -- the remaining string functions.
; LEN1's shared setup (FRESTR) is CHKSTR + FREFAC here:
; D2.W = length, A1 = data pointer, the temp (if any) freed.
;---------------------------------------------------------------------
LENFN   BSR     CHKSTR
        BSR     FREFAC
        MOVEQ   #0,D0
        MOVE.W  D2,D0
        BRA     GIVAYF          ; FAC := length (unsigned)
ASCFN   BSR     CHKSTR
        BSR     FREFAC
        TST.W   D2
        BEQ     IQERR           ; ASC("") is FCERR in the original
        MOVEQ   #0,D0
        MOVE.B  (A1),D0         ; the first character
        BRA     GIVAYF
VALFN   BSR     CHKSTR
        BSR     FREFAC          ; D2.W = length, A1 = data
        CLR.B   VALTYP          ; the result is numeric
        TST.W   D2
        BNE     VAL_1
        BRA     ZERO_FAC        ; VAL("") = 0 (tail)
VAL_1   MOVE.L  A6,-(SP)        ; save TXTPTR
        MOVEA.L A1,A0           ; plant a terminator at data+len:
        MOVEQ   #0,D0           ; the original overwrites the byte
        MOVE.W  D2,D0           ; past the string, parses, and
        ADDA.L  D0,A0           ; puts it back -- FIN would
        MOVE.L  A0,-(SP)        ; otherwise read whatever follows
        MOVEQ   #0,D0
        MOVE.B  (A0),D0
        MOVE.L  D0,-(SP)
        CLR.B   (A0)
        MOVEA.L A1,A6
        SUBQ.L  #1,A6
        BSR     CHRGET          ; D0 = first character
        BSR     INPFIN          ; parse (INPFIN: FIN + the
                                ; original's leading-sign handling)
        MOVE.L  (SP)+,D0        ; restore the planted byte
        MOVEA.L (SP)+,A0
        MOVE.B  D0,(A0)
        MOVEA.L (SP)+,A6        ; restore TXTPTR
        RTS
STRFN   BSR     CHKNUM
        BSR     FOUT            ; FBUFF := sign char + digits + NUL
        LEA     FBUFF,A0        ; the string is the whole buffer,
        MOVEQ   #0,D2           ; sign included, exactly as the
STRF_L  TST.B   (A0)+           ; original's FOUTC layout gives
        BEQ     STRF_D          ; TIMSTR a string from LOFBUF
        ADDQ.W  #1,D2
        BRA     STRF_L
STRF_D  MOVE.B  D2,DSCBUF+4     ; stage {length, FBUFF}
        MOVE.L  #FBUFF,DSCBUF
        MOVE.L  #DSCBUF,FAC+4
        MOVE.B  #$FF,VALTYP
        MOVE.W  D2,D0           ; copy it into string space
        MOVE.W  D2,-(SP)        ; (FBUFF is below TXTTAB, like
        BSR     STRINI          ; the original's page-0 rule)
        MOVE.W  (SP)+,D2
        LEA     FBUFF,A0
        MOVEA.L FRESPC,A1
        BSR     MOVSTR
        BRA     PUTNEW

;---------------------------------------------------------------------
; LEFT$ / RIGHT$ / MID$ -- the (string, byte[, byte]) functions.
; They parse their own argument list (the FE_UF single-argument
; machinery cannot): string first (its descriptor address is
; parked on the stack, as the original's FINGO2 parks it),
; then the byte argument(s) via FRMNUM + GETBYTE (CONINT).
; The result is always a fresh copy in string space (STRSPA
; in the original): SUBSTR allocates first and frees the
; source temp second, in the original's order.
; Entry to SUBSTR: STRNG1 = source descriptor address,
; D6.W = offset, D7.W = count (already clamped).
;---------------------------------------------------------------------
FE_LEFT BSR     CHRGET          ; step past the token
        BSR     CHKOPN
        BSR     FRMEVL          ; the string argument
        BSR     CHKSTR
        MOVE.L  FAC+4,-(SP)     ; park the descriptor address
        MOVE.B  #$2C,D0
        BSR     SYNCHR          ; ','
        BSR     FRMNUM
        BSR     GETBYTE         ; D2.B = count
        MOVEQ   #0,D7
        MOVE.B  D2,D7
        MOVE.W  D7,-(SP)        ; park it (CHKCLS clobbers D2)
        BSR     CHKCLS
        MOVE.W  (SP)+,D7
        MOVE.L  (SP)+,STRNG1
        BSR     SUBSTR_PREP     ; D7 := min(count, length)
        MOVEQ   #0,D6           ; offset 0
        BRA     SUBSTR
FE_RIGHT BSR    CHRGET
        BSR     CHKOPN
        BSR     FRMEVL
        BSR     CHKSTR
        MOVE.L  FAC+4,-(SP)
        MOVE.B  #$2C,D0
        BSR     SYNCHR
        BSR     FRMNUM
        BSR     GETBYTE
        MOVEQ   #0,D7
        MOVE.B  D2,D7
        MOVE.W  D7,-(SP)
        BSR     CHKCLS
        MOVE.W  (SP)+,D7
        MOVE.L  (SP)+,STRNG1
        BSR     SUBSTR_PREP     ; D7 := min(count, length),
                                ; D3.W := length
        MOVE.W  D3,D6
        SUB.W   D7,D6           ; offset := length - count
        BRA     SUBSTR
FE_MID  BSR     CHRGET
        BSR     CHKOPN
        BSR     FRMEVL
        BSR     CHKSTR
        MOVE.L  FAC+4,-(SP)     ; park the descriptor address
        MOVE.B  #$2C,D0
        BSR     SYNCHR          ; ','
        BSR     FRMNUM
        BSR     GETBYTE         ; D2.B = start position (1-based)
        MOVEQ   #0,D3
        MOVE.B  D2,D3
        MOVE.W  D3,-(SP)        ; park the start
        MOVE.B  #255,D5         ; default length: 255
        CMPI.B  #$2C,D0         ; ',' -> a length follows (D0 is
        BNE     MID_1           ; GETBYTE's CHRGOT character)
        MOVE.B  #$2C,D0
        BSR     SYNCHR
        BSR     FRMNUM
        BSR     GETBYTE         ; D2.B = the length
        MOVE.B  D2,D5
MID_1   MOVE.W  D5,-(SP)        ; park the length (CHKCLS
        BSR     CHKCLS          ; clobbers D2, not D5 -- but keep
        MOVE.W  (SP)+,D5        ; the stack discipline uniform)
        MOVE.W  (SP)+,D3        ; D3.W = start
        MOVE.L  (SP)+,STRNG1
        TST.W   D3
        BEQ     IQERR           ; position 0 is FCERR
        SUBQ.W  #1,D3           ; offset := start - 1
        MOVE.W  D3,D6
        MOVEA.L STRNG1,A0
        MOVEQ   #0,D4
        MOVE.B  4(A0),D4        ; D4.W = source length (M5e:
                                ; descriptor length lives at +4)
        CMP.W   D4,D6
        BCC     MID_NULL        ; offset >= length: null string
        MOVE.W  D4,D7
        SUB.W   D6,D7           ; available := length - offset
        MOVEQ   #0,D0
        MOVE.B  D5,D0           ; wanted := the length argument
        CMP.W   D0,D7
        BLS     SUBSTR          ; count := min(available, wanted)
        MOVE.W  D0,D7
        BRA     SUBSTR
MID_NULL MOVEQ  #0,D7           ; count 0 (offset moot)
        BRA     SUBSTR
; SUBSTR_PREP -- clamp D7.W to the source length.
; In: STRNG1 = descriptor address, D7.W = wanted count.
; Out: D7.W = min(wanted, length), D3.W = length.
SUBSTR_PREP MOVEA.L STRNG1,A0
        MOVEQ   #0,D3
        MOVE.B  4(A0),D3        ; source length (M5e: at +4)
        CMP.W   D3,D7
        BLS     SPP_R
        MOVE.W  D3,D7
SPP_R   RTS
; SUBSTR -- build the result string: STRINI allocates the
; result (DSCPNT remembers the source descriptor), FRETMP
; frees the source temp and yields its data, MOVSTR copies
; the slice, PUTNEW pushes the result descriptor.
SUBSTR  MOVE.W  D7,-(SP)        ; park offset/count across
        MOVE.W  D6,-(SP)        ; STRINI (GETSPA/GARBAG inside)
        MOVE.L  STRNG1,FAC+4    ; STRINI's DSCPNT := the source
        MOVE.W  D7,D0
        BSR     STRINI          ; DSCBUF := {count, string space}
        MOVE.W  (SP)+,D6
        MOVE.W  (SP)+,D7
        MOVEA.L DSCPNT,A0
        BSR     FRETMP          ; source: D2.W len, A1 = data
        MOVEA.L A1,A0
        ADDA.W  D6,A0           ; + offset
        MOVEA.L FRESPC,A1       ; the result block
        MOVE.W  D7,D2           ; count
        BSR     MOVSTR
        BRA     PUTNEW

;---------------------------------------------------------------------
; M5d constants.  Packed 5-byte FP values (exponent, then the
; four mantissa bytes with the sign in the first byte's top
; bit), converted from the original's RADIX 8 listing.
;---------------------------------------------------------------------
FONE    DC.B    $81,$00,$00,$00,$00     ; 1.0
SQRHLF  DC.B    $80,$35,$04,$F3,$34     ; SQR(0.5)
SQRTWO  DC.B    $81,$35,$04,$F3,$34     ; SQR(2)
NEGHLF  DC.B    $80,$80,$00,$00,$00     ; -1/2
LOG2C   DC.B    $80,$31,$72,$17,$F8     ; LN(2)
LOGEB2  DC.B    $81,$38,$AA,$3B,$29     ; LOG2(e)
PI2     DC.B    $81,$49,$0F,$DA,$A2     ; PI/2
TWOPI   DC.B    $83,$49,$0F,$DA,$A2     ; 2*PI
FR4     DC.B    $7F,$00,$00,$00,$00     ; 1/4
; RND's constants are four bytes in the original, laid out
; back to back: a 5-byte unpack reads the FIRST byte of the
; following item as the last mantissa byte.  Both are stored
; here in their effective 5-byte form (RMULZC's 5th byte is
; RADDZC's first; RADDZC's 5th is the $20 that follows it in
; the ROM -- the JSR opcode of RND's first instruction).
RMULZC  DC.B    $98,$35,$44,$7A,$68     ; RND multiplier
RADDZC  DC.B    $68,$28,$B1,$46,$20     ; RND increment
LOGCN2  DC.B    3                       ; LOG polynomial (degree-1)
        DC.B    $7F,$5E,$56,$CB,$79     ; .43425594188
        DC.B    $80,$13,$9B,$0B,$64     ; .57658454134
        DC.B    $80,$76,$38,$93,$16     ; .96180075921
        DC.B    $82,$38,$AA,$3B,$20     ; 2.8853900728
EXPCON  DC.B    7                       ; EXP polynomial (degree-1)
        DC.B    $71,$34,$58,$3E,$56     ; .000021498763697
        DC.B    $74,$16,$7E,$B3,$1B     ; .00014352314036
        DC.B    $77,$2F,$EE,$E3,$85     ; .0013422634824
        DC.B    $7A,$1D,$84,$1C,$2A     ; .0096140170119
        DC.B    $7C,$63,$59,$58,$0A     ; .055505126860
        DC.B    $7E,$75,$FD,$E7,$C6     ; .24022638462
        DC.B    $80,$31,$72,$18,$10     ; .69314718608
        DC.B    $81,$00,$00,$00,$00     ; 1.0
SINCON  DC.B    5                       ; SIN polynomial (degree-1);
                                        ; the original lists two
                                        ; further constants after
                                        ; these that POLYX never
                                        ; reads (degree is 5)
        DC.B    $84,$E6,$1A,$2D,$1B     ; -14.381383816
        DC.B    $86,$28,$07,$FB,$F8     ; 42.07777095
        DC.B    $87,$99,$68,$89,$01     ; -76.704133676
        DC.B    $87,$23,$35,$DF,$E1     ; 81.605223690 (the source's
                                        ; "065" is RADIX 8 = $35 --
                                        ; cross-checked against the
                                        ; cbmbasic2 ROM at $E063, as
                                        ; were all M5d tables)
        DC.B    $86,$A5,$5D,$E7,$28     ; -41.34170209
        DC.B    $83,$49,$0F,$DA,$A2     ; 6.2831853070
ATNCON  DC.B    11                      ; ATN polynomial (degree-1;
                                        ; the source's "13" is
                                        ; RADIX 8 for 11)
        DC.B    $76,$B3,$83,$BD,$D3     ; -.0006847939119
        DC.B    $79,$1E,$F4,$A6,$F5     ; .004850942156
        DC.B    $7B,$83,$FC,$B0,$10     ; -.01611170184
        DC.B    $7C,$0C,$1F,$67,$CA     ; .03420963805
        DC.B    $7C,$DE,$53,$CB,$C1     ; -.05427913276
        DC.B    $7D,$14,$64,$70,$4C     ; .07245719654
        DC.B    $7D,$B7,$EA,$51,$7A     ; -.08980239538
        DC.B    $7D,$63,$30,$88,$7E     ; .1109324134
        DC.B    $7E,$92,$44,$99,$3A     ; -.1428398077
        DC.B    $7E,$4C,$CC,$91,$C7     ; .1999991205
        DC.B    $7F,$AA,$AA,$AA,$13     ; -.3333333157
        DC.B    $81,$00,$00,$00,$00     ; 1.0

;---------------------------------------------------------------------
; Evaluator tables (MATHTBL) and FP constants.  Precedences and
; the constant byte patterns are the original's.
;---------------------------------------------------------------------
MATPREC DC.B    $79,$79,$7B,$7B,$7F,$50,$46,$7D,$5A,$64
        DC.B    0               ; M5e: alignment pad -- MATPERF and
                                ; DECTBL (both DC.L tables, read with
                                ; longword accesses) must start at an
                                ; even address; without this byte
                                ; they sat at $3935/$395D (odd)
MATPERF DC.L    FADD_CORE,FSUB_CORE,FMULT_CORE,FDIV_CORE
        DC.L    FPWR,TAND,ORPERF,NEGOP
        DC.L    EQUOP,RELOPS
DECTBL  DC.L    $FA0A1F00,$00989680,$FFF0BDC0,$000186A0
        DC.L    $FFFFD8F0,$000003E8,$FFFFFF9C,$0000000A
        DC.L    $FFFFFFFF
CON_ONE DC.B    $81,$00,$00,$00,$00
CON_HALF DC.B   $80,$00,$00,$00,$00
CONTEN  DC.B    $84,$20,$00,$00,$00
CON_BILLION DC.B $9E,$6E,$6B,$28,$00
CON_999999999 DC.B $9E,$6E,$6B,$27,$FE
CON_99999999_9 DC.B $9B,$3E,$BC,$1F,$FD
NEG32768 DC.B   $90,$80,$00,$00,$00
        DC.B    0               ; M5e: alignment pad -- C_ZERO is
                                ; word-read as an integer variable's
                                ; value, so it must stay even (the
                                ; MATPERF pad above shifted it odd)
C_ZERO  DC.B    0,0,0,0,0

;---------------------------------------------------------------------
; Constant strings (kept at the end so code stays contiguous).
;---------------------------------------------------------------------
