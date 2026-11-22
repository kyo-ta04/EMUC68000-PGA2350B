# M5b 結果メモ — DATA/READ/RESTORE、INPUT、ON、STOP/CONT、GET

日付: 2026-11-19
対象: `msbasic68k.asm`（Phase 1 ポート）、検証 `run_m5b.py`
結果: **81/81 checks PASS**（M5b 本体 + GET ミニセッション + 回帰 run_m1.py〜run_m5a.py 全 PASS）
イメージ: **11,109 バイト**（$0000–$2B64、619 シンボル。M5a の 9,671 バイトから +1,438）
分岐チェッカ: check_branches.py / check_short_branches.py とも **0 bad**

## 実装範囲

### DATA / READ / RESTORE
- 原典の PROCESS_INPUT_LIST 設計をそのまま共有エンジン **INLOOP** として実装し、INPUT と READ を一本化した（INPFLG: 0=INPUT、$80=READ）。変数リスト処理・項目スキャン・代入・終端検証が両者で共通。
- **DATPTR / DATLIN 管理**: DATPTR は「常に終端文字（',' ':' NUL）の上にいる」という原典の不変条件で保持。CLEARC は原典通り RESTOR を呼ぶ（DATPTR := TXTTAB-1）。SCRATCH（NEW）も同じ初期化。
- **FNDDATA**: DATA トークン（$83）の前方探索。入口は TXTTAB-1（1 行目、DATLIN をその行番号に更新）/ ':'（同行の次文）/ NUL（次行の先頭）の 3 形態。文のスキップには既存の DATAN（引用符対応）を再利用。枯渇で **?OD ERROR**（エラー行は DATLIN ではなく実行中行。原典通り）。
- 数値項目は **INPFIN** 経由（後述）、文字列項目は INPSTR: 引用符付きは閉じ引用符か NUL まで、無引用は ',' ':' NUL まで。末尾スペースはデータとして保持（原典 STRLT2 の挙動）。BUF 内のデータ（直接モード READ）は文字列空間へコピー、プログラムテキストは共有（原典と同じ二分）。
- 終端検証（STRDN2）: 項目の後に ',' ':' NUL 以外があれば、READ は CURLIN:=DATLIN にして ?SN ERROR（データ行の行番号で報告される原典挙動を再現、`DATA 12X` で照合済み）。
- **RESTORE** は引数なしで先頭へ（行番号引数版は原典 CBM BASIC 2 に無いので入れていない）。

### INPUT
- プロンプト文字列（`INPUT "NAME";N$`）、複数変数、カンマ区切り、文字列変数を実装。
- データ不足時は **"?? "** を出して継続行を読む（原典 NXIN 経路）。
- 数値項目の終端が不正だと **?REDO FROM START** を出して文全体を最初からやり直す（プロンプトも再表示。原典 RESPERR→OLDTEXT 復帰と同じ）。
- 余分なデータは **?EXTRA IGNORED**。
- 直接モードの INPUT は **?ID ERROR**（ERRDIR）。INPUT# は Phase 1 にチャネルが無いため SN スタブのまま。
- 最初の入力行が空行なら無言で READY に戻り、CONT で INPUT 文から再開する（原典 STPEND 相当。FETCH の境界保存で再開できる）。

### ON...GOTO / ON...GOSUB
- FRMNUM + GETBYTE で 0–255 のインデックス（範囲外は ?IQ ERROR）。対象番号を LINGET で数えながらスキップし、ヒットしたら GOTOH / GOSUBH に最初の数字で A6/D0 を仕掛けて合流。**0 または対象数超過では次文へ素通り**（golden 照合済み）。GOSUB 形は M5a の GOSUB フレーム（22 バイト + GOSUBSP リスト）をそのまま使う。

### STOP / CONT
- FETCH が文境界ごとに継続文脈を保存する（原典 NEWSTT の OLDTEXT/OLDLIN 保存に対応）: OLDTXT（文頭の 1 バイト前を指す）、OLDLIN、OLDCIP（行先頭ポインタ）、CONTMD。
- STOP は文脈を保存して **"BREAK IN  20"** を表示し READY へ。END も同じ保存を行う（表示なし）。直接モードの STOP は "BREAK" のみ（原典 ERRFIN が CURLIN=$FFFF でサフィックスを省く挙動通り）。
- CONT は保存文脈から再開。文脈が無ければ **?CN ERROR**。エラー発生時は原典通り文脈を破棄（TYPERR→STKINI 相当）。
- **プログラム編集後の CONT**: golden で実測したところ、STOP 後にプログラム行を 1 行でも入力すると継続文脈は無効化され ?CAN'T CONTINUE になる（原典の実挙動）。ポートも同じ挙動になることを照合した（R モード）。

### GET
- 直接モードは ?ID ERROR。プログラム内では ACIA ステータス（RDRF）をポーリングして待たない（ノンブロッキング）。
- 数値変数: キーがあれば 1 文字を FIN で解釈（数字キーはその数字の値、符号・小数点のみは 0）。文字列変数: 1 文字文字列を文字列空間に構築（CHR$ と同じ経路）。キー無しは数値 0 / 文字列 ""。
- 終端が不正な文字（数字でも符号でもない文字）は原典 INPUTERR の GET トラップを再現: **CURLIN を毒して ?SN ERROR を行番号サフィックス無しで出す**（下記「踏んだ問題」参照）。

## 照合結果

- run_m5b.py: **81/81 PASS**。内訳: メインセッション（READ/DATA 各種、INPUT 各種、ON、STOP/CONT、GET、編集後 CONT）を golden（py65 + cbmbasic2.bin）とリージョン単位で照合、GET キー無しミニセッション、回帰 5 本。
- 照合の流儀は従来通り: 通常出力はバイト照合（NUMSPC の $1D→$20 正規化のみ、今回は 28 バイト）、エラーは R モード（ポート側リージョンをバイト完全一致で固定し、golden 側は長形エラー文の部分文字列で同条件を確認）。
- 主な照合点: READ 数値・文字列混在、引用符内カンマ/コロン、RESTORE 再 READ、直接モード READ、INPUT プロンプト付き/複数変数/?? 継続/REDO/EXTRA IGNORED、ON の 1..n 分岐と 0・n+1 素通り、STOP→CONT（文途中 STOP 含む）、GET 文字/数字/不正文字/キー無し。

## 原典から外れた点

1. **CONTMD フラグ（ポート内部の都合）**: 原典は TXTPTR の約束（最後に読んだ文字を指す）で STOP 保存と文境界保存を単一の OLDTEXT に統一できるが、ポートの A6 約束では 2 種の再開（STOP 点からは EXEC 経由、文境界からは FETCH 経由）を区別する必要があり、1 バイトのフラグを追加した。外部挙動は原典通り。
2. **FOR/GOSUB の中での STOP→CONT**: ポートは M3 以来の約束で READY が FORSP/GOSUBSP リストをリセットするため、ループ内・サブルーチン内で STOP して CONT するとループ/戻り文脈は失われる（直線コードの STOP/CONT は原典通り正確）。原典はスタックフレームが残るので継続できる。既知の制限として明記する。
3. **GET の複数変数形（GET A,B）未実装**: 原典は CHKCOM でループする。ポートは 1 変数のみ（タスク範囲は 1 文字取得）。',' が続くと ?SN ERROR になる。
4. **GET# / INPUT# は未実装**（?SN ERROR）。Phase 1 にチャネル I/O が無いため。原典 CBM BASIC 2 には存在する。
5. **GET の待ちセマンティクス**: 原典 CBM の GET は MONRDKEY でキーを待つ（ブロックする）が、タスク仕様（無ければ 0/""）に従いノンブロッキングとした。golden ハーネスの GETIN（空キューで 0 を返す）とは一致する。キーが既に来ている場合の挙動は原典と同一。
6. **発見した既存のずれ（M5b では未修正）**: golden の LIST は行番号を前置スペース付き（" 10 STOP"）で出すが、ポートの LIST は前置スペースが無い（M2 由来。M2 の照合はこの点に寛容）。今回、エラー/STOP の " IN  n" はこの前置スペース形式に合わせて修正したが、LIST 本体は回帰リスクを避けて触っていない。最終フェーズでの修正候補。

## 踏んだ問題

1. **GETH の ?SN ERROR（デバッガで特定）**: ERRDIR が D0 に CURLIN をロードするため、FETCH が仕掛けた変数名の先行文字が壊れていた。sim デバッガで SNERR にブレークポイントを置き、D0=$000A（=CURLIN 10）と A0=GETH を確認して特定。INPUTH が無事だったのは ERRDIR 後に CHRGOT で再仕掛けしていたためで、GETH にも同じ再仕掛けを追加して解決。
2. **INPFIN の新設**: 評価器の FIN は単項マイナスがトークン化済みである前提で先行符号を見ないため、`DATA -7` や INPUT の負数がそのままでは読めなかった。原典 FIN の先行 '-'/'+' 処理だけを切り出したラッパ INPFIN を INLOOP 専用に新設。
3. **変位 0 分岐の誤エンコード 2 件**: READH→INLOOP と STRITEM→STRDN2 の BRA（分岐先が直後命令）が asm68k-py の既知の癖に当たり、check_branches.py が検出。フォールスルーに書き換えて解決。
4. **" IN  n" の前置スペース**: golden 実測で STOP は "BREAK IN  20"、エラーは "ERROR IN  10"（IN の後にスペース 2 つ = LINPRT の前置スペース）。ポートは 1 つしか無かったので ERROR サフィックスと STOP を原典形式に修正（過去の照合は "IN n" をバイト比較していなかったため回帰なし）。
5. **GET 数値＋英字キーの原典トラップ**: golden 実測で `GET N` に 'Q' を与えると ?SYNTAX ERROR が**行番号なし**で出る。mist64 の INPUTERR を読み、CURLIN の上位バイトを $FF に毒してサフィックスを消す原典の仕掛けと判明。ポートも CURLIN:=$FFFF としてから SNERR する形で再現した。
6. **私のテスト前提の誤り 2 件（golden 実測で訂正）**:
   - `DATA ABC : DATA DEF` は 2 つのデータ文にならない。CRUNCH は DATA 以降を行末まで逐語コピーするので 2 番目の DATA はデータテキストであり、':' で項目リストは終わる → 両機とも ?OD ERROR が正解だった。
   - `PRINT "X": DATA 111`（コロンの後にスペース）は FINDATA のコロン経路が ':' の**直後 1 バイト**だけを DATA トークンと比較するため、スペースに隠れて見つからない → 両機とも OD。スペース無し `:DATA 111` は正しく見つかることを陽性テストとして追加した。
7. **ハーネスの枠組みの発見 3 件**: (a) CBM は行入力ごとに CRLF を 1 つ出すため golden リージョンは先頭 CRLF を 1 つ落として比較。(b) golden の CHRIN はエコーしないが入力行の終端 CRLF は出すので、INPUT のエコー除去は文字分だけにした。(c) emu の --until は READY. の途中で止まりうる（--settle 2000000 で解決）、終了マーカーは行エコーに含まれない形（`"ZZM5";"END"`）にした。

## GET の検証限界（ハーネス都合）

- emu はスクリプト全体を RX FIFO に先読みするため「キューが空」はスクリプト末尾でしか作れない。キー無し GET はミニセッション（GET が最後の消費者になる構成）で検証した。golden 側も GETIN が空キューで 0 を返す同条件で照合。
- キーは生バイト供給であり、実機キーボードのマトリクスやリピート等の効果は対象外。

## M5c への引き継ぎ

- 配列（DIM と配列要素）と GC の配列要素スキャン（M5a メモの宿題）、DEF FN、残りの関数群（LOG/EXP/SQR/^・三角関数・RND、文字列関数 LEN/STR$/VAL/ASC/LEFT$/RIGHT$/MID$)、PEEK/POKE が残作業。
- GET の複数変数形（GET A,B）と GET#/INPUT# は上記の通り未実装。チャネル I/O を入れるかどうかは Phase 1 の範囲判断として残す。
- LIST の行番号前置スペース（" 10" 形式）は最終フェーズの修正候補。直す場合は run_m2.py の LIST 照合の寛容さを確認してから。
- FOR/GOSUB 内 STOP の CONT 文脈喪失は、READY のリストリセット約束に由来する。M5c で READY/CLEARC 周りを触る場合はこの制約を意識すること。
- 文字列ディスクリプタの奇数アドレス問題（M5a メモ）は実機フェーズの宿題として継続。
