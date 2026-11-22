INIT    LEA     ZPBASE,A0
        MOVE.W  #ZPSIZE,D0
INICLR  CLR.B   (A0)+
        SUBQ.W  #1,D0
        BNE   INICLR
