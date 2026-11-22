# MS-BASIC 68K移植 Phase 1 / M2 結果（2026-11-18）

結論: **M2 出口条件 全 PASS**（`python3 run_m2.py`、M1 回帰 `python3 run_m1.py` も PASS）。イメージは 2,467 バイト（$0000–$09A2）。

## 成果物

- `msbasic68k.asm` — M2 まで拡張したソース
- `run_m2.py` — 検証スクリプト（アセンブル→sim 実行→機械判定）
- 副産物: `msbasic68k.bin` / `.c` / `.lst`、`m2.script` / `m2.out`

## 採用した設計（ソース先頭コメントにも明記）

- **TXTPTR = A6**（レジスタ保持。原典の ZP スロットはレイアウト維持のため残置し、実働は A6）。A6 は「最後に読んだ文字」を指す。CHRGET は A6 を進めて読み、CHRGOT は再読する。CHRGET は空白をスキップする。
- **CHRGET のフラグ契約**: 原典の「Z= ':' または EOL」「NOT C= 数字」のうち、68K に等価物のないキャリー（数字判定）は捨て、**Z=1 ⟺ terminator（NUL または ':'）** だけを再現した。数字判定は呼び出し側（LINGET・MAIN・LIST・RUN）が明示的な範囲チェックで行う。
- **トークン割当て**: RESLST の並び＝原典 REALIO=3 の並びで $80 から連番。結果として **CBM BASIC 2 と完全一致**（END=$80 … NEW=$A2、TAB(=$A3 … GO=$CB、全 76 語）。予約語表は原典の DCI 形式（最終文字に $80 を立てた ASCII）で RESLST に保持し、トークナイズ（前方一致）と LIST の逆トークナイズの両方が同じ表を使う。
- **行フォーマット**: リンク（4 バイト、絶対アドレス）＋行番号（2 バイト）＋トークン列＋$00、合計が奇数なら末尾にパッド 1 バイト。全行が偶数アドレスに載るので、68K のワード/ロングアクセスがアライメント例外を起こさない。末尾はリンク 0 の 4 バイト（エンドマーカ）で、VARTAB はその直後を指す。リンクは絶対アドレスなので編集のたびに **LNKPRG** で全リンクを張り直す（原典も編集後に LNKPRG を回す。原典は 2 バイトリンク）。
- **実行コア**: FETCH（原典 GONE 相当）が文トークンを STMDSP（35 エントリ、アドレス表）でディスパッチし、ハンドラには「トークンの次の文字を先読みした状態（D0.B と A6）」で入る。文ハンドラが terminator を指して戻ると EXEC（原典 NEWSTT 相当）が ':' なら次の文、NUL なら次行（CURLINP 経由）へ進む。GOTO/RUN/END/LIST は戻りアドレスを捨てて FETCH/READY へ直接続く（原典の RTS スキームの等価形）。
- **実物にした文**: NEW、LIST（引数なし／番号／範囲 `n-m`・`-m`・`n-`）、RUN（引数なし／番号付き）、CLR、PRINT（文字列リテラルのみ＋';' 連結＋引数なしで改行。それ以外は ?SN ERROR）、GOTO、END、REM、DATA（文末までスキップ、引用符配慮あり）。他の文トークンは全部 ?SN ERROR にディスパッチ（表自体は全キーワード分ある）。非トークンの文頭は LET が来る場所だが M2 では ?SN ERROR。
- **エラー**: ERROR が "?XX ERROR" と、プログラム実行中なら " IN <行番号>" を出す形に一般化（SN/US/OM）。スタックは STACKTOP にリセットしてから READY に落ちる（原典 STKINI の等価）。READY でも毎回スタックをリセットする。

## トランスクリプト実物（m2.out、改行を可視化）

```
### COMMODORE BASIC ###\r\n 61440 BYTES FREE\r\n
\r\nREADY.\r\n
20 PRINT "WORLD"\r\n \r\nREADY.\r\n
10 PRINT "HELLO"\r\n \r\nREADY.\r\n
30 END\r\n \r\nREADY.\r\n
LIST\r\n \r\n10 PRINT "HELLO"\r\n20 PRINT "WORLD"\r\n30 END\r\nREADY.\r\n
RUN\r\n HELLO\r\nWORLD\r\n \r\nREADY.\r\n
20 PRINT "EARTH"\r\n \r\nREADY.\r\n
LIST\r\n \r\n10 PRINT "HELLO"\r\n20 PRINT "EARTH"\r\n30 END\r\nREADY.\r\n
20\r\n \r\nREADY.\r\n
LIST\r\n \r\n10 PRINT "HELLO"\r\n30 END\r\nREADY.\r\n
PRINT "DIRECT"\r\n DIRECT\r\n \r\nREADY.\r\n
NEW\r\n \r\nREADY.\r\n
LIST\r\n \r\nREADY.\r\n
PRINT "ZZEND"\r\n ZZEND\r\n \r\nREADY.\r\n
```

## 出口条件の判定（run_m2.py の自動判定、全 PASS）

1. 逆順入力した 3 行が LIST で行番号順に再構成される: PASS
2. RUN で HELLO / WORLD の順に表示され READY. に戻る: PASS
3. `20 PRINT "EARTH"` の入れ直しで置換される: PASS
4. `20`（行番号のみ）で 20 行が消える: PASS
5. ダイレクト `PRINT "DIRECT"` が動く: PASS
6. NEW の後の LIST が空: PASS
7. M1 回帰（run_m1.py）: PASS

追加のアドホック検証（出口条件外、目視＋部分文字列で確認済み）: 複文行 `10 PRINT "ONE":PRINT "TWO"`、`20 GOTO 40` での 30 行スキップ、REM 行と DATA 行の実行時スキップ、`LIST 20-60` の範囲指定と DATA 本文（トークン化されていない生テキスト）の正しい再表示。

## 原典から外れた点と理由

- **CHRGET の数字キャリー契約を捨てた**（上記）。68K には SEC 相当の素直な等価形がなく、呼び出し側の明示チェックの方が読みやすい。
- **空白のみの行・空行で READY. を再表示する**。原典 MAIN は再表示せず INLIN に戻るが、M1 回帰契約（READY. の出現回数）が優先。
- **リンクが絶対アドレス**（原典は 2 バイト絶対）。68K のアドレス幅に合わせた M1 の widening 方針の継続。編集後の LNKPRG 全張り直しは原典と同じ。
- **行のパッドバイト**。68K のアライメント要件のため（原典には概念なし）。
- **CURLIN を GOTO/RUN のジャンプ時点で設定する**。原典は次行へ移る NEWSTT で設定するが、エラー表示用に行番号が要るのは同じで、結果は等価。
- **GOTO の残り文スキップは引用符を配慮しない**（原典 REMN は配慮する）。GOTO 行に文字列が来るのは稀で、M5 の仕上げ項目とした。
- **行番号の上限チェックは LINGET 内の 63999 超過判定**で実装（原典は桁あふれ前の高バイトチェック）。
- ダイレクト行の CRUNCH は原典同様に行頭の空白を CHRGET が読み飛ばすため、行頭空白は保存されない（原典も同じ挙動）。

## 踏んだ問題と対処

1. **STORE が全ての番号付き行で ?OM ERROR**。原因は FNDLIN の戻りフラグ（Z）を、直後の `MOVEQ #0,D5` が上書きしていたこと。68K ではほぼ全ての MOVE が CCR を書くので、原典の「フラグは命令を跨いで生きる」感覚が通用しない。対処: BSR の直後に分岐を置き、旧行長の取得を分岐先へ移した。同種の危険箇所（MOVEA はフラグを変えないので安全、等）は全ハンドラ分を点検済み。
2. アセンブラ（asm68k-py）は今回の範囲では新規の制約に当たらなかった（`MOVE.B (A3)+,(A4)+`、`JSR (A0)`、`LEA d(A0),A1` 等すべて通過）。

## M3 への引き継ぎ

- **式評価の入口**: FETCH で非トークン文頭を SNERR にしている場所が LET の席。式評価（FORMULA EVALUATION、原典 3164–3598）と変数検索（3599–3779）は TXTPTR=A6・CHRGET 契約の上にそのまま載る。文ディスパッチの残り（FOR/NEXT/GOSUB/RETURN/LET/IF の一部）も STMDSP の SNSTUB を差し替えるだけでよい。
- **FAC/ARG は ZP ミラーに原典オフセットで既に確保済み**（FAC 8 バイト、ARG 6 バイト — 5 バイトパック＋余り。M3 で要確認: 原典 FAC は ADDPRC で 6 バイト相当＋FACOV 等。レイアウト表はソース先頭コメント参照）。
- **PRINT の数値・式対応**は PRINTH の SNERR 分岐を式評価への分岐に差し替える形になる。';' の後処理と terminator 処理は M2 の骨格がそのまま使える。
- **GOSUB/RETURN/FOR のスタック形式**は原典が CPU スタック上にフレームを積む設計。M2 の READY/ERROR のスタックリセットは「実行中フレームはエラーで全部死ぬ」という原典 STKINI の意味論と一致させてあるので、そのまま採用できる。
- **CONT は未実装**（SNSTUB）。OLDTXT/OLDLIN の保存は END/STOP 実装時（M5）に必要。
- 行番号 0 の行も格納・実行できる（原典準拠）。LIST の範囲指定は実装済みなので M3 以降のデバッグに使える。
