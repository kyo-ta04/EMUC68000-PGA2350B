# R2-M4 結果記録（2026-11-22）— コンマ NEXT 修正、関数型規則・配列・USR：D6／D7／D8／D10

作業ツリー `~/workspace/msbasic-68k/redesign/`（rd バリアント）。phase1/ は不変（一切触れていない — Part 0 の修正の phase1 へのバックポートは Kyo の別判断。本記録末尾参照）。
設計の正本：`redesign-r0-design.md` §3（D6／D7／D8／D10）、土台：`redesign-r2-m1-results.md`／`redesign-r2-m2-results.md`／`redesign-r2-m3-results.md`。

## ゲート結果

| ゲート | 結果 |
|---|---|
| Part 0 単独ゲート（build + emu 全スイート） | **PASS** — 206/206（従来 196 + Part 0 新規 10） |
| `python3 build.py rd` | **PASS** — 19,240 バイト / BSD sum 36432（R2-M3 時点 19,060 / 2931、+180 バイト） |
| `python3 run_rd.py`（emu） | **233/233 PASS**（従来 196 無変更 + Part 0 の 10 + M4 新規 27） |
| `MSB_EMU=emu_strict python3 run_rd.py` | **233/233 PASS** |
| ASCIIART ゴールデン | **バイト一致**（sum16 25584 / CRC32 0D6D8795） |
| ASCIIART サイクル | **1,005,000,000**（R2-M3 と同値、予測 ±3% 以内） |

asm68k-py の拡張は **不要だった**（新規命令なし。USR 検証用ルーチン 2 本も既存サブセットでアセンブルできた）。

## Part 0 — コンマ NEXT 修正（既存欠陥、Kyo 承認で実施）

### 症状と切り分けプローブ

`NEXT J,I` 形式が `?NF ERROR` で落ちる。切り分けの結果、壊れるのは **「コンマ遷移の後にループが継続する」場合だけ**だった：

- 両ループがコンマ段で同時に終了する `NEXT J,I` → 正常（DONE まで到達）
- 内側だけ終了して外側が継続する `NEXT J,I` → `?NF`（外側ループの2周目に入れない）
- `NEXT I,J`（J のフレームが無い）→ I 終了後に `?NF`、これは原典通り正しい挙動

### 根本原因

文ディスパッチは FETCH の `JSR (A0)` で、戻りアドレスは **最上位 FOR フレームの直下**（FORSP−4）に積まれる。単独 NEXT の継続（NX_BACK）は素の `RTS` でこれを pop して戻る。一方 NX_EXIT はフレーム pop の際に `LEA 52(A2),SP` で SP をフレームの上端までリセットする — この時点で戻りアドレスは SP の下に取り残される。コンマが続く場合、NX_EXIT はそのまま次の変数を NX_GO で処理し、その変数のループが継続すると NX_BACK の `RTS` が **I フレーム先頭の 4 バイト**（マーカー＋FORPNT 上位）を pop して暴走していた（暴走先がたまたまエラー経路に着地して ?NF に見えた）。

CHRGOT によるコンマ検出自体は正しかった（PTRGET は A6 を名前の終端文字＝コンマの上に残す）。

### 修正（parts/64-core-b3.asm、NX_EXIT のコンマ分岐に 1 命令）

次の変数を処理する前に、退避済みの戻りアドレスを積み直す：

```
        MOVE.L  NEXTRET,-(SP)   ; R2-M4 Part 0 (NEXT-fix)
        BRA     NX_GO
```

- 継続した場合：NX_BACK の RTS がこの複製を pop して正しく戻る（SP は FORSP に復帰）
- 終了した場合：その変数の NX_EXIT が再び SP をリセットするので、複製は元の戻りアドレスと同様に破棄される
- エラー（?NF 等）の場合：エラー処理が SP を丸ごと初期化するので無害

bare NEXT・単独 NEXT・不一致変数の ?NF・フレーム巻き戻しの意味論は不変。回帰チェック 5 本（RUN 単位）：FP ネスト `NEXT J,I`（総和 9）、INT ネスト `NEXT J%,I%`（36）、混在 `NEXT J%,I`／`NEXT J,I%`（各 9）、余分な変数 `NEXT I,J` の ?NF 保存。

**phase1 には同じ欠陥が残っている**（phase1 の NX_EXIT も同型で、44 バイトフレーム版。M3 記録のプローブで ext ビルドでの再現を確認済み、本記録でもコード形状を確認）。バックポートは Kyo の別判断として残す。

## Part A — 関数型規則（D6、D10 の VAL）

### 機構：型付きディスパッチ FE_UF_T / FE_UFN_T（parts/62-core-b2.asm）

M1 のチョークポイント（FE_UF／FE_UFN がハンドラ後に FACTYP を一律クリア）は維持し、型を持つ関数だけを **クリア無しの変種 FE_UF_T／FE_UFN_T** に移した。_T 側のハンドラは全経路で自分の結果型を決定的に設定する責任を持つ。SGN／INT／ABS は M2 と同じ理由（FP コアは内部 FP コードからも直接呼ばれる）で **ラッパ**（SGNFN_I／INTFN_I／FABSFN_I、同ファイル）にした。

### D6 の個別規則

| 関数 | 規則 | 実装 |
|---|---|---|
| PEEK | 常に INT（0..255） | PEEKFN の末尾を GIVAYF → **SFLOAT32** に変更、FE_UF_T 経由 |
| DEEK | 常に INT（0..65535） | DEEKFN の末尾を WORDVAL → **SFLOAT32** に変更（WORDVAL は唯一の呼び出し元を失い削除）、FE_UFN_T 経由 |
| LEEK | ≤ $7FFFFFFF は INT、それ以上は厳密な FP | LEEKFN の末尾で範囲分岐：SFLOAT32 / UFLOAT（従来通り）。§3 は「整数を返す」とのみ言うため、符号付き int32 に収まらない値の扱いはタスク文の解釈（収まれば INT、超えれば厳密 FP）を採用し、ここに明記 |
| SGN | INT 入力 → INT の −1/0/1、FP 入力 → 従来 FP | SGNFN_I：SIGN_FAC（FP シャドウの符号は厳密）→ SFLOAT32。INT 0 は FP 0 に劣化（既知の観測同一事項） |
| ABS | 型を保持。−2147483648 のみ FP へ昇格 | FABSFN_I：INT は FACSIGN クリア＋FACINT 符号反転で双表現を同期。最小値はシャドウがちょうど +2147483648.0 になるので FACTYP を落として昇格（D3 の精神） |
| INT | INT 入力 → 恒等（INT のまま）、FP 入力 → 従来の床で結果は FP | INTFN_I：INT は即 RTS（FAC/FACINT は既に一致）。**INT(−2.5) を INT −3 にはしない**（§3「INT は整数に恒等・FP に従来動作」通り） |
| VAL | D1 規則をそのまま（D10 残件） | ディスパッチを FE_UF_T に変更するだけ。VALFN → INPFIN → FIN が全経路で FACTYP を設定する（FIN_PARSE の並行 int 蓄積、FIN_HIT の復元、VAL("") は ZERO_FAC）。VAL("2147483647") が整数形表示になることが判別チェック |

VAL の境界（FIN の意味論の継承として記録）：`VAL("-2147483648")` は **FP**。FIN は絶対値で解析し 2147483648 は int32 に収まらないため候補落ちし、符号は NEGOP が後付けする — コード内リテラルの `-2147483648` も同じ経路で FP であり、D1 の実装済み意味論と一致する（% への代入では STO_INT32 が受け止める）。

### 関数監査表（M4 後、全関数）

| 関数 | 入力→出力の型規則（M4 後） | 変更 |
|---|---|---|
| SGN | INT→INT、FP→FP | **変更**（D6） |
| INT | INT→恒等、FP→FP（床） | **変更**（D6） |
| ABS | 型保持、INT 最小値のみ FP 昇格 | **変更**（D6） |
| PEEK | → INT | **変更**（D6） |
| DEEK | → INT | **変更**（D6） |
| LEEK | → INT（≤ $7FFFFFFF）／厳密 FP（超過） | **変更**（D6） |
| VAL | 解析テキストの D1 型 | **変更**（D10） |
| USR | D8 タグ規約（Part B） | **変更**（D8） |
| SQR／RND／LOG／EXP／COS／SIN／TAN／ATN | 常に FP（FE_UFN のチョークポイントが保証。INT 入力でも FP 結果） | 不変 |
| FRE | FP（§3 は無言 → 据え置き。FE_UF 経由） | 不変 |
| POS | FP（FE_UF 経由、GIVAYF） | 不変 |
| LEN／ASC | FP（§3 は無言 → 据え置き。GIVAYF が型を確定） | 不変 |
| INSTR | FP（GIVAYF 終端） | 不変 |
| STR$／CHR$／LEFT$／RIGHT$／MID$ | 文字列結果（FACTYP は PUTNEW 等で確定） | 不変 |

「偶発的な FACTYP 破壊」の監査：_T 側ハンドラは全経路で型を確定する（PEEKFN／DEEKFN は SFLOAT32 一択、LEEKFN は SFLOAT32／UFLOAT の二択で UFLOAT はクリア側、VALFN は FIN か ZERO_FAC、USR は Part B の規約）。チョークポイント側は従来通り一律 FP で決定的。

## Part B — 配列（D7 残件）と USR（D8）

### % 配列要素ロード（D7）— 監査の結論：既に成立、機構を明記

プローブ先行で確認した通り、M1 時点で既に `A%(1)=2000000000` に対して `PRINT A%(1)+1` → ` 2000000001 `（整数形）、`A%(1)\7` → 285714285 が成立していた。機構は FRM_VARIABLE（parts/60-core-b.asm）：

- 配列要素には要素ごとのタグは **無い**。型は **名前の % 印**から来る：PTRGET が INTFLG を立て（VARNAM にも符号化）、FRM_VARIABLE の FV_INT 分岐が要素スロットの 4 バイト（＝ int32 そのもの）を SFLOAT32 でロードする。スカラー % と同一経路（PTRGET_ARR は VARPNT を要素アドレスにするだけ）
- 型リーク監査：FRM_VARIABLE の 3 分岐（FV_STR＝クリア、FV_INT＝SFLOAT32 で設定、FP＝クリア後にタグ付きなら FAC32I で再導出）は全て結果型を決定的に設定する。他の要素ロード経路は存在しない（LET 左辺はストア、FN 引数設置もストア側）
- FP 配列の要素は M1 のタグ機構（値フィールド +5 の INTTAG）で INT 往復する経路が別にあり、M1 の既存チェックが担保

M4 ではスイートに判別チェック 3 本（+1 の整数形、\ への参加、要素同士の混合和）を追加して固定した。コード変更は無し。

### USR 型タグ（D8）— USRTYP ミラー方式（parts/70-ext1.asm、equates に USRTYP = ZPBASE+$1F2）

§3 D8 は「引数・戻り値の型を型タグで受け渡す（A0＝FAC アドレス規約に型の解釈を追加）」とだけ定める。具体機構は以下の通り設計・実装した：

- **引数側**：USRFN は呼び出し前に FACTYP を **USRTYP（論理 $1F2）へミラー**する。ルーチンは USRTYP を読めば引数が INT か分かり、その場合 FACINT に値が入っている（PEEK 498 でも BASIC から読める）
- **戻り値側**：USRFN はミラーの直後に **FACTYP をクリア**し、FACTYP を「結果型フラグ（初期値 FP）」としてルーチンに渡す。ルーチンが INT 結果を宣言する場合は RTS 前に **FACTYP=1 かつ FACINT=値** を設定する。USRFN は復帰後、FACTYP=1 なら FACINT を正として SFLOAT32 で FP シャドウを再構築し、(FAC, FACINT, FACTYP) の三つ組を常に整合させる。FACTYP=0 なら FAC がそのまま FP 結果で、FACINT は無効（FACTYP=0 の規約通り）
- **レガシー互換**：FACTYP に触れない従来ルーチンは、クリアされた 0 がそのまま残るため FAC が FP 結果として返る — 従来と完全同一。恒等ルーチン（RTS のみ）と定数 2.0 ルーチンの既存チェックが無変更で通過し、INT 引数 `USR(2000000000)` でも定数ルーチンが ` 2 ` を返すことを新規チェックで固定した（入り口タグの残留を正と誤認する設計だと 2000000000 が返ってしまう所）
- ディスパッチは FE_UFN_T に変更（チョークポイントのクリアが INT 結果を消さないため）。文字列引数の ?TM（CHKNUM）、未設定ベクタの ?FC は不変

検証用ルーチン（asm68k-py で $6000 にアセンブルし DATA 経由で設置、バイト列は run_rd.py のコメントに明記）：
1. エコータグ：USRTYP を読み、INT 引数なら INT 2000000000、FP 引数なら INT 7 を返す → `USR(5)` → ` 2000000000 `（整数形が判別子）、`USR(1.5)` → ` 7 `
2. インクリメント：FACINT := FACINT+1、FACTYP := 1 → `USR(41)` → 42、`USR(41)+1` → 43、`USR(2000000000)` → ` 2000000001 `（シャドウ再構築後も整数のまま下流に流れる）

ASM.BAS の RDLNUSR カーネル（M6 経路）は INT 引数で USR を呼ぶ：入り口では USRTYP=1／FACINT に引数が入り、戻りでは上記規約で型付き結果を返せる。カーネルが従来通り FAC だけを触る場合は FP 結果として扱われ、従来動作と一致する。

## 変更ファイル

- `redesign/parts/20-equates.asm` — USRTYP（$1F2）追加
- `redesign/parts/62-core-b2.asm` — SGN／INT／ABS／PEEK／VAL のディスパッチを _T 変種へ、FE_UF_T／FE_UFN_T 新設、SGNFN_I／INTFN_I／FABSFN_I ラッパ新設
- `redesign/parts/64-core-b3.asm` — Part 0 の NEXT 修正（NEXTRET 再スタック）、PEEKFN の SFLOAT32 化、VALFN への D10 コメント
- `redesign/parts/70-ext1.asm` — USR／DEEK／LEEK を FE_UFN_T へ、USRFN の D8 タグ規約、DEEKFN の SFLOAT32 化、LEEKFN の範囲分岐、WORDVAL 削除
- `redesign/run_rd.py` — 新規チェック 37 件（Part 0：10、M4：27）

phase1/ は無変更（コンマ NEXT の欠陥を含む。バックポートは Kyo の別判断）。

## 逸脱・驚き

1. **コンマ NEXT の欠陥は「コンマ検出」ではなく「戻りアドレスの喪失」だった**。CHRGOT のコンマ検出は正しく動いており、終了ケースだけが通るため一見「リスト形式が壊れている」ように見えた。継続ケースでのみ RTS がフレームバイトへ飛ぶ
2. **% 配列の実演算化（D7）は M1 で既に成立していた**。残件として残っていたのは監査と判別チェックの固定のみで、コード変更なし
3. **VAL("-2147483648") は FP**（上記 Part A に詳述）。FIN の絶対値解析の継承であり、リテラルの単項マイナスと同じ意味論
4. INT 0 の劣化（SFLOAT32 経由）は SGN(0) 等にも現れるが、従来通り観測同一（PRINT・代入とも FP 0 と区別不能）
