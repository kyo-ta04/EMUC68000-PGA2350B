; Interpreter core, part B.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; M3 FP core and everything after (M4/M5 sections).
;=====================================================================
; M3: floating point core, evaluator, variables, FOR/NEXT.
;
; FAC/ARG keep the original's memory-resident layout:
;   FAC+0 exponent (0 = zero), FAC+1..FAC+4 mantissa (top bit is
;   the hidden 1), FAC+5 (FACOV) extension byte, FAC+6 (FACSIGN).
;   Packed form (variables, constants): exponent, then byte1 =
;   sign(bit7) | mantissa top 7 bits, then mantissa bytes 2..4.
; The routines below transliterate the original math pack
; (m6502.asm 4899-6101 / mist64 float.s) algorithm for algorithm;
; deviations are listed in m3-results.md.
;=====================================================================

;---------------------------------------------------------------------
; LD_FAC / LD_ARG -- unpack the packed value at (A0) into FAC/ARG.
; (LOAD_FAC_FROM_YA / LOAD_ARG_FROM_YA.)  LD_ARG also sets
; SGNCPR := ARISGN eor FACSIGN.  Clobbers D0.
;---------------------------------------------------------------------
LD_FAC  MOVE.B  (A0),FAC
        MOVE.B  1(A0),D0
        MOVE.B  D0,FACSIGN
        ORI.B   #$80,D0
        MOVE.B  D0,FAC+1
        MOVE.B  2(A0),FAC+2
        MOVE.B  3(A0),FAC+3
        MOVE.B  4(A0),FAC+4
        CLR.B   FACOV
        RTS
LD_ARG  MOVE.B  (A0),ARG
        MOVE.B  1(A0),D0
        MOVE.B  D0,ARISGN
        ORI.B   #$80,D0
        MOVE.B  D0,ARG+1
        MOVE.B  2(A0),ARG+2
        MOVE.B  3(A0),ARG+3
        MOVE.B  4(A0),ARG+4
        CLR.B   ARGEXT
        MOVE.B  ARISGN,D0
        MOVE.B  FACSIGN,D1      ; (EOR takes a register source
        EOR.B   D1,D0           ; only: a memory source here was
        MOVE.B  D0,SGNCPR       ; mis-encoded as EOR D0,D0)
        RTS

;---------------------------------------------------------------------
; CP_F2A / CP_F2AR -- copy FAC into ARG (the ROUNDED variant first
; rounds FAC).  (COPY_FAC_TO_ARG / COPY_FAC_TO_ARG_ROUNDED.)
; CP_A2F -- copy ARG into FAC; the extension byte is NOT copied
; (the original's MFA leaves FACEXTENSION = 0).  (COPY_ARG_TO_FAC.)
;---------------------------------------------------------------------
CP_F2AR BSR     ROUND_FAC
CP_F2A  MOVE.L  FAC,ARG         ; R2-M5: FAC and ARG are both
        MOVE.B  FAC+4,ARG+4     ; even-based, so the 5-byte copy is
        CLR.B   ARGEXT          ; a long + a byte (was 5 byte moves;
        MOVE.B  FACSIGN,ARISGN  ; the original has no ARG extension:
        CLR.B   FACOV           ; MOVAF/MOVEF copy six bytes and
        RTS                     ; zero FACOV ("since rounded" --
                                ; MOVEF does it too, unrounded)
CP_A2F  MOVE.L  ARG,FAC         ; R2-M5: same, mirrored
        MOVE.B  ARG+4,FAC+4
        CLR.B   FACOV
        MOVE.B  ARISGN,FACSIGN
        RTS

;---------------------------------------------------------------------
; ST_FAC -- round FAC and store it packed at (A0).  (SETFOR /
; STORE_FAC_AT_YX_ROUNDED.)
;---------------------------------------------------------------------
ST_FAC  BSR     ROUND_FAC
        MOVE.B  FAC,(A0)
        MOVE.B  FAC+1,D0
        ANDI.B  #$7F,D0
        MOVE.B  FACSIGN,D1
        ANDI.B  #$80,D1
        OR.B    D1,D0
        MOVE.B  D0,1(A0)
        MOVE.B  FAC+2,2(A0)
        MOVE.B  FAC+3,3(A0)
        MOVE.B  FAC+4,4(A0)
        CLR.B   FACOV           ; MOVMF: "zero it since rounded"
        RTS

;---------------------------------------------------------------------
; ST_FAC_TAG -- ST_FAC plus the R2-M1 int tag (D5): after the
; packed store at (A0) (a plain variable's or array element's
; 6-byte value field), byte +5 records whether the stored value
; is an INT (FACTYP=1: tag INTTAG) or not (tag cleared).  Only
; LETCORE and INPASSIGN_NUM use this form; direct ST_FAC callers
; (FOR/NEXT, FN argument install, TEMPF saves) leave the byte
; alone, which is safe because FRM_VARIABLE validates the tag
; against the FP shadow before honouring it.
;---------------------------------------------------------------------
ST_FAC_TAG BSR  ST_FAC
        TST.B   FACTYP
        BEQ   STF_C
        MOVE.B  #INTTAG,5(A0)
        RTS
STF_C   CLR.B   5(A0)
        RTS

;---------------------------------------------------------------------
; INC_FAC_M -- FAC mantissa (FAC+1..FAC+4) += 1.
; (INCREMENT_FAC_MANTISSA.)  Z=1 iff the mantissa wrapped to zero.
; NEGFAC40 -- negate the 40-bit field FAC+1..FAC+4:FACOV
; (COMPLEMENT_FAC_MANTISSA.)
;---------------------------------------------------------------------
INC_FAC_M ADDQ.B #1,FAC+4
        BNE   IFM_R
        ADDQ.B  #1,FAC+3
        BNE   IFM_R
        ADDQ.B  #1,FAC+2
        BNE   IFM_R
        ADDQ.B  #1,FAC+1
IFM_R   RTS
NEGFAC40 MOVE.B FAC+1,D0
        EORI.B  #$FF,D0
        MOVE.B  D0,FAC+1
        MOVE.B  FAC+2,D0
        EORI.B  #$FF,D0
        MOVE.B  D0,FAC+2
        MOVE.B  FAC+3,D0
        EORI.B  #$FF,D0
        MOVE.B  D0,FAC+3
        MOVE.B  FAC+4,D0
        EORI.B  #$FF,D0
        MOVE.B  D0,FAC+4
        MOVE.B  FACOV,D0
        EORI.B  #$FF,D0
        MOVE.B  D0,FACOV
        ADDQ.B  #1,FACOV
        BNE   NFC_R
        ADDQ.B  #1,FAC+4
        BNE   NFC_R
        ADDQ.B  #1,FAC+3
        BNE   NFC_R
        ADDQ.B  #1,FAC+2
        BNE   NFC_R
        ADDQ.B  #1,FAC+1
NFC_R   RTS

;---------------------------------------------------------------------
; ROUND_FAC -- round FAC by its extension byte (the original also
; shifts the extension left by the ASL; that side effect is kept).
; (ROUND_FAC.)
;---------------------------------------------------------------------
ROUND_FAC TST.B FAC
        BEQ   RF_R
        MOVE.B  FACOV,D0
        ADD.B   D0,FACOV        ; FACOV <<= 1 (the original's ASL
                                ; side effect; a memory byte shift
                                ; does not exist on the 68000, so the
                                ; doubling is done as an add)
        CMPI.B  #$80,D0
        BCS   RF_R            ; extension < $80: no round-up
        BSR     INC_FAC_M
        BNE   RF_R            ; no mantissa overflow
        MOVE.B  #$80,FAC+1      ; overflow: mantissa := $80000000,
        CLR.B   FAC+2           ; extension := 0, exponent += 1
        CLR.B   FAC+3
        CLR.B   FAC+4
        CLR.B   FACOV
        ADDQ.B  #1,FAC
        BEQ     OVERR           ; exponent wrapped: ?OV ERROR
RF_R    RTS

;---------------------------------------------------------------------
; ZERO_FAC -- FAC := 0 (exponent and sign cleared).
; NORMALIZE -- normalize the 40-bit mantissa in FAC+1..FAC+4:FACOV
; against the exponent in FAC.  (NORMALIZE_FAC2 loop, including
; the original's count==32 -> ZERO_FAC behaviour.)
;---------------------------------------------------------------------
ZERO_FAC CLR.B  FAC
        CLR.B   FACSIGN
        CLR.B   FACTYP          ; R2-M1: a fresh FP zero is FP
        RTS
; R2-M5: register version, bit-identical to the byte loop it
; replaces.  The 40-bit field rides in D0 (mantissa) : D1
; (extension byte); the shift count is computed with 16- and
; 8-bit chunks, then single bits (at most 7: after the chunks
; the top byte is nonzero).  A zero mantissa goes straight to
; ZERO_FAC: the old code reaches it after four byte shifts
; (count == 32), including the case where only FACOV was
; nonzero -- such a field is zero for every consumer, since
; all of them test the exponent byte before the mantissa.
; The underflow rule (count >= exponent -> ZERO_FAC) and the
; clobber set (D0-D2) are unchanged.
NORMALIZE MOVE.L FAC,D0         ; mantissa via the even-address
        ROL.L   #8,D0           ; ROL trick (as elsewhere in the
        MOVE.B  FAC+4,D0        ; pack)
        TST.L   D0
        BEQ     ZERO_FAC        ; mantissa zero: value is zero
        MOVEQ   #0,D1
        MOVE.B  FACOV,D1        ; D1 = extension byte
        MOVEQ   #0,D2           ; shift count
        CMPI.L  #$10000,D0
        BCC     NRZ_S8
        LSL.L   #8,D1           ; field <<= 16: the extension
        LSL.L   #8,D0           ; byte lands at bits 8..15 and
        LSL.L   #8,D0           ; the extension becomes 0
        OR.L    D1,D0
        MOVEQ   #0,D1
        MOVE.B  #16,D2
NRZ_S8  CMPI.L  #$1000000,D0
        BCC     NRZ_BIT
        LSL.L   #8,D0           ; field <<= 8: extension byte
        OR.L    D1,D0           ; lands at bits 0..7 (D0's low
        MOVEQ   #0,D1           ; byte was 0 after the shift)
        ADDQ.B  #8,D2
NRZ_BIT TST.L   D0
        BMI     NRZ_EXP         ; top bit set: normalized
        LSL.B   #1,D1           ; field <<= 1: extension's top
        ROXL.L  #1,D0           ; bit enters the mantissa at
        ADDQ.B  #1,D2           ; bit 0 (X from the LSL)
        BRA     NRZ_BIT
NRZ_EXP MOVE.L  D0,MANTMP       ; store the normalized field
        MOVE.B  MANTMP,FAC+1    ; (byte-staged: FAC+1 is odd)
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        MOVE.B  D1,FACOV
        MOVE.B  FAC,D0
        CMP.B   D2,D0
        BLS     ZERO_FAC        ; count >= exponent: underflow to 0
        SUB.B   D2,D0
        MOVE.B  D0,FAC
        RTS

;---------------------------------------------------------------------
; SIGN_FAC -- D0.B := 0/1/$FF as FAC is zero/positive/negative.
; (SIGN.)  SGNF -- the SGN function: FAC := that value.
; FLOAT_BYTE -- FAC := the signed byte in D0.B.  (FLOAT.)
; GIVAYF -- FAC := the signed word in D0.W; VALTYP := 0.
; FABSFN -- the ABS function.  NEGOP -- FAC := -FAC (sign flip).
;---------------------------------------------------------------------
SIGN_FAC TST.B  FAC
        BEQ   SG_0
        TST.B   FACSIGN
        BMI   SG_N
        MOVEQ   #1,D0
        RTS
SG_N    MOVEQ   #-1,D0
        RTS
SG_0    MOVEQ   #0,D0
        RTS
SGNFN   BSR     SIGN_FAC
        ; fall through into FLOAT_BYTE (a BRA to the next
        ; instruction is mis-encoded by asm68k-py: a zero
        ; displacement picks up the target's first word)
FLOAT_BYTE CLR.B FACTYP        ; R2-M1: an FP producer clears INT
        MOVE.B D0,FAC+1
        CLR.B   FAC+2
        CLR.B   FAC+3
        CLR.B   FAC+4
        CLR.B   FACOV
        CLR.B   FACSIGN
        MOVE.B  #$88,FAC
        TST.B   D0
        BPL   FB_N
        BSR     NEGFAC40
        MOVE.B  #$FF,FACSIGN
FB_N    BRA     NORMALIZE
GIVAYF  CLR.B   VALTYP
        CLR.B   FACTYP          ; R2-M1: an FP producer clears INT
        MOVE.W  D0,D1
        LSR.W   #8,D1
        MOVE.B  D1,FAC+1        ; high byte
        MOVE.B  D0,FAC+2        ; low byte
        CLR.B   FAC+3
        CLR.B   FAC+4
        CLR.B   FACOV
        CLR.B   FACSIGN
        MOVE.B  #$90,FAC
        TST.B   D1
        BPL   GIV_N
        BSR     NEGFAC40
        MOVE.B  #$FF,FACSIGN
GIV_N   BRA     NORMALIZE

;---------------------------------------------------------------------
; SFLOAT32 -- FAC := the signed 32-bit integer in D0.L, as an
; INT result (R2-M1, D1/D5): FACINT := D0, FACTYP := 1, and FAC
; receives the exact FP conversion (the dual representation).
; The magnitude is staged through MANTMP like UFLOAT; negating
; -2147483648 yields $80000000, which read unsigned IS the
; correct magnitude 2147483648.  A zero input degrades to FP
; zero through NORMALIZE's ZERO_FAC path (FACTYP cleared there)
; -- observationally identical in M1, since INT 0 and FP 0 print
; and store the same.  Clobbers D0, D1, D2 (via NORMALIZE).
;---------------------------------------------------------------------
SFLOAT32 MOVE.L D0,FACINT
        MOVE.B  #1,FACTYP
        CLR.B   FACSIGN
        TST.L   D0
        BPL   SF_P
        NEG.L   D0
        MOVE.B  #$FF,FACSIGN
SF_P    MOVE.L  D0,MANTMP
        MOVE.B  MANTMP,FAC+1
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        CLR.B   FACOV
        MOVE.B  #$A0,FAC        ; exponent 160 (as UFLOAT)
        BRA     NORMALIZE

;---------------------------------------------------------------------
; FAC32I -- if FAC (just loaded by LD_FAC, so FACOV = 0) is
; exactly an integer inside signed int32 range, set FACINT to
; it and FACTYP := 1; otherwise FACTYP := 0.  FAC itself is not
; modified.  This is the validator behind FRM_VARIABLE's int
; tag (D5): the tag in a variable record is only a hint, the
; value is always re-derived from the FP shadow, so a stale
; tag (a record re-stored by a path that does not maintain the
; tag byte) can never invent a value.  The mantissa long is
; assembled through MANTMP (FAC+1 is odd).  Clobbers D0-D3.
; With exponent e and 32-bit mantissa M (hidden bit set), the
; value is M * 2^(e-160): e = 160 is the [2^31, 2^32) band,
; e < 160 needs the low (160-e) mantissa bits clear.
;---------------------------------------------------------------------
FAC32I  CLR.B   FACTYP
        CLR.L   FACINT
        TST.B   FAC
        BEQ   F32_ZERO          ; FAC zero: INT 0
        MOVEQ   #0,D0
        MOVE.B  FAC,D0          ; D0 = exponent
        CMPI.B  #$A0,D0
        BHI   F32_R             ; e > 160: |value| >= 2^32
        MOVE.B  FAC+1,MANTMP    ; M via MANTMP (odd-safe staging)
        MOVE.B  FAC+2,MANTMP+1
        MOVE.B  FAC+3,MANTMP+2
        MOVE.B  FAC+4,MANTMP+3
        MOVE.L  MANTMP,D2       ; D2 = M
        CMPI.B  #$A0,D0
        BEQ   F32_E160          ; e = 160: the [2^31, 2^32) band
        MOVEQ   #160,D1
        SUB.B   D0,D1           ; D1 = shift = 160 - e (1..160)
        CMPI.B  #32,D1
        BCC   F32_R             ; shift >= 32: 0 < |value| < 1
        MOVE.L  D2,D3
        LSR.L   D1,D3           ; D3 = M >> shift (the magnitude)
        MOVE.L  D3,D0
        LSL.L   D1,D0
        CMP.L   D2,D0
        BNE   F32_R             ; low bits set: a fraction remains
        MOVE.L  D3,D2
        BRA   F32_SIGN
F32_E160 TST.B  FACSIGN
        BPL   F32_R             ; positive: >= 2^31, too big
        CMPI.L  #$80000000,D2
        BNE   F32_R             ; negative: only exactly -2^31 fits
F32_SIGN TST.B  FACSIGN
        BPL   F32_P
        NEG.L   D2
F32_P   MOVE.L  D2,FACINT
F32_ZERO MOVE.B #1,FACTYP        ; (zero lands here with FACINT = 0)
F32_R   RTS
FABSFN  ANDI.B  #$7F,FACSIGN
        RTS
NEGOP   TST.B   FAC             ; the original has ONE negate
        BEQ     NF_R            ; routine and it tests FACEXP:
        EORI.B  #$FF,FACSIGN    ; -0 stays +0 (PRINT -0 -> " 0",
        RTS                     ; VAL("-0") -> 0 in the golden)

;---------------------------------------------------------------------
; R2-M2 integer performers (D2/D3) -- IADD / ISUB / IMULT.
; MATPERF's + - * entries point HERE, not at the FP cores: the
; wrappers see ARGINT/ARGTYP, which only PERFORM2 restores,
; while the FP cores are also called directly by internal FP
; code (FMUL10, FADDH, FOR/NEXT, the math pack) where ARGTYP
; is meaningless -- so the integer dispatch lives in the
; wrappers, and each FP core clears FACTYP at its own head so
; every FP path (wrapped or direct) leaves an FP result.
; When both operands are INT the operation runs in int32; on
; overflow (D3) control falls into the FP core with the exact
; FP shadows in ARG/FAC untouched, and the result is FP.  On
; success the result goes through SFLOAT32 (FACINT set,
; FACTYP=1, FP shadow rebuilt).
;---------------------------------------------------------------------
IADD    TST.B   ARGTYP
        BEQ     FADD_CORE       ; an FP operand: the FP path (the
        TST.B   FACTYP          ; core clears FACTYP at its head)
        BEQ     FADD_CORE
        MOVE.L  ARGINT,D0
        ADD.L   FACINT,D0
        BVS     FADD_CORE       ; D3: overflow promotes to FP
        BRA     SFLOAT32
ISUB    TST.B   ARGTYP
        BEQ     FSUB_CORE
        TST.B   FACTYP
        BEQ     FSUB_CORE
        MOVE.L  ARGINT,D0
        SUB.L   FACINT,D0       ; ARG - FAC, as FSUB_CORE computes
        BVS     FSUB_CORE       ; D3: overflow promotes to FP
        BRA     SFLOAT32
IMULT   TST.B   ARGTYP
        BEQ     FMULT_CORE
        TST.B   FACTYP
        BEQ     FMULT_CORE
        BSR     IMUL32          ; D0.L := product, D1.B := 0, or
        TST.B   D1              ; D1.B := 1 on overflow
        BNE     FMULT_CORE      ; D3: overflow promotes to FP
        BRA     SFLOAT32

;---------------------------------------------------------------------
; IMUL32 -- the signed 32x32 multiply behind IMULT (R2-M2, D2):
; D0.L := ARGINT * FACINT when the true product fits in signed
; int32 (D1.B := 0); on overflow D1.B := 1 and D0 is meaningless
; (the caller promotes to FP, D3).  MULU is 16x16->32 only, so
; the product is built from the magnitudes' 16-bit partial
; products: with a = ah*2^16+al and b = bh*2^16+bl,
;   |a*b| = p0 + (p1+p2)*2^16 + p3*2^32
; (p0 = al*bl, p1 = al*bh, p2 = ah*bl, p3 = ah*bh).  The high
; word (bits 32..63) is accumulated on the side; overflow is
; high /= 0, or a low word past the signed limit for the
; product's sign (2^31-1 positive, 2^31 negative).  Working in
; magnitudes makes -2147483648 safe: its magnitude 2^31 is an
; ordinary unsigned 32-bit value, and NEG.L of it is itself.
; Shift counts are two #8 steps (a #16 count is not encodable).
; Clobbers D0-D7.
;---------------------------------------------------------------------
IMUL32  MOVE.L  ARGINT,D0       ; D0 := |a|
        BPL     IM_A
        NEG.L   D0
IM_A    MOVE.L  FACINT,D1       ; D1 := |b|
        BPL     IM_B
        NEG.L   D1
IM_B    MOVE.L  D0,D2           ; D2 := al
        ANDI.L  #$0000FFFF,D2
        MOVE.L  D0,D3           ; D3 := ah
        LSR.L   #8,D3
        LSR.L   #8,D3
        MOVE.L  D1,D4           ; D4 := bl
        ANDI.L  #$0000FFFF,D4
        MOVE.L  D1,D5           ; D5 := bh
        LSR.L   #8,D5
        LSR.L   #8,D5
        MOVE.L  D2,D6           ; D6 := p1 = al*bh
        MULU    D5,D6
        MOVE.L  D3,D7           ; D7 := p2 = ah*bl
        MULU    D4,D7
        ADD.L   D7,D6           ; D6 := mid = p1+p2; X := its carry
        MOVEQ   #0,D7
        ADDX.L  D7,D7           ; D7 := mid carry (0/1)
        LSL.L   #8,D7
        LSL.L   #8,D7           ; << 16: its place in the high word
        MULU    D4,D2           ; D2 := p0 = al*bl
        MOVE.L  D6,D1           ; low += mid << 16 (only mid's low
        LSL.L   #8,D1           ; word survives the shift)
        LSL.L   #8,D1
        ADD.L   D1,D2           ; D2 := product low word; X := carry
        MOVEQ   #0,D0
        ADDX.L  D0,D0           ; D0 := low carry (0/1)
        MULU    D5,D3           ; D3 := p3 = ah*bh
        MOVE.L  D6,D1           ; high += mid >> 16
        LSR.L   #8,D1
        LSR.L   #8,D1
        ADD.L   D1,D3
        ADD.L   D7,D3           ; high += mid carry << 16
        ADD.L   D0,D3           ; high += low carry
        MOVEQ   #0,D1           ; D1.B := 0: fits, unless shown not
        TST.L   D3
        BNE     IM_OV           ; high /= 0: |product| >= 2^32,
                                ; past either signed limit
        MOVE.L  ARGINT,D0       ; the product is negative iff the
        EOR.L   FACINT,D0       ; operands' signs differ
        BMI     IM_NEG
        CMPI.L  #$80000000,D2
        BCC     IM_OV           ; positive: low must be < 2^31
        MOVE.L  D2,D0
        RTS
IM_NEG  CMPI.L  #$80000000,D2
        BHI     IM_OV           ; negative: low must be <= 2^31
        MOVE.L  D2,D0
        NEG.L   D0              ; (2^31 negates to itself: -2^31)
        RTS
IM_OV   MOVEQ   #1,D1
        RTS

;---------------------------------------------------------------------
; R2-M3 integer-division performers (D2) -- IDIVW / IMODW, the
; MATPERF entries for \ (index 10) and MOD (index 11).  The
; language semantics are BASIC-80's, widened to int32, written
; clean-room here: BOTH operands are first converted to int32
; with the assignment conversion (FAC2INT, the STO_INT32 core:
; floor after mantissa rounding, so 5.5 -> 5 and -5.5 -> -6;
; an INT operand passes through unchanged).  Conversion out of
; int32 range is ?IQ -- D3's silent promotion does NOT apply
; to \ and MOD (there is no FP form of these operators to
; promote into).  Division truncates toward zero; MOD is the
; truncated remainder, so its sign follows the DIVIDEND.
; A zero divisor is the existing ?/0 (DZERR) -- checked after
; conversion, so 1\0.5 is /0 too (0.5 converts to 0).  The one
; quotient that cannot fit, -2147483648 \ -1, is ?IQ for \;
; MOD never needs the quotient, and IDIV32 computes the
; remainder without it, so -2147483648 MOD -1 = 0 works.
; The right operand (FAC, the divisor) is converted first.
;---------------------------------------------------------------------
IDIVW   BSR     FAC2INT         ; divisor -> FACINT (FAC destroyed)
        MOVE.L  FACINT,-(SP)    ; park it across the dividend's
        BSR     IDIVCVT         ; conversion: D6 := dividend
        MOVE.L  (SP)+,D7        ; D7 := divisor
        TST.L   D7
        BEQ     DZERR           ; division by zero
        BSR     IDIV32          ; D0 := quotient, D1 := remainder,
        TST.B   D2              ; D2.B := quotient-overflow flag
        BNE     IQERR           ; -2^31 \ -1: the one overflow
        BRA     SFLOAT32        ; quotient as an INT result
IMODW   BSR     FAC2INT         ; as IDIVW, but the result is
        MOVE.L  FACINT,-(SP)    ; IDIV32's remainder, whose sign
        BSR     IDIVCVT         ; follows the dividend; the
        MOVE.L  (SP)+,D7        ; quotient's overflow flag is
        TST.L   D7              ; irrelevant here
        BEQ     DZERR
        BSR     IDIV32
        MOVE.L  D1,D0           ; remainder -> the result slot
        BRA     SFLOAT32
; IDIVCVT -- D6.L := the ARG (dividend) operand as an int32:
; ARGINT when ARGTYP is INT, else ARG's FP shadow converted by
; FAC2INT (which destroys FAC -- the divisor already rides the
; stack).  May raise ?IQ through FAC2INT.
IDIVCVT TST.B   ARGTYP
        BNE     IDVC_I
        BSR     CP_A2F          ; FAC := ARG (the FP shadow)
        CLR.B   FACTYP
        BSR     FAC2INT
        MOVE.L  FACINT,D6
        RTS
IDVC_I  MOVE.L  ARGINT,D6
        RTS

;---------------------------------------------------------------------
; IDIV32 -- signed 32/32 division (R2-M3, D2): the 68000's
; DIVS/DIVU take a 16-bit divisor only, so this is a 32-step
; shift-subtract over the operands' magnitudes.
; In:  D6.L = dividend, D7.L = divisor (nonzero, checked by the
;      caller).
; Out: D0.L = quotient truncated toward zero, D1.L = remainder
;      (sign of the dividend), D2.B = 1 iff the quotient's
;      magnitude is 2^31 with a positive sign (the -2^31 / -1
;      case: the bits in D0 are then $80000000 and the caller
;      decides -- \ raises ?IQ, MOD ignores the quotient).
; Working in magnitudes makes -2^31 safe (its magnitude is the
; ordinary unsigned $80000000).  Clobbers D0-D5.
;---------------------------------------------------------------------
IDIV32  MOVEQ   #0,D4           ; D4.B: quotient is negative
        MOVEQ   #0,D5           ; D5.B: dividend is negative
        MOVE.L  D6,D0           ; D0 := |dividend| (the working
        BPL     ID3_A           ; quotient register)
        NEG.L   D0
        MOVEQ   #1,D5
        MOVEQ   #1,D4
ID3_A   MOVE.L  D7,D2           ; D2 := |divisor|
        BPL     ID3_B
        NEG.L   D2
        EORI.B  #1,D4           ; divisor's sign flips the quotient
ID3_B   MOVEQ   #0,D1           ; D1 := remainder (magnitudes)
        MOVEQ   #32,D3          ; 32 shift-subtract steps
ID3_L   ADD.L   D0,D0           ; Q <<= 1; the top bit leaves via X
        ADDX.L  D1,D1           ; R := (R << 1) | X
        CMP.L   D2,D1
        BCS     ID3_N           ; R < |divisor|: no subtraction
        SUB.L   D2,D1           ; R -= |divisor|
        ADDQ.L  #1,D0           ; Q |= 1 (its low bit is 0 here)
ID3_N   SUBQ.W  #1,D3
        BNE     ID3_L
        MOVEQ   #0,D2           ; D2.B := quotient overflow flag
        TST.B   D4
        BNE     ID3_QN
        CMPI.L  #$80000000,D0   ; a positive quotient of 2^31 is
        BNE     ID3_QS          ; the only one that cannot fit
        MOVEQ   #1,D2
        BRA     ID3_QS
ID3_QN  NEG.L   D0              ; (2^31 negates to itself: -2^31,
                                ; which DOES fit, flag stays 0)
ID3_QS  TST.B   D5
        BEQ     ID3_R
        NEG.L   D1              ; remainder takes dividend's sign
ID3_R   RTS

;---------------------------------------------------------------------
; FADD_CORE -- FAC := FAC + ARG (ARG loaded, SGNCPR set).
; (FADDT.)  Exact 40-bit sign-magnitude add/subtract: the smaller
; exponent operand is aligned into RESULT (bits shifted out are
; lost for an add, and act as a sticky -1 for a subtract, which
; is what the original's complement trick computes).  If the
; exponents are equal the "big" operand is FAC.
;---------------------------------------------------------------------
FADD_CORE CLR.B FACTYP        ; R2-M2: an FP result is FP (the
                                ; integer path lives in IADD; this
                                ; also covers direct internal calls)
        TST.B   FAC
        BEQ     CP_A2F          ; FAC = 0: result is ARG
        TST.B   ARG
        BEQ   FAD_RTS         ; ARG = 0: FAC unchanged
        MOVE.B  FAC,D6          ; D6 = big exponent
        MOVEQ   #0,D7           ; D7.B = shift count
        MOVE.B  ARG,D0
        CMP.B   FAC,D0
        BHI   FAD_ABIG        ; ARG exp > FAC exp: big = ARG
        MOVE.B  FAC,D7
        SUB.B   ARG,D7          ; shift = FACexp - ARGexp
        LEA     ARG,A1          ; small = ARG
        LEA     FAC,A2          ; big = FAC
        MOVE.B  FACSIGN,D4      ; D4 = result sign if no borrow
        MOVE.B  ARISGN,D3       ; D3 = result sign if borrow
        BRA   FAD_SH
FAD_ABIG MOVE.B ARG,D6
        MOVE.B  ARG,D7
        SUB.B   FAC,D7          ; shift = ARGexp - FACexp
        LEA     FAC,A1          ; small = FAC
        LEA     ARG,A2          ; big = ARG
        MOVE.B  ARISGN,D4
        MOVE.B  FACSIGN,D3
        ; R2-M5: the small operand's 40-bit field rides in
        ; registers (D0 = mantissa, D1 = extension byte) instead
        ; of the RESULT memory field.  The alignment is the old
        ; loop's exact arithmetic -- byte shifts while the
        ; count is >= 8 (the byte about to fall out feeds the
        ; sticky), then single bits (the falling bit feeds the
        ; sticky) -- with one shortcut: once the field is zero
        ; the remaining shifts change nothing, as the old loop
        ; shifting zeros shows.  The operation itself is one
        ; ADD.B/SUB.B + ADDX.L/SUBX.L pair (FAD_OP below); the
        ; carry shift, the sticky -1 tail and the borrow path
        ; are the old code.
FAD_SH  MOVE.L  D2,-(SP)        ; R2-M5: the register version
                                ; works in D2, but the old
                                ; byte-chain FADD preserved D2
                                ; and callers rely on it (FIN
                                ; parks the digit in D2 across
                                ; FMUL10).  Save it here -- both
                                ; entries pass through FAD_SH --
                                ; and restore it at every exit
                                ; below (OVERR needs none: ERROR
                                ; resets SP to STACKTOP).
        MOVE.L  (A1),D0         ; small mantissa (ROL trick)
        ROL.L   #8,D0
        MOVE.B  4(A1),D0
        TST.L   D0
        MOVEQ   #0,D1
        MOVE.B  5(A1),D1        ; D1 = small extension byte
        MOVEQ   #0,D5           ; D5.B = sticky (bits lost)
FAD_SB  CMPI.B  #8,D7
        BCS   FAD_SBIT
        TST.B   D1              ; byte shift right; lost byte?
        BEQ   FAD_SB1
        MOVEQ   #1,D5
FAD_SB1 MOVE.B  D0,D1           ; new extension := mantissa's
        LSR.L   #8,D0           ; low byte; mantissa >>= 8
        SUBI.B  #8,D7
        MOVE.L  D0,D2           ; field exhausted (both words
        OR.L    D1,D2           ; zero)?  then the rest of the
        BEQ   FAD_OP            ; alignment is a no-op
        BRA   FAD_SB
FAD_SBIT TST.B  D7
        BEQ   FAD_OP
        MOVE.B  D1,D2           ; bit shift right; the bit
        ANDI.B  #1,D2           ; about to fall out feeds
        OR.B    D2,D5           ; the sticky
        MOVE.B  D0,D2           ; mantissa's bit 0 -> the
        ANDI.B  #1,D2           ; extension's bit 7
        LSL.B   #7,D2
        LSR.B   #1,D1
        OR.B    D2,D1
        LSR.L   #1,D0
        SUBQ.B  #1,D7
        BRA   FAD_SBIT
FAD_OP  TST.B   SGNCPR
        BMI     FAD_SUB
        ; ---- add path: FAC field := big + small ----
        ; R2-M5: the 40-bit add is one ADD.B + ADDX.L pair
        ; (extension byte, then the mantissa long through X).
        ; A byte-wise chain cannot feed the small operand from
        ; a register: the LSR used to expose the next byte
        ; would destroy X between ADDX steps.
        MOVE.L  (A2),D2         ; big mantissa (ROL trick)
        ROL.L   #8,D2
        MOVE.B  4(A2),D2
        TST.L   D2
        MOVEQ   #0,D7
        MOVE.B  5(A2),D7        ; D7 = big extension byte
        ADD.B   D1,D7           ; L := big + small ext; X :=
        ADDX.L  D0,D2           ; carry; H := big + small + X
        BCC   FAD_NC            ; no carry out (C = X here)
        ROXR.L  #1,D2           ; carry: the 41-bit result
        ROXR.B  #1,D7           ; shifts right once (X in at
                                ; the top, exactly the old
                                ; chain's ROXR pair)
        MOVE.L  D2,MANTMP
        MOVE.B  MANTMP,FAC+1
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        MOVE.B  D7,FACOV
        MOVE.B  D4,FACSIGN
        MOVE.B  D6,FAC
        ADDQ.B  #1,FAC
        BEQ     OVERR           ; (ERROR resets SP: no restore)
        MOVE.L  (SP)+,D2        ; R2-M5: restore the caller's D2
        RTS
FAD_NC  MOVE.L  D2,MANTMP
        MOVE.B  MANTMP,FAC+1
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        MOVE.B  D7,FACOV
        MOVE.B  D4,FACSIGN
        MOVE.B  D6,FAC
        MOVE.L  (SP)+,D2        ; R2-M5: restore (see FAD_SH)
        RTS
FAD_RTS RTS
        ; ---- subtract path: FAC field := big - small - sticky --
FAD_SUB MOVE.L  (A2),D2         ; big mantissa (ROL trick)
        ROL.L   #8,D2
        MOVE.B  4(A2),D2
        TST.L   D2
        MOVEQ   #0,D7
        MOVE.B  5(A2),D7        ; D7 = big extension byte
        SUB.B   D1,D7           ; L := big - small ext; X :=
        SUBX.L  D0,D2           ; borrow; H := big - small - X
        BCS   FAD_SB1X          ; borrow out (C tested before
        MOVEQ   #0,D1           ; any MOVE clears it)
        BRA   FAD_STF
FAD_SB1X MOVEQ  #1,D1           ; D1.B = borrow out
FAD_STF MOVE.L  D2,MANTMP       ; field into FAC (the sticky
        MOVE.B  MANTMP,FAC+1    ; tail below works on FAC
        MOVE.B  MANTMP+1,FAC+2  ; memory, as before)
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        MOVE.B  D7,FACOV
        BRA   FAD_SST2
FAD_SB1B MOVEQ  #1,D1
FAD_SST MOVE.B  D0,FAC+1
FAD_SST2
        TST.B   D5              ; apply the sticky -1
        BEQ   FAD_SBR
        SUBQ.B  #1,FACOV
        CMPI.B  #$FF,FACOV
        BNE   FAD_SBR
        SUBQ.B  #1,FAC+4
        CMPI.B  #$FF,FAC+4
        BNE   FAD_SBR
        SUBQ.B  #1,FAC+3
        CMPI.B  #$FF,FAC+3
        BNE   FAD_SBR
        SUBQ.B  #1,FAC+2
        CMPI.B  #$FF,FAC+2
        BNE   FAD_SBR
        SUBQ.B  #1,FAC+1
        CMPI.B  #$FF,FAC+1
        BNE   FAD_SBR
        MOVEQ   #1,D1           ; the -1 borrowed out too
FAD_SBR MOVE.B  D6,FAC
        TST.B   D1
        BEQ   FAD_SN
        BSR     NEGFAC40        ; borrowed: negate, sign flips
        MOVE.B  D3,FACSIGN
        BRA     FAD_POPN
FAD_SN  MOVE.B  D4,FACSIGN
FAD_POPN MOVE.L (SP)+,D2        ; R2-M5: restore D2 (see FAD_SH);
                                ; NORMALIZE then clobbers it again,
                                ; exactly as the old chain did
        BRA     NORMALIZE

; FSUB_CORE -- the subtraction performer: FAC := ARG - FAC is NOT
; what happens; as in the original (FSUBT), FACSIGN is flipped and
; SGNCPR recomputed, then FADDT runs: FAC := FAC + ARG with the
; flipped sign, i.e. ARG - (original FAC) with operands swapped
; by the perform frame: the net is (stacked) - (current).
FSUB_CORE EORI.B #$FF,FACSIGN
        MOVE.B  FACSIGN,D0
        MOVE.B  ARISGN,D1       ; (EOR register source only)
        EOR.B   D1,D0
        MOVE.B  D0,SGNCPR
        BRA     FADD_CORE

; FADD_MEM / FMULT_MEM / FDIV_MEM -- the (Y,A)-address forms:
; load ARG from the packed value at (A0), then the core routine.
FADD_MEM BSR    LD_ARG
        BRA     FADD_CORE
FMULT_MEM BSR   LD_ARG
        BRA     FMULT_CORE
FDIV_MEM BSR    LD_ARG
        BRA     FDIV_CORE

; FADDH -- FAC += 0.5 (the original's FADDH, used by FOUT).
FADDH   LEA     CON_HALF(PC),A0
        BSR     LD_ARG
        BRA     FADD_CORE

; FMUL10 -- FAC *= 10 (the original's MUL10: round, copy to ARG,
; exponent += 2, FADD2 for the +1/4 part, exponent += 1).
FMUL10  BSR     CP_F2AR
        TST.B   FAC
        BEQ   FM10_R
        MOVE.B  FAC,D0
        ADDQ.B  #2,D0
        BCS     OVERR
        MOVE.B  D0,FAC
        CLR.B   SGNCPR
        BSR     FADD_CORE
        ADDQ.B  #1,FAC
        BEQ     OVERR
FM10_R  RTS

; FDIV10 -- FAC /= 10 (the original's DIV10).
FDIV10  BSR     CP_F2AR
        LEA     CONTEN(PC),A0
        BSR     LD_FAC
        CLR.B   SGNCPR
        BRA     FDIV_CORE

;---------------------------------------------------------------------
; FMULT_CORE -- FAC := FAC * ARG (ARG loaded, SGNCPR set).
; (FMULTT.)  The original's 40-bit shift-and-add computes the
; exact 40-bit truncation floor(Mcand * B40 / 2^32) (see the
; proof sketch at the implementation); R2-M5 computes the
; same floor with MULU partial products (UMUL64).  If FAC
; (the multiplier) is zero the original simply returns,
; leaving FAC untouched; a zero ARG goes through
; ADD_EXPONENTS to ZERO_FAC.
;---------------------------------------------------------------------
FMULT_CORE CLR.B FACTYP       ; R2-M2: FP result (see FADD_CORE)
        TST.B   FAC
        BEQ   FMU_RTS         ; FAC = 0: plain return (original)
        TST.B   ARG
        BEQ     ZERO_FAC        ; ARG = 0: result zero (the
                                ; original's MULDIV checks ARGEXP
                                ; first -- without this, a packed
                                ; zero loaded by LD_ARG still has
                                ; the hidden bit set and the product
                                ; comes out as FAC * 2^-129 garbage:
                                ; POLYX(0) for SIN(0) hit exactly
                                ; this via TEMPF2 = 0)
        MOVEQ   #0,D6           ; new exponent = ARGexp+FACexp-128
        MOVE.B  ARG,D6
        MOVEQ   #0,D0
        MOVE.B  FAC,D0
        ADD.W   D0,D6
        SUBI.W  #128,D6
        BLE     ZERO_FAC        ; <= 0: underflow to zero
        CMPI.W  #255,D6
        BHI     OVERR
        MOVE.B  D6,TMPEXP
        MOVE.B  SGNCPR,FACSIGN
        ; R2-M5: the exact product in registers (UMUL64).  The
        ; bit-serial loop this replaces computes, provably,
        ; floor(Mcand * B40 / 2^32): each add-and-rotate step
        ; keeps 2^40*acc = Mcand*2^8*(bits consumed) - D with
        ; 0 <= D < 2^40, and D is forced to (product mod 2^40),
        ; so after 40 bits acc is that exact floor (the zero-
        ; byte shortcut is the same floor taken 8 bits at a
        ; time).  Here Mcand = ARG mantissa (32 bits) and B40 =
        ; FAC's field (mantissa:FACOV).  Split B40 = B32*2^8 +
        ; FACOV: Mcand*B40 = P*2^8 + T with P = Mcand*B32
        ; (64-bit) and T = Mcand*FACOV (40-bit), and the floor
        ; is (P >> 24) + (T >> 32) + carry, the carry being 1
        ; iff ((P mod 2^24) << 8) + (T mod 2^32) >= 2^32.
        MOVE.L  ARG,D7          ; Mcand (ROL trick, as before)
        ROL.L   #8,D7
        MOVE.B  ARG+4,D7
        TST.L   D7
        ; T := Mcand * FACOV first, while Mcand is fresh.
        ; FACOV is a single byte, so two MULUs suffice:
        ; T = (mh*ov) << 16 + (ml*ov), each product < 2^24.
        ; A zero FACOV (every freshly loaded operand) skips
        ; the correction entirely.
        TST.B   FACOV
        BEQ     FMU_T0
        MOVEQ   #0,D6
        MOVE.B  FACOV,D6        ; D6 = ov
        MOVE.L  D7,D0
        LSR.L   #8,D0
        LSR.L   #8,D0           ; D0 = mh
        MULU    D6,D0           ; t1 = mh*ov (< 2^24)
        MOVE.L  D7,D1
        ANDI.L  #$0000FFFF,D1   ; ml
        MULU    D6,D1           ; t0 = ml*ov (< 2^24)
        MOVE.L  D0,D2
        ANDI.L  #$0000FFFF,D2
        LSL.L   #8,D2
        LSL.L   #8,D2           ; (t1 mod 2^16) << 16
        ADD.L   D1,D2           ; Tlo := that + t0; X := carry
        MOVEQ   #0,D1
        ADDX.L  D1,D1           ; the carry into T's high word
        LSR.L   #8,D0
        LSR.L   #8,D0           ; t1 >> 16
        ADD.L   D1,D0           ; Thi := (t1 >> 16) + carry
        BRA     FMU_TP
FMU_T0  MOVEQ   #0,D0           ; FACOV = 0: T = 0
        MOVEQ   #0,D2
FMU_TP  MOVE.L  D0,-(SP)        ; park Thi / Tlo across the
        MOVE.L  D2,-(SP)        ; main multiply (D7 survived:
                                ; the T path only reads it)
        MOVE.L  FAC,D6          ; B32 = FAC mantissa
        ROL.L   #8,D6
        MOVE.B  FAC+4,D6
        TST.L   D6
        BSR     UMUL64          ; P := Mcand * B32 -> D1:D0
        MOVE.L  D0,D3
        ANDI.L  #$FFFFFF,D3     ; D3 = P mod 2^24
        MOVE.L  D0,D4           ; result low := P >> 24 (low):
        LSR.L   #8,D4           ; P.lo >> 24, plus (P.hi mod
        LSR.L   #8,D4           ; 2^24) << 8
        LSR.L   #8,D4
        MOVE.L  D1,D0
        ANDI.L  #$FFFFFF,D0
        LSL.L   #8,D0
        OR.L    D0,D4
        MOVE.L  D1,D5           ; result high := P.hi >> 24
        LSR.L   #8,D5           ; (the 40-bit result's top
        LSR.L   #8,D5           ; byte)
        LSR.L   #8,D5
        MOVE.L  (SP)+,D0        ; T mod 2^32
        MOVE.L  (SP)+,D1        ; T >> 32
        LSL.L   #8,D3           ; (P mod 2^24) << 8
        ADD.L   D0,D3           ; + T mod 2^32: X := the carry
        MOVEQ   #0,D0
        ADDX.L  D0,D0           ; D0 = carry (0/1)
        ADD.L   D0,D1           ; delta = (T >> 32) + carry
        ADD.L   D1,D4           ; result += delta
        BCC     FMU_ST
        ADDQ.L  #1,D5
FMU_ST  MOVE.L  D4,D0           ; mantissa := result >> 8
        LSR.L   #8,D0
        MOVE.L  D5,D1
        LSL.L   #8,D1
        LSL.L   #8,D1
        LSL.L   #8,D1           ; result high << 24
        OR.L    D1,D0
        MOVE.L  D0,MANTMP       ; result back into FAC (byte-
        MOVE.B  MANTMP,FAC+1    ; staged store: FAC+1 is odd),
        MOVE.B  MANTMP+1,FAC+2  ; extension := result & $FF,
        MOVE.B  MANTMP+2,FAC+3  ; exponent := TMPEXP, normalize
        MOVE.B  MANTMP+3,FAC+4
        MOVE.B  D4,FACOV
        MOVE.B  TMPEXP,FAC
        BRA     NORMALIZE
FMU_RTS RTS

;---------------------------------------------------------------------
; UMUL64 -- unsigned 32x32 -> 64 multiply (R2-M5).
; In:  D6.L = a, D7.L = b.  Out: D1.L = high, D0.L = low.
; Clobbers D2-D7 (the inputs are consumed).  16-bit partial
; products -- the same construction as IMUL32, but keeping
; the full 64-bit result instead of range-checking it.
;---------------------------------------------------------------------
UMUL64  MOVE.L  D6,D2
        ANDI.L  #$0000FFFF,D2   ; D2 = al
        MOVE.L  D6,D3
        LSR.L   #8,D3
        LSR.L   #8,D3           ; D3 = ah
        MOVE.L  D7,D4
        ANDI.L  #$0000FFFF,D4   ; D4 = bl
        MOVE.L  D7,D5
        LSR.L   #8,D5
        LSR.L   #8,D5           ; D5 = bh
        MOVE.L  D3,D6
        MULU    D5,D6           ; D6 = p3 = ah*bh
        MOVE.L  D2,D0
        MULU    D4,D0           ; D0 = p0 = al*bl
        MOVE.L  D2,D1
        MULU    D5,D1           ; D1 = p1 = al*bh
        MOVE.L  D3,D7
        MULU    D4,D7           ; D7 = p2 = ah*bl
        ADD.L   D7,D1           ; D1 = mid = p1+p2
        MOVEQ   #0,D2
        ADDX.L  D2,D2           ; D2 = mid carry (0/1)
        MOVE.L  D1,D3
        LSL.L   #8,D3
        LSL.L   #8,D3           ; mid << 16 (its low word)
        ADD.L   D3,D0           ; D0 = product low
        MOVEQ   #0,D3
        ADDX.L  D3,D3           ; D3 = low carry (0/1)
        MOVE.L  D1,D4
        LSR.L   #8,D4
        LSR.L   #8,D4           ; mid >> 16
        ADD.L   D6,D4           ; high = p3 + (mid >> 16)
        LSL.L   #8,D2
        LSL.L   #8,D2           ; mid carry << 16
        ADD.L   D2,D4
        ADD.L   D3,D4           ; high += low carry
        MOVE.L  D4,D1           ; D1 = product high
        RTS

;---------------------------------------------------------------------
; FDIV_CORE -- FAC := ARG / FAC (ARG loaded, SGNCPR set).
; (FDIVT.)  The divisor (in FAC) is rounded first; a zero divisor
; is ?/0 ERROR, checked before the dividend.  The quotient is
; generated as exactly 34 bits by restoring division:
; Q34 = floor(ARGmant * 2^33 / FACmant); the result mantissa is
; Q34 >> 2 and the extension byte is (Q34 & 3) << 6.
;---------------------------------------------------------------------
FDIV_CORE CLR.B FACTYP        ; R2-M2 (D2): / is always FP
        TST.B   FAC
        BEQ     DZERR           ; divide by zero
        BSR     ROUND_FAC       ; round the divisor
        TST.B   ARG
        BEQ     ZERO_FAC        ; dividend zero: result zero
        MOVEQ   #0,D6           ; new exponent = ARGexp-FACexp+129
        MOVE.B  ARG,D6
        MOVEQ   #0,D0
        MOVE.B  FAC,D0
        SUB.W   D0,D6
        ADDI.W  #129,D6
        CMPI.W  #255,D6
        BHI     OVERR
        TST.W   D6
        BLE     ZERO_FAC        ; < 1: underflow to zero
        MOVE.B  D6,TMPEXP
        MOVE.B  SGNCPR,FACSIGN
        MOVE.L  ARG,D6          ; dividend mantissa (M5e: both
        ROL.L   #8,D6           ; mantissa longs assembled via
        MOVE.B  ARG+4,D6        ; even accesses, was ARG+1/FAC+1)
        TST.L   D6
        MOVE.L  FAC,D3          ; divisor mantissa
        ROL.L   #8,D3
        MOVE.B  FAC+4,D3
        TST.L   D3
        ; R2-M5: the first 31 restoring steps provably do
        ; nothing but shift.  The remainder after k steps is
        ; the dividend's top k bits (< 2^k), and both
        ; mantissas are normalised (>= 2^31), so for k <= 31
        ; the remainder is below the divisor: no subtraction
        ; can fire and every quotient bit is 0.  Start from
        ; the exact state after step 31 -- remainder =
        ; dividend >> 1, the dividend shifter = dividend << 31
        ; (the next bit out is the dividend's bit 0, then
        ; zeros), quotient = 0 -- and run the remaining 34
        ; steps of the unchanged loop.
        MOVE.L  D6,D2           ; remainder low := dividend >> 1
        LSR.L   #1,D2
        MOVEQ   #0,D1           ; remainder high
        LSL.L   #8,D6           ; dividend <<= 31
        LSL.L   #8,D6
        LSL.L   #8,D6
        LSL.L   #7,D6
        MOVEQ   #0,D4           ; quotient (D5:D4)
        MOVEQ   #0,D5
        MOVE.W  #34,D7          ; 34 restoring steps -> 34 bits
FDV_L   LSL.L   #1,D6           ; next dividend bit -> X
        ROXL.L  #1,D2           ; remainder <<= 1, bit in
        ROXL.L  #1,D1
        MOVEQ   #0,D0           ; quotient bit := 0
        TST.L   D1
        BNE   FDV_SUB         ; remainder >= 2^32: must subtract
        CMP.L   D3,D2
        BCS   FDV_Q           ; remainder < divisor: bit stays 0
FDV_SUB SUB.L   D3,D2
        BCC   FDV_S1
        SUBQ.L  #1,D1           ; borrow out of the low word
FDV_S1  MOVEQ   #1,D0
FDV_Q   LSL.L   #1,D4           ; quotient <<= 1, bit in
        ROXL.L  #1,D5
        OR.B    D0,D4
        SUBQ.W  #1,D7
        BNE   FDV_L
        MOVE.B  D4,D0           ; extension := (Q34 & 3) << 6
        ANDI.B  #3,D0
        LSL.B   #6,D0
        MOVE.B  D0,FACOV
        LSR.L   #2,D4           ; mantissa := Q34 >> 2
        MOVE.L  D5,D0
        ANDI.L  #3,D0
        LSL.L   #8,D0
        LSL.L   #8,D0
        LSL.L   #8,D0
        LSL.L   #6,D0
        OR.L    D0,D4
        MOVE.L  D4,MANTMP       ; M5e: byte-staged store (was
        MOVE.B  MANTMP,FAC+1    ; MOVE.L D4,FAC+1)
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        TST.L   D4
        MOVE.B  TMPEXP,FAC
        BRA     NORMALIZE

;---------------------------------------------------------------------
; FCOMP -- compare the packed value at (A0) against FAC.
; (FCOMP.)  Returns D0.B: 1 if the packed value is less than FAC,
; 0 if equal, $FF if greater.  A packed exponent of 0 returns
; SIGN(FAC).  The last mantissa byte comparison is biased by the
; extension byte exactly as the original: the borrow into it is
; set iff FACOV > $7F.
;---------------------------------------------------------------------
FCOMP   MOVE.B  (A0),D1         ; packed exponent
        BEQ   FCMP_PS         ; packed is zero: SIGN(FAC)
        MOVE.B  1(A0),D2
        MOVE.B  FACSIGN,D0
        EOR.B   D2,D0
        BMI   FCMP_SD         ; signs differ: answer from FACSIGN
        MOVE.B  FAC,D0
        CMP.B   D1,D0           ; FACexp - Pexp
        BCS   FCMP_EL         ; Pexp > FACexp: P magnitude bigger
        BNE   FCMP_EG0        ; Pexp < FACexp: flag = 0
        MOVE.B  1(A0),D0        ; exponents equal: byte compare
        ORI.B   #$80,D0
        CMP.B   FAC+1,D0
        BNE   FCMP_DF
        MOVE.B  2(A0),D0
        CMP.B   FAC+2,D0
        BNE   FCMP_DF
        MOVE.B  3(A0),D0
        CMP.B   FAC+3,D0
        BNE   FCMP_DF
        MOVEQ   #0,D0           ; last byte, with the original's
        MOVE.B  4(A0),D0        ; extension bias: the 6502 FCOMP
        MOVEQ   #0,D1           ; computes P4 - FAC4 - (FACOV > $7F
        MOVE.B  FAC+4,D1        ; ? 1 : 0) in a single SBC chain.
        SUB.W   D1,D0           ; A byte-wise SUB+SUBQ loses the
        CMPI.B  #$7F,FACOV      ; borrow when P4 < FAC4, which
        BLS     FCMP_LB0        ; misjudged a 1-ulp difference in
        SUBQ.W  #1,D0           ; FOUT's scaling loop (99.9999999
FCMP_LB0 TST.W   D0              ; printed ":0"); word math instead
        BEQ     FCMP_EQ
        BMI     FCMP_LB2        ; diff < 0: |P| < |FAC|
        MOVEQ   #1,D2           ; diff > 0: |P| > |FAC|
        BRA     FCMP_DF2
FCMP_LB2 MOVEQ  #0,D2
        BRA     FCMP_DF2
FCMP_EL MOVEQ   #1,D2           ; difference with P >= FAC: flag 1
        BRA   FCMP_DF2
FCMP_EG0 MOVEQ  #0,D2
        BRA   FCMP_DF2
FCMP_DF BCC   FCMP_DF1        ; carry set: P byte >= FAC byte
        MOVEQ   #0,D2
        BRA   FCMP_DF2
FCMP_DF1 MOVEQ  #1,D2
FCMP_DF2 MOVE.B FACSIGN,D0
        TST.B   D2
        BEQ   FCMP_S2
        EORI.B  #$FF,D0
FCMP_S2 TST.B   D0
        BMI   FCMP_GT
        MOVEQ   #1,D0
        RTS
FCMP_GT MOVEQ   #-1,D0
        RTS
FCMP_SD MOVE.B  FACSIGN,D0      ; signs differ: FAC's sign alone
        BRA   FCMP_S2           ; decides (the EOR above left D0
                                ; holding the DIFFERENCE of the
                                ; signs, which is always negative
                                ; on this path -- the Phase 1 code
                                ; branched to FCMP_S2 with that D0
                                ; and so always answered -1 when
                                ; the signs differed: 1>-1 came out
                                ; right by accident, -1<1 and a
                                ; FOR..TO -1 loop came out wrong)
FCMP_EQ MOVEQ   #0,D0
        RTS
FCMP_PS BSR     SIGN_FAC
        RTS

;---------------------------------------------------------------------
; QINT -- convert FAC to a fixed-point integer in place: the
; 40-bit field FAC+1..FAC+4:FACOV becomes the two's complement
; integer scaled by 2^8 (so FAC+1..FAC+4 hold the integer part).
; (QINT.)  INTFN -- the INT function: FAC := floor(FAC).
; AYINT -- QINT with the original's range check: exponents >= $90
; are ?ILLEGAL QUANTITY, including exactly -32768 (the original's
; short NEG32768 constant makes its FCOMP allowance unreachable;
; see AYINT itself).
;---------------------------------------------------------------------
QINT    TST.B   FAC
        BEQ   QINT_Z
        MOVE.L  FAC,D2          ; V := mantissa << 8 | extension
        ROL.L   #8,D2           ; (M5e: mantissa long assembled
        MOVE.B  FAC+4,D2        ; via even accesses, was FAC+1)
        TST.L   D2
        LSL.L   #8,D2
        OR.B    FACOV,D2
        MOVEQ   #0,D1
        MOVE.B  FAC+1,D1        ; V high word := top mantissa byte
        TST.B   FACSIGN
        BPL   QINT_S
        NOT.L   D2              ; negative: two's complement V
        NOT.L   D1              ; (NOT + 1; NEGX is outside the
        ADDQ.L  #1,D2           ; assembler subset)
        BCC   QINT_S
        ADDQ.L  #1,D1
QINT_S  MOVEQ   #0,D0
        MOVE.B  FAC,D0
        MOVE.W  #160,D3
        SUB.W   D0,D3           ; shift = 160 - exponent
        BMI   QINT_L
        CMPI.W  #40,D3
        BCC   QINT_BIG
        TST.W   D3
        BEQ   QINT_ST
QINT_RL ASR.L   #1,D1           ; arithmetic shift right (64-bit)
        ROXR.L  #1,D2
        SUBQ.W  #1,D3
        BNE   QINT_RL
        BRA   QINT_ST
QINT_L  LSL.L   #1,D2           ; shift left (exponent > 160)
        ROXL.L  #1,D1
        ADDQ.W  #1,D3
        BNE   QINT_L
        BRA   QINT_ST
QINT_BIG TST.L  D1               ; shift >= 40: result is 0 or -1
        BMI   QINT_BN
        MOVEQ   #0,D1
        MOVEQ   #0,D2
        BRA   QINT_ST
QINT_BN MOVEQ   #-1,D1
        MOVEQ   #-1,D2
QINT_ST MOVE.B  D2,FACOV        ; field := V >> shift; integer part
        MOVE.L  D2,D0           ; is field >> 8 -> FAC+1..FAC+4
        LSR.L   #8,D0
        MOVE.L  D1,D3
        LSL.L   #8,D3
        LSL.L   #8,D3
        LSL.L   #8,D3
        OR.L    D3,D0
        MOVE.L  D0,MANTMP       ; M5e: byte-staged store (was
        MOVE.B  MANTMP,FAC+1    ; MOVE.L D0,FAC+1)
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        TST.L   D0
        RTS
QINT_Z  CLR.B   FAC+1
        CLR.B   FAC+2
        CLR.B   FAC+3
        CLR.B   FAC+4
        RTS
INTFN   TST.B   FAC
        BEQ   INT_Z
        CMPI.B  #160,FAC
        BCC   INT_R           ; already integral: INTEGR keeps
                                ; its old value, as in the
                                ; original (INT returns early)
        BSR     QINT
        MOVE.B  FAC+4,INTEGR    ; the two's-complement low byte
        CLR.B   FACOV
        TST.B   FACSIGN
        BPL   INT_P
        MOVE.L  FAC,D0          ; negative: negate the integer
        ROL.L   #8,D0           ; (M5e: mantissa long via even
        MOVE.B  FAC+4,D0        ; accesses, was MOVE.L FAC+1,D0)
        TST.L   D0
        NEG.L   D0
        MOVE.L  D0,MANTMP
        MOVE.B  MANTMP,FAC+1
        MOVE.B  MANTMP+1,FAC+2
        MOVE.B  MANTMP+2,FAC+3
        MOVE.B  MANTMP+3,FAC+4
        TST.L   D0
        MOVE.B  #$FF,FACSIGN
        BRA   INT_N
INT_P   CLR.B   FACSIGN
INT_N   MOVE.B  #160,FAC
        BRA     NORMALIZE
INT_Z   CLR.B   INTEGR          ; INT(0): QINT's CLRFAC path
                                ; still stores FACLO (= 0)
INT_R   RTS
AYINT   CMPI.B  #$90,FAC
        BCS   AY_Q            ; exponent < $90: plain QINT
        BRA     IQERR         ; M5c: the original allows exactly
                                ; -32768 here via an FCOMP against
                                ; its NEG32768 constant -- but that
                                ; constant is stored SHORT (4 bytes
                                ; for a 5-byte FP number), so FCOMP
                                ; reads the byte after it ($20 in
                                ; cbmbasic2) as the last mantissa
                                ; byte and the comparison can never
                                ; be equal: -32768 is rejected too.
                                ; Golden-verified (A%=-32768 and
                                ; (-32768) AND 255 both give ?IQ).
                                ; CONFIG_2C's appended $00 is the
                                ; later bugfix we do NOT have.
AY_Q    BRA     QINT

;---------------------------------------------------------------------
; FIN -- parse the number at TXTPTR into FAC.  Entered with the
; first character already in D0 (CHRGET state).  On exit A6/D0
; hold the character that ended the number.  (FIN.)  The leading
; '-' is applied by the caller (FRM_ELEMENT), matching the
; observable behaviour of the original's SERLEN mechanism.
; ADDACC -- FAC := FAC + digit in D0.B (ADDACC.)
;---------------------------------------------------------------------
;---------------------------------------------------------------------
; R1-M3 literal cache -- FIN wrapper.  A numeric literal in
; program text is re-parsed on every execution (and the parse
; repeatedly divides by 10: M9 measured ~13% of ASCIIART).
; The cache is direct-mapped at LCACHE: {text address (4),
; end address (4), FAC value (6), exit D0 (1), FACTYP (1),
; FACINT (4), pad}.  Only text inside [TXTTAB, VARTAB) is
; cached -- direct-mode lines (input buffer) and string data
; change under the same address, program text cannot (any
; edit goes through STORE, which clears the cache, as does
; NEW via SCRATCH).  The stored exit D0 keeps even VAL of a
; program-text literal exact: VAL plants a NUL terminator
; during its parse, and a hit must return that NUL, not the
; byte the program holds again afterwards.
; R2-M1: entries are 32 bytes x 128 (the same 4KB frame) so
; the entry also carries the D1 integer result (FACTYP/FACINT);
; the hash folds one more address bit to match.
;---------------------------------------------------------------------
FIN     MOVE.L  A6,D1           ; the literal's first byte
        CMP.L   TXTTAB,D1
        BCS     FIN_PARSE
        CMP.L   VARTAB,D1
        BCC     FIN_PARSE
        MOVE.L  D1,D2
        LSR.L   #6,D2
        EOR.L   D1,D2
        ANDI.L  #$7F,D2
        LSL.L   #5,D2
        LEA     LCACHE,A0
        ADDA.L  D2,A0
        CMP.L   (A0),D1
        BEQ     FIN_HIT
        MOVE.L  A0,-(SP)        ; miss: parse, then store
        MOVE.L  D1,-(SP)
        BSR     FIN_PARSE
        MOVE.L  (SP)+,D1
        MOVE.L  (SP)+,A0
        MOVE.L  D1,(A0)
        MOVE.L  A6,4(A0)
        MOVE.B  FAC,8(A0)
        MOVE.B  FAC+1,9(A0)
        MOVE.B  FAC+2,10(A0)
        MOVE.B  FAC+3,11(A0)
        MOVE.B  FAC+4,12(A0)
        MOVE.B  FACOV,13(A0)
        MOVE.B  D0,14(A0)
        MOVE.B  FACTYP,15(A0)   ; R2-M1: the D1 result rides along
        MOVE.L  FACINT,16(A0)
        RTS
FIN_HIT MOVE.B  8(A0),FAC
        MOVE.B  9(A0),FAC+1
        MOVE.B  10(A0),FAC+2
        MOVE.B  11(A0),FAC+3
        MOVE.B  12(A0),FAC+4
        MOVE.B  13(A0),FACOV
        CLR.B   FACSIGN
        MOVE.B  15(A0),FACTYP   ; R2-M1: restore the D1 result
        MOVE.L  16(A0),FACINT
        MOVEA.L 4(A0),A6
        MOVE.B  14(A0),D0
        RTS
LC_CLEAR LEA    LCACHE,A0         ; wipe all 128 entries (4KB)
        MOVE.W  #1023,D0
LCC_L   CLR.L   (A0)+
        SUBQ.W  #1,D0
        BPL     LCC_L
        RTS
FIN_PARSE CLR.B INDEX1          ; fraction digit count
        CLR.B   INDEX2          ; explicit exponent
        CLR.B   EXPSGN
        CLR.B   LOWTR           ; bit7 fraction, bit6 point seen
        CLR.B   FAC
        CLR.B   FAC+1
        CLR.B   FAC+2
        CLR.B   FAC+3
        CLR.B   FAC+4
        CLR.B   FACOV
        CLR.B   FACSIGN
        CLR.L   FININT          ; R2-M1 (D1): parallel int32
        MOVE.B  #1,FINFLG       ; accumulation; still a candidate
        CLR.B   FACTYP
FIN_L   CMPI.B  #$2E,D0         ; '.' ?
        BEQ   FIN_DOT
        CMPI.B  #$30,D0
        BCS   FIN_ND
        CMPI.B  #$39,D0
        BHI   FIN_ND
        TST.B   LOWTR           ; digit: in fraction?
        BPL   FIN_D1
        ADDQ.B  #1,INDEX1
FIN_D1  MOVE.B  D0,D2           ; save the digit (FMUL10's rounding
        BSR     FIN_IDIG        ; R2-M1 (D1): FININT := FININT*10 +
                                ; digit while the literal is still
                                ; an int32 candidate (digit in D2)
        BSR     FMUL10          ; path clobbers D0)
        MOVE.B  D2,D0           ; FAC := FAC*10 + digit
        ANDI.B  #$0F,D0
        BSR     ADDACC
        BSR     CHRGET
        BRA   FIN_L
FIN_DOT CLR.B   FINFLG          ; R2-M1 (D1): a '.' ends the int
                                ; candidacy (the literal is FP)
        MOVE.B  LOWTR,D1
        ANDI.B  #$40,D1
        BNE   FIN_FIN         ; second '.': number ends
        ORI.B   #$C0,LOWTR
        BSR     CHRGET
        BRA   FIN_L
FIN_ND  CMPI.B  #$45,D0         ; 'E' ?
        BNE   FIN_FIN
        CLR.B   FINFLG          ; R2-M1 (D1): an exponent ends the
                                ; int candidacy (the literal is FP)
        BSR     CHRGET
        CMPI.B  #$AB,D0         ; '-' token
        BEQ   FIN_ES
        CMPI.B  #$2D,D0         ; '-' raw
        BEQ   FIN_ES
        CMPI.B  #$AA,D0         ; '+' token
        BEQ   FIN_EP
        CMPI.B  #$2B,D0         ; '+' raw
        BEQ   FIN_EP
        BRA   FIN_ED
FIN_ES  MOVE.B  #$FF,EXPSGN
FIN_EP  BSR     CHRGET
FIN_ED  CMPI.B  #$30,D0         ; exponent digits
        BCS   FIN_FIN
        CMPI.B  #$39,D0
        BHI   FIN_FIN
        MOVE.B  INDEX2,D1       ; EXPON := EXPON*10 + digit
        MOVE.B  D1,D3
        LSL.B   #3,D1
        LSL.B   #1,D3
        ADD.B   D3,D1
        MOVE.B  D0,D2
        ANDI.B  #$0F,D2
        ADD.B   D2,D1
        MOVE.B  D1,INDEX2
        BSR     CHRGET
        BRA   FIN_ED
FIN_FIN MOVEQ   #0,D1           ; scale: total = +/-EXPON - INDX
        MOVE.B  INDEX2,D1
        TST.B   EXPSGN
        BEQ   FIN_F1
        NEG.W   D1
FIN_F1  MOVEQ   #0,D0
        MOVE.B  INDEX1,D0
        SUB.W   D0,D1
        BEQ   FIN_R
        BMI   FIN_NEG
FIN_POS MOVE.W  D1,-(SP)        ; the scale count rides out the
        BSR     FMUL10          ; call on the stack: the FP core
        MOVE.W  (SP)+,D1        ; clobbers every data register
        SUBQ.W  #1,D1
        BNE   FIN_POS
        BRA   FIN_R
FIN_NEG MOVE.W  D1,-(SP)
        BSR     FDIV10
        MOVE.W  (SP)+,D1
        ADDQ.W  #1,D1
        BNE   FIN_NEG
FIN_R   TST.B   FINFLG          ; R2-M1 (D1): the literal stayed a
        BEQ   FIN_RR            ; pure int32 candidate (no '.', no
        MOVE.L  FININT,FACINT   ; exponent, no overflow -- so the
        MOVE.B  #1,FACTYP       ; scale at FIN_FIN was necessarily
FIN_RR  RTS                     ; zero): finish as an INT; the FP
                                ; shadow is already in FAC (exact)
;---------------------------------------------------------------------
; FIN_IDIG -- one digit of FIN's parallel int32 accumulation
; (R2-M1, D1).  Entry: D2.B = the digit character.  While
; FINFLG says the literal is still a candidate, FININT :=
; FININT*10 + digit, with a pre-multiply range check against
; 214748364 (the largest prefix that can still fit: at the
; equal boundary the digit must be <= 7).  Overflow simply
; ends the candidacy -- the FP parse continues untouched and
; the literal finishes as FP, exactly as before R2.
; Clobbers D1, D3 (both dead at the FIN_D1 call site).
;---------------------------------------------------------------------
FIN_IDIG TST.B  FINFLG
        BEQ   FID_R
        CMPI.L  #214748364,FININT
        BHI   FID_NO
        BNE   FID_GO
        MOVE.B  D2,D1           ; prefix == 214748364: digit <= 7
        ANDI.B  #$0F,D1
        CMPI.B  #7,D1
        BHI   FID_NO
FID_GO  MOVE.L  FININT,D1
        MOVE.L  D1,D3
        ADD.L   D1,D1           ; *2
        MOVE.L  D1,D3           ; (keep the *2 for the *10 sum)
        ADD.L   D1,D1           ; *4
        ADD.L   D1,D1           ; *8
        ADD.L   D3,D1           ; *10
        MOVE.B  D2,D3
        ANDI.L  #$0F,D3
        ADD.L   D3,D1
        MOVE.L  D1,FININT
        RTS
FID_NO  CLR.B   FINFLG
FID_R   RTS
ADDACC  MOVE.B  D0,D3           ; save the digit
        BSR     CP_F2AR         ; ARG := FAC (rounded)
        MOVE.B  D3,D0
        BSR     FLOAT_BYTE      ; FAC := digit
        MOVE.B  ARISGN,D0
        MOVE.B  FACSIGN,D1      ; (EOR takes a register source
        EOR.B   D1,D0           ; only: a memory source here was
        MOVE.B  D0,SGNCPR       ; mis-encoded as EOR D0,D0)
        BRA     FADD_CORE

;---------------------------------------------------------------------
; FOUT -- convert FAC to its display string in FBUFF,
; NUL-terminated.  (FOUT.)  As in the original, FACSIGN is
; REPLACED by the sign character (' ' or '-'), which makes FAC
; effectively positive for the rest of the routine.  The digit
; loop uses the original's DECTBL place values (taken unsigned;
; the original's sign-alternating add trick produces the same
; digits).  A3 = write pointer.  Clobbers A0-A3, D0-D7.
;---------------------------------------------------------------------
FOUT    LEA     FBUFF,A3
        MOVE.B  #$20,D0         ; sign char: ' ' or '-'
        TST.B   FACSIGN
        BPL   FOUT_SC
        MOVE.B  #$2D,D0
FOUT_SC MOVE.B  D0,FACSIGN      ; the original stores the char in
        MOVE.B  D0,(A3)+        ; FACSIGN itself
        TST.B   FAC
        BNE   FOUT_NZ
        MOVE.B  #$30,(A3)+      ; zero: sign + '0'
        CLR.B   (A3)
        RTS
FOUT_NZ CLR.B   INDEX1          ; INDX := 0
        MOVE.B  FAC,D0
        CMPI.B  #$80,D0
        BHI   FOUT_S1         ; exponent > $80: no initial scale
        LEA     CON_BILLION(PC),A0 ; exponent <= $80: FAC *= 1E9
        BSR     FMULT_MEM
        MOVE.B  #-9,INDEX1
FOUT_S1                         ; ---- adjust into [1E8, 1E9) ----
FOUT_UP LEA     CON_999999999(PC),A0
        BSR     FCOMP
        TST.B   D0
        BEQ   FOUT_QINT       ; exactly 999999999: no +0.5
        BMI   FOUT_LOW        ; packed > FAC: check lower bound
FOUT_DIVB BSR   FDIV10          ; FAC too big: /= 10, INDX++
        ADDQ.B  #1,INDEX1
        BNE   FOUT_UP
        BRA   FOUT_QH         ; INDX hit 0: accept (safety valve)
FOUT_LOW LEA    CON_99999999_9(PC),A0
        BSR     FCOMP
        TST.B   D0
        BMI   FOUT_MULB       ; packed > FAC: too small
        BEQ   FOUT_MULB       ; equal: also multiply (original)
        BRA   FOUT_QH         ; packed < FAC: in range
FOUT_MULB BSR   FMUL10          ; FAC *= 10, INDX--
        SUBQ.B  #1,INDEX1
        BNE   FOUT_LOW
        BRA   FOUT_DIVB       ; INDX hit 0: into the DIV10 block
FOUT_QH BSR     FADDH           ; in range: add 0.5, then QINT
FOUT_QINT BSR   QINT
        ; ---- classify: D0.W = INDX + 10 ----
        MOVEQ   #0,D0
        MOVE.B  INDEX1,D0
        EXT.W   D0
        ADDI.W  #10,D0
        BMI   FOUT_EX         ; D0 < 0: exponential
        CMPI.W  #11,D0
        BCC   FOUT_EX         ; D0 >= 11: exponential
        SUBQ.W  #1,D0           ; decimal: counter := INDX + 9
        MOVE.B  D0,FOUTIND
        CLR.B   FOUTEXP         ; EXPON := 0
        BRA   FOUT_PRE
FOUT_EX MOVE.B  #1,FOUTIND      ; exponential: counter := 1
        SUBQ.W  #2,D0           ; EXPON := (INDX + 10) - 2
        MOVE.B  D0,FOUTEXP
FOUT_PRE                        ; ---- prefix if counter <= 0 ----
        TST.B   FOUTIND
        BGT   FOUT_DIG
        MOVE.B  #$2E,(A3)+      ; '.'
        TST.B   FOUTIND
        BEQ   FOUT_DIG
        MOVE.B  #$30,(A3)+      ; then '0' (INDX < 0)
FOUT_DIG                        ; ---- nine digits ----
        MOVE.L  FAC,D7          ; the integer from QINT (M5e:
        ROL.L   #8,D7           ; mantissa long via even accesses,
        MOVE.B  FAC+4,D7        ; was MOVE.L FAC+1,D7)
        TST.L   D7
        LEA     DECTBL(PC),A0
        MOVEQ   #9,D6
FOUT_DL MOVE.L  (A0)+,D1        ; place value := |DECTBL entry|
        BPL   FOUT_DP
        NEG.L   D1
FOUT_DP MOVEQ   #$30,D0         ; digit := '0'
FOUT_DC CMP.L   D1,D7
        BCS   FOUT_DW         ; remaining < place: digit done
        SUB.L   D1,D7
        ADDQ.B  #1,D0
        BRA   FOUT_DC
FOUT_DW MOVE.B  D0,(A3)+
        SUBQ.B  #1,FOUTIND      ; point after this digit?
        BNE   FOUT_DN
        MOVE.B  #$2E,(A3)+
FOUT_DN SUBQ.B  #1,D6
        BNE   FOUT_DL
        ; ---- lop trailing zeros and a trailing point ----
FOUT_LP MOVE.B  -1(A3),D0
        CMPI.B  #$30,D0
        BNE   FOUT_LP2
        SUBQ.L  #1,A3
        BRA   FOUT_LP
FOUT_LP2 CMPI.B #$2E,D0
        BNE   FOUT_EXP
        SUBQ.L  #1,A3
FOUT_EXP TST.B  FOUTEXP         ; ---- exponent suffix ----
        BEQ   FOUT_END
        MOVE.B  #$45,(A3)+      ; 'E'
        MOVE.B  #$2B,D0         ; '+'
        TST.B   FOUTEXP
        BPL   FOUT_E1
        MOVE.B  #$2D,D0         ; '-'
        NEG.B   FOUTEXP
FOUT_E1 MOVE.B  D0,(A3)+
        MOVE.B  FOUTEXP,D0      ; two digits, tens first
        MOVEQ   #0,D1
FOUT_E2 CMPI.B  #10,D0
        BCS   FOUT_E3
        SUBI.B  #10,D0
        ADDQ.B  #1,D1
        BRA   FOUT_E2
FOUT_E3 ADDI.B  #$30,D1
        MOVE.B  D1,(A3)+
        ADDI.B  #$30,D0
        MOVE.B  D0,(A3)+
FOUT_END CLR.B  (A3)
        RTS

;---------------------------------------------------------------------
; FOUT_INT -- the D9 integer print conversion (R2-M1): FACINT
; to its display string in FBUFF, NUL-terminated, in exactly
; FOUT's byte format (a leading ' ' for non-negative values,
; '-' for negative ones, then the decimal digits; PRITEM adds
; the NUMSPC trailing byte as usual).  Digits are produced by
; DIV10 (50-machine) least-significant first and stacked, then
; popped into FBUFF.  The magnitude of -2147483648 is
; $80000000, which DIV10 reads unsigned as 2147483648 -- the
; correct digit string.  Clobbers D0-D3, A3.
;---------------------------------------------------------------------
FOUT_INT LEA    FBUFF,A3
        MOVE.B  #$20,D0         ; sign char: ' ' or '-'
        MOVE.L  FACINT,D1
        BPL   FI_SC
        MOVE.B  #$2D,D0
        NEG.L   D1              ; magnitude (unsigned reading)
FI_SC   MOVE.B  D0,(A3)+
        MOVE.L  D1,D0
        MOVEQ   #0,D3           ; digit count
FI_L1   BSR     DIV10           ; D0 = quotient, D1 = digit
        ADDI.B  #$30,D1
        MOVE.B  D1,-(SP)        ; stack the digit (byte push)
        ADDQ.W  #1,D3
        TST.L   D0
        BNE   FI_L1
FI_L2   MOVE.B  (SP)+,D0
        MOVE.B  D0,(A3)+
        SUBQ.W  #1,D3
        BNE   FI_L2
        CLR.B   (A3)
        RTS

;---------------------------------------------------------------------
; PTRGET -- find (or create) the variable named at TXTPTR.
; Entry: D0 = first name character, A6 points at it.
; D5.B <> 0: create the variable if missing (LET/FOR);
; D5.B = 0: no-create (expressions): a missing variable points
; VARPNT at C_ZERO, the original's behaviour.  Sets VARNAM (two
; bytes, second ORed with $80; '$' sets VALTYP, '%' sets INTFLG),
; VARPNT = address of the 6-byte value field (or of the array
; element, for a subscripted name).  Three entries, mirroring
; the original: PTRGET clears DIMFLG; PTRGT1 keeps it (the DIM
; statement sets it first); PTRGT2 keeps VARNAM as preset by
; GETFNM (FN names: the first byte already carries the FN bit).
; (PTRGET/PTRGT1/PTRGT2.)
; ISLETC -- D1.B := 1 if D0 is a letter or digit, else 0.
;---------------------------------------------------------------------
ISLETC  MOVEQ   #0,D1
        CMPI.B  #$30,D0
        BCS   ISL_R
        CMPI.B  #$39,D0
        BLS   ISL_Y
        CMPI.B  #$41,D0
        BCS   ISL_R
        CMPI.B  #$5A,D0
        BHI   ISL_R
ISL_Y   MOVEQ   #1,D1
ISL_R   RTS
;---------------------------------------------------------------------
; R1-M2 variable hash -- a direct-mapped cache over the two
; linear searches (scalars in PTRGET, array blocks in
; PTRGET_ARR).  512 entries x 8 bytes at VHASH: {key (2) = the
; VARNAM word, which already encodes name + type marks, flag
; (1: 0 scalar, 1 array), pad, pointer (4) to the record or
; block}.  A miss or a collision falls back to the original
; walk, which refreshes the entry, so the table can never
; change a result -- only the time to reach it.  Scalar
; records never move; array blocks shift +8 when a scalar is
; created (PT_MAKE), which VH_SHARR mirrors into the table.
; NEW/CLEAR wipe the table (VH_CLEAR hooks in SCRATCH/CLEARC;
; INIT reaches it through SCRATCH).
;---------------------------------------------------------------------
VH_LOOK MOVE.W  VARNAM,D1       ; in: D2.B = flag; out: Z set
        MOVE.W  D1,D0           ; on a hit, A0 = record/block
        LSR.W   #5,D0
        EOR.W   D1,D0
        ANDI.W  #$1FF,D0
        LSL.L   #3,D0
        LEA     VHASH,A0
        ADDA.L  D0,A0
        CMP.W   (A0),D1
        BNE     VH_MISS
        CMP.B   2(A0),D2
        BNE     VH_MISS
        MOVEA.L 4(A0),A0
        MOVEQ   #0,D0           ; Z = 1: hit
        RTS
VH_MISS MOVEQ   #1,D0           ; Z = 0: miss
        RTS
VH_PUT  MOVE.W  VARNAM,D1       ; in: A0 = record/block, D2.B
        MOVE.W  D1,D0           ; = flag; stores the entry
        LSR.W   #5,D0
        EOR.W   D1,D0
        ANDI.W  #$1FF,D0
        LSL.L   #3,D0
        LEA     VHASH,A1
        ADDA.L  D0,A1
        MOVE.W  D1,(A1)
        MOVE.B  D2,2(A1)
        MOVE.L  A0,4(A1)
        RTS
VH_SHARR LEA    VHASH,A1         ; array entries += 8 (called
        MOVE.W  #511,D0         ; from PT_MAKE after its move)
VHS_L   CMPI.B  #1,2(A1)
        BNE     VHS_N
        ADDQ.L  #8,4(A1)
VHS_N   ADDA.L  #8,A1
        SUBQ.W  #1,D0
        BPL     VHS_L
        RTS
VH_CLEAR LEA    VHASH,A0         ; wipe all 512 entries
        MOVE.W  #1023,D0
VHC_L   CLR.L   (A0)+
        SUBQ.W  #1,D0
        BPL     VHC_L
        RTS

PTRGET  CLR.B   DIMFLG
PTRGT1  CLR.B   VALTYP
        CLR.B   INTFLG
        MOVE.B  D0,VARNAM       ; first character
        BRA     PT_1ST
PTRGT2  CLR.B   VALTYP          ; FN name: VARNAM's first byte was
        CLR.B   INTFLG          ; stored by GETFNM (FN bit set)
PT_1ST  BSR     CHRGET
        MOVEQ   #0,D2           ; second character := 0
        BSR     ISLETC
        TST.B   D1
        BEQ   PT_2
        MOVE.B  D0,D2           ; second character
        BSR     CHRGET
PT_SK   BSR     ISLETC          ; further alphanumerics are
        TST.B   D1              ; consumed and ignored
        BEQ   PT_2
        BSR     CHRGET
        BRA   PT_SK
PT_2    CMPI.B  #$24,D0         ; '$' ?
        BNE   PT_3
        MOVE.B  #$FF,VALTYP
        BRA   PT_MK
PT_3    CMPI.B  #$25,D0         ; '%' ?
        BNE   PT_4
        TST.B   SUBFLG          ; M5c: '%' under SUBFLG was the
        BEQ   PT_3OK            ; original's INTERR: FOR I%= and
        CMPI.B  #$80,SUBFLG     ; DEF FN F(A%) are ?SN ERROR
        BNE   SNERR             ; (golden-verified for FOR I%=).
        ; R2-M3 (D4): FORH is the one caller that sets SUBFLG
        ; to $80, and integer FOR is a deliberate deviation --
        ; a % variable is admitted there.  GETFNM and DEFH set
        ; SUBFLG to $FF, so FN names and FN arguments still
        ; reject '%' with ?SN, exactly as before.
PT_3OK  MOVE.B  #$80,INTFLG
        ORI.B   #$80,VARNAM
PT_MK   ORI.B   #$80,D2         ; '$' and '%' names mark the second
        BSR     CHRGET          ; name byte with its high bit; plain
                                ; FP names keep it clear -- exactly
                                ; the original's encoding.  (M1-M4
                                ; set the bit for ALL names, so a FP
                                ; variable and the string variable of
                                ; the same name shared one slot.  The
                                ; collision stayed invisible until
                                ; string variables arrived in M5a,
                                ; and GC's variable scan reads this
                                ; mark to tell string slots apart.)
PT_4    MOVE.B  D2,VARNAM+1
        TST.B   FNPARSE         ; M5c: an FN name (GETFNM): the
        BNE   PT_FNRET          ; parse is all we want; the '('
                                ; that may follow is the call's
                                ; argument parenthesis, not a
                                ; subscript, and no scalar entry
                                ; is made (side table instead)
        CMPI.B  #$28,D0         ; '(' -> array (M5c), unless this
        BNE   PT_SCAL         ; is an FN argument (SUBFLG set)
        TST.B   SUBFLG
        BNE   PT_SCAL
        BRA     PTRGET_ARR
PT_FNRET CLR.B  FNPARSE          ; consume both one-shot flags and
        CLR.B   SUBFLG          ; return to GETFNM
        RTS
PT_SCAL CLR.B   SUBFLG          ; M5c: SUBFLG is one-shot; the
                                ; original clears it on the scalar
                                ; path ("allow subscripts again")
        MOVEQ   #0,D2           ; R1-M2: hash first (flag 0 =
        BSR     VH_LOOK         ; scalar); a hit names the record
        BEQ     PT_FD2          ; in A0, skipping the linear walk
        MOVEA.L VARTAB,A0       ; search the scalar area
PT_FND  CMPA.L  ARYTAB,A0
        BCC   PT_NEW
        MOVE.B  (A0),D0
        CMP.B   VARNAM,D0
        BNE   PT_FNXT
        MOVE.B  1(A0),D0
        CMP.B   VARNAM+1,D0
        BEQ   PT_FD
PT_FNXT ADDA.L  #8,A0
        BRA   PT_FND
PT_FD   MOVEQ   #0,D2           ; R1-M2: remember the walk's find
        BSR     VH_PUT
PT_FD2  LEA     2(A0),A0
        MOVE.L  A0,VARPNT
        RTS
PT_NEW  TST.B   D5
        BNE   PT_MAKE
        LEA     C_ZERO(PC),A0   ; no-create: point at packed zero
        MOVE.L  A0,VARPNT
        RTS
PT_MAKE MOVE.L  STREND,D0       ; room for 8 more bytes?
        ADDQ.L  #8,D0
        CMP.L   FRETOP,D0
        BHI     OMERR
        MOVEA.L STREND,A0       ; move [ARYTAB,STREND) up by 8
PT_BL   CMPA.L  ARYTAB,A0
        BEQ   PT_BD
        SUBQ.L  #1,A0
        MOVE.B  (A0),8(A0)
        BRA   PT_BL
PT_BD   MOVEA.L ARYTAB,A0
        MOVE.B  VARNAM,(A0)
        MOVE.B  VARNAM+1,1(A0)
        CLR.B   2(A0)
        CLR.B   3(A0)
        CLR.B   4(A0)
        CLR.B   5(A0)
        CLR.B   6(A0)
        CLR.B   7(A0)
        LEA     2(A0),A1
        MOVE.L  A1,VARPNT
        ADDQ.L  #8,ARYTAB
        ADDQ.L  #8,STREND
        MOVEQ   #0,D2           ; R1-M2: cache the new record;
        BSR     VH_PUT          ; array blocks just shifted +8,
        BSR     VH_SHARR        ; so mirror that into the table
        RTS

;---------------------------------------------------------------------
; INTIDX -- evaluate one subscript; A6 sits on the '(' or ','
; before it.  Returns the subscript (0..32767) in D0.W; the
; terminator is then re-readable via CHRGOT.  The original's
; INTIDX/POSINT/AYINT chain: CHKNUM (a string subscript is
; ?TM ERROR), a negative value is ?IQ ERROR (the original
; reaches FCERR through AYINT), AYINT range-checks, and QINT
; truncates the fraction (golden: A(3.7) is A(3)).
;---------------------------------------------------------------------
INTIDX  BSR     CHRGET
        BSR     FRMEVL
        BSR     CHKNUM
        TST.B   FACSIGN
        BMI     IQERR
        BSR     AYINT
        MOVE.B  FAC+3,D0        ; M5e: the low word assembled
        LSL.W   #8,D0           ; from bytes (FAC+3 is odd in
        MOVE.B  FAC+4,D0        ; the realigned layout)
        RTS

;---------------------------------------------------------------------
; PTRGET_ARR -- the array half of PTRGET (the original's ISARY).
; Entered from PT_4 with the name in VARNAM, VALTYP/INTFLG set
; and A6 on the '('.  Subscripts are evaluated left to right
; into this invocation's SUBBUF level (ARYDPT picks the level,
; so array references inside subscripts nest).  VARNAM and the
; COUNT/DIMFLG/VALTYP/INTFLG quad are saved on the stack and
; restored after every evaluation: subscript expressions call
; PTRGET recursively and clobber all of them (the original
; saves DIMFLG/VALTYP/VARNAM on its stack for the same reason).
;
;---------------------------------------------------------------------
; MUL32 -- D1.L := D1.L * D0.L (unsigned, low 32 bits of the
; product).  Clobbers D0, D2, D4.  R1: array element counts and
; offsets may exceed 65535 in the A1 space, where MULU.W (which
; reads only the low word of the multiplicand) silently wraps.
; The low 32 bits need only P_ll + (P_hl + P_lh) << 16.
;---------------------------------------------------------------------
MUL32   MOVE.L  D1,D4
        MULU    D0,D4           ; P_ll = a_lo * b_lo
        MOVE.L  D1,D2
        SWAP    D2
        MULU    D0,D2           ; P_hl = a_hi * b_lo
        SWAP    D0
        MULU    D0,D1           ; P_lh = a_lo * b_hi
        ADD.L   D2,D1
        LSL.L   #8,D1
        LSL.L   #8,D1
        ADD.L   D4,D1
        RTS

; Array block layout in [ARYTAB, STREND), the original's
; format with this port's widths: name (2 bytes), total block
; size in bytes (4 -- R1: was 2, which capped one array block
; at 64KB), dimension count (1), one pad byte (M5e: keeps the
; dimension words and the elements even-aligned),
; then per dimension, in declaration order, the size = max
; subscript + 1 (2 bytes each), then the elements, the LAST
; subscript varying
; fastest.  Element sizes: FP 6, string 6 (a descriptor),
; integer 4 (R2-M1: was 2 through R1; int32 now).  A missing
; array is built at STREND: with
; DIMFLG set the sizes come from the subscripts, otherwise
; every dimension defaults to 11 (subscripts 0..10).
;---------------------------------------------------------------------
PTRGET_ARR MOVE.W ARYDPT,-(SP)    ; save the caller's depth
        MOVEQ   #0,D0
        MOVE.W  ARYDPT,D0
        LSL.L   #5,D0           ; *32: this level's SUBBUF block
        LEA     SUBBUF,A0
        ADDA.L  D0,A0
        CLR.B   (A0)            ; ndims := 0
        MOVE.L  A0,-(SP)        ; park the level base in the frame
        ADDQ.W  #1,ARYDPT       ; nested references go one deeper
        MOVE.W  VARNAM,-(SP)
        MOVE.L  COUNT,-(SP)     ; the flag quad
        ; frame from SP: +0 flag quad, +4 VARNAM, +6 level base,
        ; +10 saved ARYDPT
ARR_L   BSR     INTIDX          ; D0.W = the next subscript
        MOVE.L  (SP),COUNT      ; restore the quad and the name,
        MOVE.W  4(SP),VARNAM    ; clobbered by the evaluation
        MOVE.L  6(SP),A3        ; level base
        MOVEQ   #0,D1
        MOVE.B  (A3),D1         ; ndims so far
        ADDQ.B  #1,(A3)         ; ndims += 1
        ADD.L   D1,D1
        MOVE.W  D0,2(A3,D1.L)   ; subscripts[ndims] := value
        BSR     CHRGOT          ; terminator: ',' or ')'
        CMPI.B  #$2C,D0
        BEQ     ARR_L
        BSR     CHKCLS          ; must be ')' (else ?SN ERROR)
        MOVE.L  (SP)+,COUNT     ; unwind the frame: quad, name,
        MOVE.W  (SP)+,VARNAM    ; level base (into A3; the
        MOVE.L  (SP)+,A3        ; subscripts stay live in SUBBUF
        MOVE.B  (A3),COUNT      ; for the index phase), depth
        MOVE.W  (SP)+,ARYDPT
        MOVEQ   #6,D2           ; element size: FP and string
        MOVE.B  VARNAM,D0       ; elements are both 6 bytes in
        BPL   ARR_ES            ; this port; an integer array
        MOVEQ   #4,D2           ; (first name byte marked) is 4
ARR_ES  MOVE.W  D2,ELMSZ        ; (R2-M1, D7: % elements widened
                                ; from 2 to 4 bytes for int32)
        ; ---- search the array table ----
        MOVEQ   #1,D2           ; R1-M2: hash first (flag 1 =
        BSR     VH_LOOK         ; array); a hit names the block
        BNE     ARR_WLK
        MOVE.L  A0,ARYBLK
        BRA     ARR_FND
ARR_WLK MOVEA.L ARYTAB,A0
ARR_SR  CMPA.L  STREND,A0
        BEQ     ARR_BLD
        MOVE.L  A0,ARYBLK
        MOVE.B  (A0),D0
        CMP.B   VARNAM,D0
        BNE     ARR_NX
        MOVE.B  1(A0),D0
        CMP.B   VARNAM+1,D0
        BEQ     ARR_FND
ARR_NX  MOVE.L  2(A0),D0
        ADDA.L  D0,A0
        BRA     ARR_SR
ARR_FND MOVEQ   #1,D2           ; R1-M2: remember the find
        BSR     VH_PUT
        TST.B   DIMFLG
        BNE     DDERR           ; DIM of an existing array: ?DD
        MOVEQ   #0,D0
        MOVE.B  6(A0),D0        ; the array's dimension count
        CMP.B   COUNT,D0
        BNE     BSERR           ; != the given count: ?BS
        BRA     ARR_IDX
        ; ---- build a new block at STREND ----
ARR_BLD MOVEA.L STREND,A0
        MOVE.L  A0,ARYBLK
        MOVE.B  VARNAM,(A0)     ; header: name, ndims, dim sizes
        MOVE.B  VARNAM+1,1(A0)  ; (the size field is filled in
        MOVE.B  COUNT,6(A0)     ; once the total is known; the
        CLR.B   7(A0)           ; header pad (M5e: keeps the dim
        LEA     8(A0),A1        ; bytes sit above STREND, still
        LEA     2(A3),A2        ; invisible, until then)
        MOVEQ   #1,D1           ; element count := 1
        MOVEQ   #0,D3           ; k := 0
ARR_BL  MOVEQ   #0,D0
        MOVE.B  COUNT,D0
        CMP.L   D0,D3
        BCC     ARR_BDN
        MOVEQ   #11,D0          ; default size (subscripts 0..10)
        TST.B   DIMFLG
        BEQ     ARR_BS
        MOVE.W  (A2),D0         ; DIM: size = subscript + 1
        ADDQ.L  #1,D0
ARR_BS  MOVE.W  D0,(A1)+
        ADDQ.L  #2,A2
        BSR     MUL32           ; count *= size (32-bit)
        CMP.L   #$40000,D1
        BHI     OMERR           ; sanity cap: 262144 elements; a
                                ; real block is bounded by the
                                ; FRETOP room check below anyway
        ADDQ.L  #1,D3           ; k += 1
        BRA     ARR_BL
ARR_BDN MOVE.L  D1,D3           ; block size := header + elements
        MOVEQ   #0,D0
        MOVE.W  ELMSZ,D0
        MOVE.L  D3,D1
        BSR     MUL32           ; * element size (32-bit)
        MOVE.L  D1,D3
        MOVEQ   #0,D0
        MOVE.B  COUNT,D0
        ADD.L   D0,D0
        ADDQ.L  #8,D0
        ADD.L   D0,D3
        MOVE.L  STREND,D0       ; room?  (the original's REASON:
        ADD.L   D3,D0           ; collect once, then ?OM ERROR)
        CMP.L   FRETOP,D0
        BLS     ARR_RM
        BSR     GARBAG
        MOVE.L  STREND,D0
        ADD.L   D3,D0
        CMP.L   FRETOP,D0
        BHI     OMERR
ARR_RM  MOVEA.L ARYBLK,A0       ; zero the element area
        MOVEQ   #0,D0
        MOVE.B  COUNT,D0
        ADD.L   D0,D0
        ADDQ.L  #8,D0
        ADDA.L  D0,A0
        MOVE.L  D3,D1
        SUB.L   D0,D1           ; element bytes = size - header
ARR_ZL  SUBQ.L  #1,D1
        BCS     ARR_ZD
        CLR.B   (A0)+
        BRA     ARR_ZL
ARR_ZD  MOVEA.L ARYBLK,A0
        MOVE.L  D3,2(A0)        ; the size field (R1: 4 bytes;
                                ; a block may exceed 64KB now)
        MOVEQ   #1,D2           ; R1-M2: cache the new block
        BSR     VH_PUT
        ADD.L   D3,STREND
        TST.B   DIMFLG
        BNE     ARR_DRTS        ; DIM: done (VARPNT unused by
        MOVEA.L ARYBLK,A0       ; DIMH; point it at the elements)
        BRA     ARR_IDX         ; access: index into the new array
ARR_DRTS MOVE.L A0,D0
        MOVEQ   #0,D1
        MOVE.B  COUNT,D1
        ADD.L   D1,D1
        ADDQ.L  #8,D1
        ADD.L   D1,D0
        MOVE.L  D0,VARPNT
        RTS
        ; ---- index into the block at ARYBLK ----
ARR_IDX LEA     8(A0),A1        ; dimension sizes (A0 = the block,
        LEA     2(A3),A2        ; set by the search or the build)
        MOVEQ   #0,D1           ; subscripts
        MOVEQ   #0,D3           ; offset := 0, k := 0
ARR_IL  MOVEQ   #0,D0
        MOVE.B  COUNT,D0
        CMP.L   D0,D3
        BCC     ARR_IDN
        MOVE.W  (A1)+,D2        ; dimension size
        MOVE.W  (A2)+,D0        ; subscript
        CMP.W   D2,D0
        BCC     BSERR           ; subscript out of range: ?BS
        MOVE.L  D0,-(SP)        ; offset := offset * size + sub
        MOVE.L  D2,D0           ; (32-bit: the offset may exceed
        BSR     MUL32           ; 65535 elements in the A1 space)
        MOVE.L  (SP)+,D0
        ADD.L   D0,D1
        ADDQ.L  #1,D3
        BRA     ARR_IL
ARR_IDN MOVEQ   #0,D0
        MOVE.W  ELMSZ,D0
        BSR     MUL32           ; * element size (32-bit)
        MOVE.L  ARYBLK,D0
        ADD.L   D1,D0
        MOVEQ   #0,D1
        MOVE.B  COUNT,D1
        ADD.L   D1,D1
        ADDQ.L  #8,D1           ; + header size
        ADD.L   D1,D0
        MOVE.L  D0,VARPNT
        RTS

;---------------------------------------------------------------------
; DIM -- DIMH: for each item, DIMFLG set and PTRGT1; items are
; separated by commas (the original's DIMCON loop).  A bare
; name (no parentheses) creates a scalar, as in the original.
;---------------------------------------------------------------------
DIMH    MOVE.B  #$FF,DIMFLG
        MOVEQ   #1,D5           ; create mode (scalars too)
        BSR     PTRGT1
        BSR     CHRGOT          ; terminator?
        BEQ     DIM_R           ; NUL or ':': done
        MOVE.B  #$2C,D0         ; a comma must separate items
        BSR     SYNCHR
        BRA     DIMH
DIM_R   RTS

;---------------------------------------------------------------------
; GETFNM -- parse the FN name at TXTPTR (D0 = its first letter,
; A6 on it) and point DEFPNT at its definition record, making
; a zeroed record if none exists.  Ends in CHKNUM: a string
; FN name is ?TM ERROR (the original's header note: "NO
; STRINGS CAN BE INVOLVED WITH THESE FUNCTIONS").  A record
; is {text pointer (4), argument VARPNT (4)} preceded by the
; 2 name bytes, 12 bytes in all, in the table at FNTABV.
; The original keeps the record in a pseudo-variable's value
; area in the scalar table (its pointers are 2 bytes, so the
; record fits a value area exactly); this port's pointers
; are 4 bytes and the record needs 8, so a side table is
; used.  FN names therefore never enter the scalar area;
; the observable behaviour (a separate namespace, wiped by
; NEW and CLR) is the original's.
;---------------------------------------------------------------------
GETFNM  CMPI.B  #$41,D0
        BCS     SNERR
        CMPI.B  #$5A,D0
        BHI     SNERR
        ORI.B   #$80,D0         ; the FN bit on the first byte
        MOVE.B  D0,VARNAM
        MOVE.B  #$FF,SUBFLG     ; no subscripts, no '%'
        MOVE.B  #$FF,FNPARSE    ; parse only; no scalar entry
        BSR     PTRGT2
        MOVEA.L #FNTABV,A0      ; search the definition table
GF_L    CMPA.L  FNTOP,A0
        BCC     GF_NEW
        MOVE.B  (A0),D0
        CMP.B   VARNAM,D0
        BNE     GF_NX
        MOVE.B  1(A0),D0
        CMP.B   VARNAM+1,D0
        BEQ     GF_FD
GF_NX   ADDA.L  #12,A0
        BRA     GF_L
GF_NEW  MOVE.L  FNTOP,D0
        ADD.L   #12,D0
        CMP.L   #FNTABV+$300,D0 ; 64 records: a full table is ?OM
        BHI     OMERR
        MOVEA.L FNTOP,A0
        MOVE.B  VARNAM,(A0)
        MOVE.B  VARNAM+1,1(A0)
        CLR.L   2(A0)           ; text pointer := 0 (undefined)
        CLR.L   6(A0)           ; argument VARPNT := 0
        CLR.W   10(A0)
        MOVE.L  D0,FNTOP
GF_FD   LEA     2(A0),A0
        MOVE.L  A0,DEFPNT
        BRA     CHKNUM

;---------------------------------------------------------------------
; DEF -- DEFH: DEF FN name(arg) = expression.  Records the
; definition (text pointer at the '=', argument VARPNT) and
; skips the body like a DATA statement; the body is evaluated
; afresh at every call.  Direct mode is ?ID ERROR (ERRDIR,
; checked after GETFNM, as in the original).
;---------------------------------------------------------------------
DEFH    BSR     CHRGET          ; step past the FN token
        BSR     GETFNM          ; DEFPNT -> record (CHKNUM inside)
        BSR     ERRDIR          ; DEF in direct mode: ?ID ERROR
        BSR     CHKOPN
        MOVE.B  #$FF,SUBFLG     ; the argument may not be an
        MOVEQ   #1,D5           ; array (nor an integer: PTRGET's
        BSR     PTRGET          ; SUBFLG check) -- create if new
        BSR     CHKNUM          ; the argument must be numeric
        BSR     CHKCLS
        MOVE.B  #$B2,D0         ; '=' token
        BSR     SYNCHR          ; A6 now sits on the body's first
        MOVEA.L DEFPNT,A0       ; character, which is exactly the
        MOVE.L  A6,(A0)         ; pointer the record wants: the
                                ; original stores TXTPTR at the
                                ; '=' (its convention: TXTPTR names
                                ; the last char read, and a call
                                ; CHRGETs into the body), while
                                ; this port's FRMEVL is entered with
                                ; A6 primed on the first character
                                ; (it backs up one byte itself)
        MOVE.L  VARPNT,4(A0)
        BRA     DATAN           ; skip the body; RTS via DATAN

;---------------------------------------------------------------------
; FN call -- FE_FN (the original's FNDOER): evaluate the
; argument, install it in the definition's argument variable
; (saving that variable's old value on the stack), evaluate
; the definition body with TXTPTR swapped, then restore both.
; A record with no argument pointer was never DEFined:
; ?UF ERROR.  The mechanism is the original's, so nested
; calls (including a body that calls another FN whose
; argument has the same name) restore correctly.
; PARCHK -- '(' expression ')' into FAC.
;---------------------------------------------------------------------
PARCHK  BSR     CHKOPN
        BSR     FRMEVL
        BRA     CHKCLS
FE_FN   BSR     CHRGET          ; step past the FN token
        BSR     GETFNM          ; DEFPNT -> record (CHKNUM inside)
        MOVE.L  DEFPNT,-(SP)    ; the argument may itself call FN
        BSR     PARCHK          ; argument value -> FAC
        BSR     CHKNUM
        MOVE.L  (SP)+,DEFPNT
        MOVEA.L DEFPNT,A0
        MOVE.L  4(A0),D0        ; the argument variable's VARPNT
        BEQ     UFERR           ; zero: never DEFined
        MOVE.L  D0,VARPNT
        MOVEA.L D0,A0           ; save the variable's 5 value
        MOVE.B  4(A0),-(SP)     ; bytes on the stack (byte pushes
        MOVE.B  3(A0),-(SP)     ; keep the stack even on the
        MOVE.B  2(A0),-(SP)     ; 68000, as in PSH_FAC5)
        MOVE.B  1(A0),-(SP)
        MOVE.B  (A0),-(SP)
        MOVEA.L VARPNT,A0
        BSR     ST_FAC          ; argument value -> the variable
        MOVE.L  A6,-(SP)        ; the caller's TXTPTR
        MOVEA.L DEFPNT,A0
        MOVEA.L (A0),A6         ; TXTPTR := the body's first
                                ; character (FRMEVL's primed entry)
        MOVE.L  VARPNT,-(SP)    ; the restore target rides the
        BSR     FRMNUM          ; stack across the body (the
        MOVE.L  (SP)+,DEFPNT    ; original's DEFPNT hand-off)
        BSR     CHRGOT          ; the body must end at a
        BNE     SNERR           ; terminator
        MOVE.L  (SP)+,A6        ; the caller's TXTPTR back
        MOVEA.L DEFPNT,A0       ; restore the argument's value
        MOVE.B  (SP)+,(A0)
        MOVE.B  (SP)+,1(A0)
        MOVE.B  (SP)+,2(A0)
        MOVE.B  (SP)+,3(A0)
        MOVE.B  (SP)+,4(A0)
        RTS

; FRM_VARIABLE -- a variable as an expression element.
; (FRM_VARIABLE.)  Strings load the descriptor address into
; FAC+4..FAC+7; integers load as INT (R2-M1: FACINT + the FP
; shadow via SFLOAT32); FP loads FAC, honouring the R2-M1 int
; tag (D5) when the record carries one.
FRM_VARIABLE MOVEQ #0,D5
        BSR     PTRGET
        TST.B   VALTYP
        BMI   FV_STR
        TST.B   INTFLG
        BMI   FV_INT
        MOVEA.L VARPNT,A0
        BSR     LD_FAC
        CLR.B   FACTYP          ; plain FP load: FP unless tagged
        MOVE.L  VARPNT,D0       ; the tag byte lives at value+5 --
        CMP.L   VARTAB,D0       ; but the no-create C_ZERO constant
        BCS   FV_R              ; is only 5 bytes long, so slots
        MOVEA.L VARPNT,A0       ; below VARTAB never consult it
        CMPI.B  #INTTAG,5(A0)
        BNE   FV_R
        BRA     FAC32I          ; validate + restore FACINT (D5)
FV_INT  MOVEA.L VARPNT,A0       ; R2-M1 (D5/D7): % values are int32
        MOVE.L  (A0),D0         ; now: load the long, keep it as
        BRA     SFLOAT32        ; FACINT, and float the shadow
FV_STR  MOVE.L  VARPNT,FAC+4
        CLR.B   FACTYP          ; R2-M1: a string result is not INT
FV_R    RTS

;---------------------------------------------------------------------
; Type checks and character matching.
; CHKNUM: VALTYP must be numeric.  CHKSTR: string.  CHKVAL:
; D0.B <> 0 expects a string, = 0 expects numeric (else ?TM ERROR).
; SYNCHR: the current character (CHRGOT) must equal D0.B, then
; advance.  CHKOPN / CHKCLS match '(' and ')'.
;---------------------------------------------------------------------
CHKNUM  TST.B   VALTYP
        BMI     TMERR
        RTS
CHKSTR  TST.B   VALTYP
        BPL     TMERR
        RTS
CHKVAL  TST.B   D0
        BNE   CHKV_S
        TST.B   VALTYP
        BMI     TMERR
        RTS
CHKV_S  TST.B   VALTYP
        BPL     TMERR
        RTS
SYNCHR  MOVE.B  D0,D2
        BSR     CHRGOT
        CMP.B   D2,D0
        BNE     SNERR
        BRA     CHRGET
CHKOPN  MOVE.B  #$28,D0
        BRA     SYNCHR
CHKCLS  MOVE.B  #$29,D0
        BRA     SYNCHR
FRMNUM  BSR     FRMEVL          ; evaluate + require numeric
        BRA     CHKNUM

;---------------------------------------------------------------------
; PERFORM2 -- pop one evaluator frame and run its performer.
; The frame (pushed by EV_RECURSE) is, top first: precedence
; (already popped by the caller), mask word, the stacked
; operand's FACTYP word and FACINT long (R2-M2 frame extension,
; restored into ARGTYP/ARGINT), FAC exponent and mantissa
; bytes, FACSIGN, performer address.  The popped value becomes
; ARG (extension byte lost, exactly as the original's 5-byte
; stack frame loses it); SGNCPR is recomputed.
;---------------------------------------------------------------------
PERFORM2 MOVEA.L (SP)+,A1       ; save my return address (it sits
        MOVE.W  (SP)+,D6        ; on top of the frame); the frame
                                ; pops follow: mask slot first.
                                ; The popped mask goes to CPRMASK
                                ; ONLY -- the original pops it into
                                ; CPRMASK and never touches CPRTYP,
                                ; which holds the PENDING operator's
                                ; mask while EV_PRECTEST performs
                                ; tighter stacked ops.  An earlier
                                ; port version also stored it to
                                ; CPRTYP here, which clobbered the
                                ; pending relation's mask whenever a
                                ; unary minus or ^ was performed at
                                ; the relation scan (-1<1, 2^3<9 all
                                ; came out false).
        LSR.W   #1,D6           ; carry := string flag (test it
        BCS   PF2_S             ; BEFORE any MOVE clears C)
        CLR.B   CPRSTR
        BRA   PF2_F
PF2_S   MOVE.B  #1,CPRSTR
PF2_F   MOVE.B  D6,CPRMASK
        MOVE.W  (SP)+,D0        ; R2-M2: the stacked operand's type
        MOVE.B  D0,ARGTYP       ; tag (pushed as a word) and its
        MOVE.L  (SP)+,ARGINT    ; int32 value (frame extension)
        MOVE.B  (SP)+,ARG+4     ; R2-M5: EV_RECURSE now pushes the
        MOVE.L  (SP)+,ARG       ; 5 FAC bytes as long + byte (byte
        CLR.B   ARGEXT          ; lowest on the stack): pop the byte
                                ; first, then the long into ARG..ARG+3
        MOVE.L  (SP)+,ARGDSC    ; M5a: the stacked operand's string
                                ; descriptor address (see EV_RECURSE)
        MOVE.B  (SP)+,ARISGN
        MOVE.B  ARISGN,D0
        MOVE.B  FACSIGN,D1      ; (EOR takes a register source
        EOR.B   D1,D0           ; only: a memory source here was
        MOVE.B  D0,SGNCPR       ; mis-encoded as EOR D0,D0)
        MOVEA.L (SP)+,A0        ; performer address
        MOVE.L  A1,-(SP)        ; restore the return address
        JSR     (A0)
        RTS                     ; R2-M2: no blanket FACTYP clear
                                ; here any more -- each performer
                                ; leaves FACTYP correct for its own
                                ; result (the integer wrappers set
                                ; INT via SFLOAT32; every FP path
                                ; clears it, at the core's head or
                                ; through GIVAYF/FLOAT_BYTE)

;---------------------------------------------------------------------
; FRMEVL -- the formula evaluator.  (FRMEVL/FRMEVL1/FRMEVL2.)
; Entered with A6 one byte before the expression's first
; character.  One routine with the original's state machine:
; element -> operator scan -> precedence test -> perform or
; recurse.  Register use: D3 relational mask, D4 operator index,
; D5 popped precedence.  Operator indices 0..9 follow MATHTBL:
; + - * / ^ AND OR, 7 = unary NEGOP, 8 = NOT (EQUOP), 9 = RELOPS.
; R2-M3 adds 10 = \ (IDIVTK) and 11 = MOD (MODTK), whose tokens
; live outside the $AA..$B0 block and are recognised explicitly
; in EV_OPDEC.
;---------------------------------------------------------------------
FRMEVL  SUBQ.L  #1,A6           ; back up one byte (original)
        CLR.B   CPRTYP
        MOVE.W  #0,-(SP)        ; outermost precedence slot
EV_EL   BSR     FRM_ELEMENT
EV_OP   BSR     CHRGOT
        MOVEQ   #0,D3           ; relational operator scan
EV_REL  CMPI.B  #$B3,D0         ; '<' token
        BEQ   EV_RL
        CMPI.B  #$B2,D0         ; '=' token
        BEQ   EV_RE
        CMPI.B  #$B1,D0         ; '>' token
        BEQ   EV_RG
        BRA   EV_OPDEC
EV_RL   MOVE.B  D3,D1
        ANDI.B  #4,D1
        BNE     SNERR           ; same relational twice
        ORI.B   #4,D3
        BSR     CHRGET
        BRA   EV_REL
EV_RE   MOVE.B  D3,D1
        ANDI.B  #2,D1
        BNE     SNERR
        ORI.B   #2,D3
        BSR     CHRGET
        BRA   EV_REL
EV_RG   MOVE.B  D3,D1
        ANDI.B  #1,D1
        BNE     SNERR
        ORI.B   #1,D3
        BSR     CHRGET
        BRA   EV_REL
EV_OPDEC TST.B  D3
        BNE   EV_RELGO
        CMPI.B  #MODTK,D0       ; R2-M3: MOD (its token sits outside
        BEQ   EV_MOD            ; the $AA..$B0 operator block)
        CMPI.B  #IDIVTK,D0      ; R2-M3: \ integer division
        BEQ   EV_IDIV
        CMPI.B  #$AA,D0         ; + - * / ^ AND OR are $AA..$B0
        BCS     EV_END
        CMPI.B  #$B0,D0
        BHI     EV_END
        MOVEQ   #0,D4
        MOVE.B  D0,D4
        SUBI.W  #$AA,D4         ; operator index 0..6
        TST.W   D4
        BNE   EV_OP2
        TST.B   VALTYP          ; '+' on a string is CAT (M5a): the
        BMI     CAT             ; original leaves the precedence
        BRA   EV_PRECTEST       ; machinery for it entirely
EV_OP2  TST.B   VALTYP          ; any other operator on a string is
        BMI     TMERR           ; ?TM ERROR (the original reaches it
        BRA   EV_PRECTEST       ; through CHKNUM at this point)
EV_MOD  MOVEQ   #11,D4          ; R2-M3: MOD is operator index 11
        BRA     EV_OP2
EV_IDIV MOVEQ   #10,D4          ; R2-M3: \ is operator index 10
        BRA     EV_OP2
EV_RELGO SUBQ.L #1,A6          ; the relational scan already read
        MOVE.B  D3,CPRMASK      ; the right operand's first char
        MOVE.B  D3,D1           ; (CHRGET per operator char), so
        LSL.B   #1,D1           ; back TXTPTR up one byte: the
        CLR.B   CPRSTR          ; element reader's CHRGET must land
        TST.B   VALTYP          ; on it, as on the arithmetic path
        BPL   EV_RG2
        ORI.B   #1,D1
        MOVE.B  #1,CPRSTR
EV_RG2  MOVE.B  D1,CPRTYP
        MOVEQ   #9,D4
EV_PRECTEST MOVE.W (SP)+,D5   ; popped precedence vs the new op's
        LEA     MATPREC(PC),A0
        MOVEQ   #0,D1
        MOVE.B  0(A0,D4.W),D1
        CMP.W   D1,D5
        BCC   EV_PERF1        ; stacked op binds tighter/equal
        MOVE.W  D5,-(SP)        ; push it back and recurse
        BRA     EV_RECURSE
EV_PERF1 MOVE.B D4,LASTOP
        CMPI.W  #$64,D5         ; stacked op is RELOPS: strings OK
        BEQ   EV_PERF2
        BSR     CHKNUM
EV_PERF2 BSR    PERFORM2
        MOVE.W  (SP)+,D5        ; precedence below the frame
        MOVEQ   #0,D1
        MOVE.B  LASTOP,D1
        LEA     MATPREC(PC),A0
        MOVE.B  0(A0,D1.W),D1
        ANDI.W  #$00FF,D1
        CMP.W   D1,D5
        BCC   EV_PERF2        ; still binds: perform again
        MOVE.W  D5,-(SP)        ; push back, recurse with LASTOP
        MOVEQ   #0,D4
        MOVE.B  LASTOP,D4
        BRA   EV_RECURSE
EV_END  MOVE.W  (SP)+,D5        ; end of expression: drain or exit
        TST.W   D5
        BEQ   EV_EXIT
        MOVE.B  #$FF,LASTOP
        CMPI.W  #$64,D5
        BEQ   EV_DR2
        BSR     CHKNUM
EV_DR2  BSR     PERFORM2
        BRA   EV_END
EV_EXIT RTS
EV_RECURSE LEA    MATPERF(PC),A0 ; push a frame and go one level
        MOVE.W  D4,D1           ; deeper: performer, sign, FAC
        LSL.W   #2,D1           ; (rounded), mask, precedence
        MOVE.L  0(A0,D1.W),-(SP)
        MOVE.B  FACSIGN,-(SP)
        MOVE.L  FAC+4,-(SP)     ; M5a: the full descriptor-address
                                ; long, for a stacked string operand
                                ; (RELOPS reads it back as ARGDSC;
                                ; the 5-byte FAC save below carries
                                ; only its lowest byte).  Numeric
                                ; performers ignore it.
        TST.B   VALTYP          ; a string "FAC" is a descriptor
        BMI   EV_RSK            ; address in FAC+4..7: rounding would
        BSR     ROUND_FAC       ; shift and increment those bytes
EV_RSK  MOVE.L  FAC,-(SP)        ; R2-M5: the 5-byte FAC save is a
        MOVE.B  FAC+4,-(SP)     ; long + a byte (was 5 byte pushes).
                                ; The pair order flips with PERFORM2's
                                ; pops (byte first there): the frame
                                ; bytes on the stack are FAC+4 below
                                ; FAC..FAC+3 -- same 5 bytes, same
                                ; total size, and the long push/pop
                                ; land on the same even addresses the
                                ; old sequence's parity produces.
        MOVE.L  FACINT,-(SP)    ; R2-M2: the stacked operand's
        MOVEQ   #0,D6           ; int32 value and type tag ride
        MOVE.B  FACTYP,D6       ; the frame (PERFORM2 restores
        MOVE.W  D6,-(SP)        ; them into ARGINT/ARGTYP); the
                                ; long+word pair keeps the stack
                                ; even from this point of the push
                                ; sequence on (and in the pops)
        MOVEQ   #0,D6
        MOVE.B  CPRTYP,D6
        MOVE.W  D6,-(SP)
        LEA     MATPREC(PC),A0
        MOVEQ   #0,D1
        MOVE.B  0(A0,D4.W),D1
        MOVE.W  D1,-(SP)
        CLR.B   CPRTYP
        BRA     EV_EL

;---------------------------------------------------------------------
; FRM_ELEMENT -- one expression element into FAC/VALTYP.
; (FRM_ELEMENT.)  Numbers go to FIN (a leading '-' reaches here
; only via the EQUL unary path below; FIN itself handles the
; exponent sign).  String literals build a descriptor at TEMPST
; (full string machinery is M4).  Unary '-' and NOT hijack the
; level continuation exactly as the original's EQUL does: the
; return address is dropped and EV_RECURSE runs with the unary
; operator index.
;---------------------------------------------------------------------
FRM_ELEMENT CLR.B VALTYP
        BSR     CHRGET
        CMPI.B  #$2E,D0         ; '.' starts a number
        BEQ   FE_NUM
        CMPI.B  #$30,D0
        BCS   FE_N1
        CMPI.B  #$39,D0
        BHI   FE_N1
FE_NUM  BSR     FIN             ; digit: parse the number
        RTS
FE_N1   CMPI.B  #$22,D0         ; '"' string literal
        BEQ   FE_STR
        CMPI.B  #$AB,D0         ; MINUS token: unary (EQUL)
        BEQ   FE_MINUS
        CMPI.B  #$A8,D0         ; NOT token (EQUL)
        BEQ   FE_NOT
        CMPI.B  #$28,D0         ; '(' subexpression (PARCHK)
        BEQ   FE_PAREN
        CMPI.B  #$A5,D0         ; FN token (M5c)
        BEQ   FE_FN
        CMPI.B  #$B4,D0
        BCS   FE_VAR          ; below SGN: must be a variable
        BRA   FE_UNARY        ; function tokens
FE_MINUS ADDQ.L #4,SP           ; drop FRM_ELEMENT's return (EQUL)
        MOVEQ   #7,D4           ; NEGOP index
        BRA     EV_RECURSE
FE_NOT  ADDQ.L  #4,SP
        MOVEQ   #8,D4           ; EQUOP index
        BRA     EV_RECURSE
FE_PAREN BSR    CHKOPN
        BSR     FRMEVL
        BSR     CHKCLS
        RTS
