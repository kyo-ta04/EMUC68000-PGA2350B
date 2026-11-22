FE_UNARY CMPI.B #$B4,D0         ; SGN
        BNE   FE_U1
        LEA     SGNFN(PC),A2
        BRA   FE_UFN
FE_U1   CMPI.B  #$B5,D0         ; INT
        BNE   FE_U2
        LEA     INTFN(PC),A2
        BRA   FE_UFN
FE_U2   CMPI.B  #$B6,D0         ; ABS
        BNE     FE_U25
        LEA     FABSFN(PC),A2
        BRA     FE_UFN
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
        BRA     FE_UF
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
        BRA     FE_UF
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
        RTS
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
        RTS
