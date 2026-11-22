PRTAB   MOVE.B  D0,-(SP)        ; save the TAB( / SPC( token
        BSR     GTBYTC          ; D2.B = count, D0 = char after ')'
        MOVE.B  (SP)+,D1        ; D1.B = token again
        MOVE.W  #1,(SP)         ; (the PRINT state word is below)
        CMPI.B  #$A6,D1         ; SPC( : count is absolute
        BEQ   PRTCNT          ; SPC: D2 = count already
        MOVE.B  POSX,D1         ; TAB( : spaces = count - POSX
        CMP.B   D1,D2
        BCS   PRTNXT          ; count < POSX: nothing
        SUB.B   D1,D2
        ; fall through into PRTCNT (see PRSG2's note on BRA)
PRTCNT  TST.B   D2
        BEQ   PRTNXT
PRT1    BSR     OUTSP           ; print first, then count down:
        SUBQ.B  #1,D2           ; exactly D2 spaces (same M3
        BNE   PRT1              ; off-by-one as PRZONE's loop)
PRTNXT  BSR     CHRGOT          ; re-read the current char: D0 held
        TST.B   D0              ; it on entry, but the OUTSP space
        BEQ   PRTERM            ; loop above rewrites D0, so a bare
        CMPI.B  #$3A,D0         ; TAB(n)/SPC(n) at the end of a
        BEQ   PRTERM            ; statement used to fall into a
        BRA     PRITEM          ; phantom FRMEVL (latent M4 bug,
                                ; invisible while every TAB/SPC test
                                ; had an item after it)

; GTBYTC -- evaluate "(byte)" at TXTPTR: CHRGET past the token's
; '(', a numeric expression, a byte conversion (GETBYTE), then
; require ')' and advance past it.  Out: D2.B = the byte, D0.B =
; current char after ')'.
GTBYTC  BSR     CHRGET          ; first char of the expression
        BSR     FRMNUM
        BSR     GETBYTE         ; D2.B = byte value; CHRGOT refresh
        CMPI.B  #$29,D0         ; ')'
        BNE     SNERR
        BRA     CHRGET          ; advance; D0 = next char; RTS via it

; GETBYTE -- convert FAC to a byte in D2.B (the original's CONINT:
; the integer must satisfy 0 <= v <= 255, else ?IQ ERROR).
; Leaves D0.B = CHRGOT's current char.  M5d: the sign is tested
; first (the original's POSINT step): without it, a value in
; (-1,0) slipped through QINT as 0 -- CHR$(-0.5) included.
GETBYTE BSR     CHKNUM          ; CONINT checks the type first
        TST.B   FACSIGN
        BMI     GBERR
        BSR     QINT
        TST.B   FAC+1
        BNE   GBERR
        TST.B   FAC+2
        BNE   GBERR
        TST.B   FAC+3
        BNE   GBERR
        MOVE.B  FAC+4,D2
        BRA     CHRGOT
GBERR   BRA     IQERR

; PRWIDTH -- the original PRINT's wrap check, simplified: if the
; FOUT string would cross column 80, CRDO first.
PRWIDTH MOVEQ   #0,D1
        LEA     FBUFF,A0
PRW1    TST.B   (A0)+
        BEQ   PRW2
        ADDQ.W  #1,D1
        BRA   PRW1
PRW2    MOVEQ   #0,D0
        MOVE.B  POSX,D0
        ADD.W   D1,D0
        CMPI.W  #80,D0
        BCS   PRWRTS
        BSR     CRDO
PRWRTS  RTS

;---------------------------------------------------------------------
; LIST -- list the program (or a line / range) with detokenization.
;   LIST            all lines
;   LIST n          just line n
;   LIST n- / n-m   from n (to m)
;   LIST -m         up to m
; (The original parses exactly this shape through LINGET/FNDLIN.)
; LIST always ends back at READY, as in the original.
;---------------------------------------------------------------------
LISTH   MOVEQ   #0,D6           ; start line = 0
        MOVE.L  #$0000FFFF,D7   ; end line = 65535
        TST.B   D0
        BEQ   LSTGO
        CMPI.B  #$3A,D0
        BEQ   LSTGO
        CMPI.B  #MINUTK,D0      ; '-' first?
        BEQ   LSTDASH
        CMPI.B  #$30,D0
        BCS     SNERR
        CMPI.B  #$39,D0
        BHI     SNERR
        BSR     LINGET          ; start = LINNUM
        MOVE.W  LINNUM,D6
        MOVE.W  LINNUM,D7       ; end = start unless a dash follows
        CMPI.B  #MINUTK,D0
        BNE   LSTTERM
LSTDASH BSR     CHRGET          ; char after '-'
        CMPI.B  #$30,D0
        BCS   LSTTERM         ; no number: end stays as preset
        CMPI.B  #$39,D0
        BHI   LSTTERM
        BSR     LINGET          ; end = LINNUM
        MOVE.W  LINNUM,D7
LSTTERM TST.B   D0              ; must be at a terminator now
        BEQ   LSTGO
        CMPI.B  #$3A,D0
        BNE     SNERR
LSTGO   MOVEA.L TXTTAB,A0
LSTLP   TST.L   (A0)
        BEQ   LSTDONE         ; end marker
        MOVEQ   #0,D1
        MOVE.W  4(A0),D1        ; this line's number
        CMP.L   D6,D1
        BCS   LSTNXT          ; below the range: skip
        CMP.L   D7,D1
        BHI   LSTDONE         ; past the range: done (sorted)
        BSR     CRDO
        MOVE.L  D1,D0
        BSR     PRTDEC          ; line number, no leading space
        MOVE.B  #$20,D0
        BSR     MONCOUT         ; one space (the original does this)
        LEA     6(A0),A1
        BSR     LSTTXT          ; detokenized text
LSTNXT  MOVEA.L (A0),A0
        BRA   LSTLP
LSTDONE ADDQ.L  #4,SP           ; drop the FETCH return address
        BRA     READY

; LSTTXT -- print the tokenized text at (A1) up to its NUL,
; expanding tokens back to keywords via RESLST.  Inside quotes,
; bytes are printed raw (CRUNCH never tokenizes there anyway).
; D5 = quote flag.  Clobbers A1, A2, D0, D3, D4, D5.
LSTTXT  MOVEQ   #0,D5
LTX1    MOVE.B  (A1)+,D0
        BEQ   LTXRTS
        TST.B   D5
        BNE   LTXQ            ; inside quotes: raw
        CMPI.B  #$80,D0
        BCC   LTXTOK          ; a token: expand it
        BSR     MONCOUT
        CMPI.B  #$22,D0
        BNE   LTX1
        MOVEQ   #1,D5           ; opening quote
        BRA   LTX1
LTXQ    BSR     MONCOUT
        CMPI.B  #$22,D0
        BNE   LTX1
        MOVEQ   #0,D5           ; closing quote
        BRA   LTX1
LTXTOK  MOVE.B  D0,D4
        BSR     LSTKW
        BRA   LTX1
LTXRTS  RTS

; LSTKW -- print the keyword whose token is in D4.B, by walking
; RESLST to the (token-$80)-th entry and typing it with the last
; character's high bit stripped.
LSTKW   LEA     RESLST(PC),A2
        MOVEQ   #0,D3
        MOVE.B  D4,D3
        SUBI.W  #$80,D3         ; entries left to skip
        BRA   LKWCHK
LKWSKP  MOVE.B  (A2)+,D0        ; skip one entry (ends on high bit)
        BPL   LKWSKP
        SUBQ.W  #1,D3
LKWCHK  TST.W   D3
        BNE   LKWSKP
LKWPR   MOVE.B  (A2)+,D0        ; print the entry
        MOVE.B  D0,D3
        ANDI.B  #$7F,D0
        BSR     MONCOUT
        TST.B   D3
        BPL   LKWPR           ; last char has the high bit set
        RTS

;---------------------------------------------------------------------
; ERROR -- print "?XX ERROR", plus " IN <line>" when executing a
; program line, and fall into READY.  The two-letter code arrives
; packed in D2.W.  The stack is reset first (the original's STKINI
; does the equivalent), so ERROR is reachable from any depth.
;---------------------------------------------------------------------
RGERR   MOVE.W  #$5247,D2       ; "RG" (RETURN WITHOUT GOSUB)
        BRA   ERROR
LSERR   MOVE.W  #$4C53,D2       ; "LS" (STRING TOO LONG)
        BRA   ERROR
STERR   MOVE.W  #$5354,D2       ; "ST" (FORMULA TOO COMPLEX)
        BRA   ERROR
SNERR   MOVE.W  #$534E,D2       ; "SN"
        BRA   ERROR
USERR   MOVE.W  #$5553,D2       ; "US"
        BRA   ERROR
OMERR   MOVE.W  #$4F4D,D2       ; "OM"
        BRA   ERROR
NFERR   MOVE.W  #$4E46,D2       ; "NF" (NEXT without FOR)
        BRA   ERROR
OVERR   MOVE.W  #$4F56,D2       ; "OV" (overflow)
        BRA   ERROR
TMERR   MOVE.W  #$544D,D2       ; "TM" (type mismatch)
        BRA   ERROR
IQERR   MOVE.W  #$4951,D2       ; "IQ" (illegal quantity)
        BRA   ERROR
DZERR   MOVE.W  #$2F30,D2       ; "/0" (division by zero)
        BRA   ERROR
ODERR   MOVE.W  #$4F44,D2       ; "OD" (OUT OF DATA, M5b)
        BRA   ERROR
CNERR   MOVE.W  #$434E,D2       ; "CN" (CAN'T CONTINUE, M5b)
        BRA   ERROR
IDERR   MOVE.W  #$4944,D2       ; "ID" (ILLEGAL DIRECT, M5b)
        BRA   ERROR
DDERR   MOVE.W  #$4444,D2       ; "DD" (REDIM'D ARRAY, M5c)
        BRA   ERROR
BSERR   MOVE.W  #$4253,D2       ; "BS" (BAD SUBSCRIPT, M5c)
        BRA   ERROR
UFERR   MOVE.W  #$5546,D2       ; "UF" (UNDEF'D FUNCTION, M5c)
        ; fall through into ERROR (see SGNFN for why no BRA)
ERROR   LEA     STACKTOP,SP
        CLR.L   OLDTXT          ; M5b: the original's ERROR goes
                                ; through TYPERR, which JSRs STKINI:
                                ; an error disallows CONT
        MOVE.L  #TMPDSC,TEMPPT  ; M5d: STKINI also frees ALL string
                                ; temporaries -- without this, an
                                ; error raised with a temp live (e.g.
                                ; SIN("A") -> ?TM) leaks a temp slot
                                ; per error until PUTNEW reports ?ST
        CLR.B   SUBFLG          ; STKINI: allow subscripts again
        MOVE.B  #$3F,D0         ; '?'
        BSR     MONCOUT
        MOVE.W  D2,D0
        LSR.W   #8,D0           ; first letter
        BSR     MONCOUT
        MOVE.W  D2,D0           ; second letter (in D0.B)
        BSR     MONCOUT
        LEA     ERRTXT(PC),A0   ; " ERROR"
        BSR     STROUT
        MOVE.W  CURLIN,D0
        CMPI.W  #$FFFF,D0
        BEQ   ERRNOLN
        LEA     INTXT(PC),A0    ; " IN "
        BSR     STROUT
        MOVE.B  #$20,D0         ; the original's INPRT prints the
        BSR     MONCOUT         ; line number via LINPRT, which
        MOVEQ   #0,D0           ; leads with a space (" IN  10";
        MOVE.W  CURLIN,D0       ; the golden's LIST shows the same
        BSR     PRTDEC          ; " 10" form) -- M5b correction
ERRNOLN BSR     CRDO
        BRA     READY

