FE_UNARY CMPI.B #$B4,D0         ; SGN
        BNE   FE_U1
        LEA     SGNFN_I(PC),A2  ; R2-M4 (D6): typed wrapper
        BRA   FE_UFN_T
FE_U1   CMPI.B  #$B5,D0         ; INT
        BNE   FE_U2
        LEA     INTFN_I(PC),A2  ; R2-M4 (D6): typed wrapper
        BRA   FE_UFN_T
FE_U2   CMPI.B  #$B6,D0         ; ABS
        BNE     FE_U25
        LEA     FABSFN_I(PC),A2 ; R2-M4 (D6): typed wrapper
        BRA   FE_UFN_T
FE_U25  CMPI.B  #$B8,D0         ; FRE (M5a)
        BNE     FE_U26
        LEA     FREFN(PC),A2
        BRA     FE_UF
FE_U26  CMPI.B  #$B9,D0         ; POS (M5d)
        BNE     FE_U27
        LEA     POSFN(PC),A2
        BRA     FE_UF
FE_U27  CMPI.B  #$BA,D0         ; SQR (M5d)
        BNE     FE_U28
        LEA     SQR_FN(PC),A2
        BRA     FE_UFN
FE_U28  CMPI.B  #$BB,D0         ; RND (M5d)
        BNE     FE_U29
        LEA     RND_FN(PC),A2
        BRA     FE_UFN
FE_U29  CMPI.B  #$BC,D0         ; LOG (M5d)
        BNE     FE_U30
        LEA     LOG_FN(PC),A2
        BRA     FE_UFN
FE_U30  CMPI.B  #$BD,D0         ; EXP (M5d)
        BNE     FE_U31
        LEA     EXP_FN(PC),A2
        BRA     FE_UFN
FE_U31  CMPI.B  #$BE,D0         ; COS (M5d)
        BNE     FE_U32
        LEA     COS_FN(PC),A2
        BRA     FE_UFN
FE_U32  CMPI.B  #$BF,D0         ; SIN (M5d)
        BNE     FE_U33
        LEA     SIN_FN(PC),A2
        BRA     FE_UFN
FE_U33  CMPI.B  #$C0,D0         ; TAN (M5d)
        BNE     FE_U34
        LEA     TAN_FN(PC),A2
        BRA     FE_UFN
FE_U34  CMPI.B  #$C1,D0         ; ATN (M5d)
        BNE     FE_U35
        LEA     ATN_FN(PC),A2
        BRA     FE_UFN
FE_U35  CMPI.B  #$C2,D0         ; PEEK (M5d)
        BNE     FE_U36
        LEA     PEEKFN(PC),A2
        BRA     FE_UF_T         ; R2-M4 (D6): PEEK returns INT
FE_U36  CMPI.B  #$C3,D0         ; LEN (M5d)
        BNE     FE_U37
        LEA     LENFN(PC),A2
        BRA     FE_UF
FE_U37  CMPI.B  #$C4,D0         ; STR$ (M5d)
        BNE     FE_U38
        LEA     STRFN(PC),A2
        BRA     FE_UF
FE_U38  CMPI.B  #$C5,D0         ; VAL (M5d)
        BNE     FE_U39
        LEA     VALFN(PC),A2
        BRA     FE_UF_T         ; R2-M4 (D10): VAL keeps FIN's
                                ; D1 type (see VALFN)
FE_U39  CMPI.B  #$C6,D0         ; ASC (M5d)
        BNE     FE_U40
        LEA     ASCFN(PC),A2
        BRA     FE_UF
FE_U40  CMPI.B  #$C8,D0         ; LEFT$ (M5d): two-argument
        BEQ     FE_LEFT         ; functions parse their own
        CMPI.B  #$C9,D0         ; RIGHT$ (M5d)
        BEQ     FE_RIGHT
        CMPI.B  #$CA,D0         ; MID$ (M5d)
        BEQ     FE_MID
        BRA     FE_U3
FE_UF   BSR     CHRGET          ; step past the function token
        MOVE.L  A2,-(SP)        ; the function pointer rides out
        BSR     CHKOPN          ; the argument evaluation on the
        BSR     FRMEVL          ; stack: the evaluator and the FP
        BSR     CHKCLS          ; core clobber A0-A2
        MOVEA.L (SP)+,A2
        JSR     (A2)
        CLR.B   FACTYP          ; R2-M1: a function result is FP
        RTS                     ; (typed results -- VAL among
                                ; them -- go through FE_UF_T,
                                ; R2-M4 below)
; FE_UFN -- the numeric functions' variant: the argument must
; be numeric.  The original dispatches these through
; FRM_PERFORM2, which runs CHKNUM after the handler returns;
; checking here, before the handler, is observationally the
; same for every handler that returns normally (and turns
; the handlers' garbage-input paths into the same ?TM ERROR
; the original reports -- SQR is the one exception, see the
; M5d memo).
FE_UFN  BSR     CHRGET
        MOVE.L  A2,-(SP)
        BSR     CHKOPN
        BSR     FRMEVL
        BSR     CHKCLS
        BSR     CHKNUM
        MOVEA.L (SP)+,A2
        JSR     (A2)
        CLR.B   FACTYP          ; R2-M1: a function result is FP
        RTS
;---------------------------------------------------------------------
; FE_UF_T / FE_UFN_T -- R2-M4 typed variants (D6/D8/D10): exactly
; FE_UF / FE_UFN but WITHOUT the blanket FACTYP clear after the
; handler.  The handler owns its result type and must set it
; deterministically on every path: the SGN/INT/ABS wrappers
; below, PEEKFN, VALFN, DEEKFN/LEEKFN and USRFN.  Every other
; function keeps the M1 choke point above -- its result is FP
; even for an INT argument (SQR/SIN/.../RND, FRE, POS, LEN,
; ASC, INSTR: the R2-M4 audit table is in the results record).
;---------------------------------------------------------------------
FE_UF_T BSR     CHRGET          ; step past the function token
        MOVE.L  A2,-(SP)
        BSR     CHKOPN
        BSR     FRMEVL
        BSR     CHKCLS
        MOVEA.L (SP)+,A2
        JSR     (A2)
        RTS                     ; no clear: the handler set the type
FE_UFN_T BSR    CHRGET
        MOVE.L  A2,-(SP)
        BSR     CHKOPN
        BSR     FRMEVL
        BSR     CHKCLS
        BSR     CHKNUM
        MOVEA.L (SP)+,A2
        JSR     (A2)
        RTS                     ; no clear: the handler set the type
;---------------------------------------------------------------------
; R2-M4 typed wrappers (D6) -- the SGN / INT / ABS handlers for
; FE_UFN_T.  An INT argument is answered in INT; an FP argument
; takes the legacy handler unchanged (its result is FP, and
; FACTYP is already 0).  The wrappers live here, next to the
; dispatch, because the FP cores are also called directly by
; internal FP code (INTFN by the math pack) where the argument
; type is meaningless -- the same reasoning as M2's wrappers.
;---------------------------------------------------------------------
SGNFN_I TST.B   FACTYP
        BEQ     SGNFN           ; FP argument: legacy path (tail)
        BSR     SIGN_FAC        ; D0.L = -1/0/1 (SIGN_FAC's MOVEQs
                                ; sign-extend; the FP shadow of an
                                ; INT carries the exact sign)
        BRA     SFLOAT32        ; INT result (0 degrades to FP 0,
                                ; as everywhere in the dual rep)
INTFN_I TST.B   FACTYP
        BNE     INTFN_R         ; INT argument: INT is the identity
        BRA     INTFN           ; FP argument: legacy floor (tail)
INTFN_R RTS                     ; (FAC/FACINT already agree)
FABSFN_I TST.B  FACTYP
        BEQ     FABSFN          ; FP argument: legacy path (tail)
        CMPI.L  #$80000000,FACINT
        BEQ     FABS_MIN        ; -2147483648: see below
        BSR     FABSFN          ; clear the FP shadow's sign bit
        TST.L   FACINT
        BPL     FABS_R
        NEG.L   FACINT          ; keep FACINT in sync with the shadow
FABS_R  RTS
FABS_MIN BSR    FABSFN          ; the shadow is now exactly
        CLR.B   FACTYP          ; +2147483648.0, which no int32 can
        RTS                     ; hold: promote to FP (D3's spirit)
