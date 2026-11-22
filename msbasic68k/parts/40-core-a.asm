; Interpreter core, part A.
; Part of msbasic68k.asm -- assembled only as part of
; the combined source produced by build.py.  Do not
; assemble this file on its own.
; Dispatch tables, RESLST, INIT, main loop, statements, errors.
;---------------------------------------------------------------------
; Statement dispatch table: handler addresses in token order
; ($80 END .. $A2 NEW).  Kept right after the vectors so its own
; address stays even for the longword reads in FETCH.
;---------------------------------------------------------------------
STMDSP  DC.L    ENDH
        DC.L    FORH            ; FOR    (M3)
        DC.L    NEXTH           ; NEXT   (M3)
        DC.L    DATAN           ; DATA   (skip)
        DC.L    SNSTUB          ; INPUT# (channels: not in Phase 1)
        DC.L    INPUTH          ; INPUT  (M5b)
        DC.L    DIMH            ; DIM    (M5c)
        DC.L    READH           ; READ   (M5b)
        DC.L    LETH            ; LET    (M3)
        DC.L    GOTOH           ; GOTO
        DC.L    RUNH            ; RUN
        DC.L    IFH             ; IF     (M4)
        DC.L    RESTOREH        ; RESTORE (M5b)
        DC.L    GOSUBH          ; GOSUB  (M5a)
        DC.L    RETURNH         ; RETURN (M5a)
        DC.L    REMH            ; REM
        DC.L    STOPH           ; STOP   (M5b)
        DC.L    ONH             ; ON     (M5b)
        DC.L    WAITH           ; WAIT   (M5d)
        DC.L    SNSTUB          ; LOAD   (stub in Phase 1)
        DC.L    SNSTUB          ; SAVE   (stub in Phase 1)
        DC.L    SNSTUB          ; VERIFY (stub in Phase 1)
        DC.L    DEFH            ; DEF    (M5c)
        DC.L    POKEH           ; POKE   (M5d)
        DC.L    SNSTUB          ; PRINT# (M5)
        DC.L    PRINTH          ; PRINT
        DC.L    CONTH           ; CONT   (M5b)
        DC.L    LISTH           ; LIST
        DC.L    CLEARH          ; CLR
        DC.L    SNSTUB          ; CMD    (M5)
        DC.L    SNSTUB          ; SYS    (M5)
        DC.L    SNSTUB          ; OPEN   (M5)
        DC.L    SNSTUB          ; CLOSE  (M5)
        DC.L    GETH            ; GET    (M5b)
        DC.L    NEWH            ; NEW

;---------------------------------------------------------------------
; RESLST -- the reserved word list, in token order.  Each word is
; stored as plain ASCII with the LAST character's high bit set
; (the original's DCI encoding).  A 0 byte ends the list.
;---------------------------------------------------------------------
RESLST  DC.B    "EN",$C4         ; END
        DC.B    "FO",$D2         ; FOR
        DC.B    "NEX",$D4        ; NEXT
        DC.B    "DAT",$C1        ; DATA
        DC.B    "INPUT",$A3      ; INPUT#
        DC.B    "INPU",$D4       ; INPUT
        DC.B    "DI",$CD         ; DIM
        DC.B    "REA",$C4        ; READ
        DC.B    "LE",$D4         ; LET
        DC.B    "GOT",$CF        ; GOTO
        DC.B    "RU",$CE         ; RUN
        DC.B    "I",$C6          ; IF
        DC.B    "RESTOR",$C5     ; RESTORE
        DC.B    "GOSU",$C2       ; GOSUB
        DC.B    "RETUR",$CE      ; RETURN
        DC.B    "RE",$CD         ; REM
        DC.B    "STO",$D0        ; STOP
        DC.B    "O",$CE          ; ON
        DC.B    "WAI",$D4        ; WAIT
        DC.B    "LOA",$C4        ; LOAD
        DC.B    "SAV",$C5        ; SAVE
        DC.B    "VERIF",$D9      ; VERIFY
        DC.B    "DE",$C6         ; DEF
        DC.B    "POK",$C5        ; POKE
        DC.B    "PRINT",$A3      ; PRINT#
        DC.B    "PRIN",$D4       ; PRINT
        DC.B    "CON",$D4        ; CONT
        DC.B    "LIS",$D4        ; LIST
        DC.B    "CL",$D2         ; CLR
        DC.B    "CM",$C4         ; CMD
        DC.B    "SY",$D3         ; SYS
        DC.B    "OPE",$CE        ; OPEN
        DC.B    "CLOS",$C5       ; CLOSE
        DC.B    "GE",$D4         ; GET
        DC.B    "NE",$D7         ; NEW
        DC.B    "TAB",$A8        ; TAB(
        DC.B    "T",$CF          ; TO
        DC.B    "F",$CE          ; FN
        DC.B    "SPC",$A8        ; SPC(
        DC.B    "THE",$CE        ; THEN
        DC.B    "NO",$D4         ; NOT
        DC.B    "STE",$D0        ; STEP
        DC.B    $AB              ; +
        DC.B    $AD              ; -
        DC.B    $AA              ; *
        DC.B    $AF              ; /
        DC.B    $DE              ; ^
        DC.B    "AN",$C4         ; AND
        DC.B    "O",$D2          ; OR
        DC.B    $BE              ; >
        DC.B    $BD              ; =
        DC.B    $BC              ; <
        DC.B    "SG",$CE         ; SGN
        DC.B    "IN",$D4         ; INT
        DC.B    "AB",$D3         ; ABS
        DC.B    "US",$D2         ; USR
        DC.B    "FR",$C5         ; FRE
        DC.B    "PO",$D3         ; POS
        DC.B    "SQ",$D2         ; SQR
        DC.B    "RN",$C4         ; RND
        DC.B    "LO",$C7         ; LOG
        DC.B    "EX",$D0         ; EXP
        DC.B    "CO",$D3         ; COS
        DC.B    "SI",$CE         ; SIN
        DC.B    "TA",$CE         ; TAN
        DC.B    "AT",$CE         ; ATN
        DC.B    "PEE",$CB        ; PEEK
        DC.B    "LE",$CE         ; LEN
        DC.B    "STR",$A4        ; STR$
        DC.B    "VA",$CC         ; VAL
        DC.B    "AS",$C3         ; ASC
        DC.B    "CHR",$A4        ; CHR$
        DC.B    "LEFT",$A4       ; LEFT$
        DC.B    "RIGHT",$A4      ; RIGHT$
        DC.B    "MID",$A4        ; MID$
