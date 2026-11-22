# M8 結果メモ ― 行毎 READY. 修正とバナー・バリアント

2026-11-21。Kyo のスクリーンショット用途の 2 変更：
(1) 番号付き行を格納するたびに再表示されていた READY. を原典
（CBM BASIC 2）の挙動に戻す（M1 時代のハーネス同期都合で決め
打ちした既知の原典差異。2026-11-20 に Kyo が「害は無いので
後でもいいよ」と保留していた修正を今回実施）。
(2) スクショ用バナー・バリアント（2 行目に COPYRIGHT 行）を
追加。忠実フレーバーのバナーは原典のまま不変。
（同日追記：Kyo の選択で 3 行目 `PORTED FROM 6502 TO MC68000`
を追加し、バナーは 3 行になった。-c 系の数値は追記後の値。）

## 結論

- **全ゲート合格**：通常 emu／emu_strict の両方で
  run_m5d 116/118（既知の 1-ulp 2 件のみ、従来通り）、
  run_break 16/16、run_ext1 130/130、run_hw 両 emu 通過。
  ASCIIART の golden バイト一致は全変種で不変。
- 変更 1 はサイズ中立（分岐先ラベルの変更のみ）で、全バイナリ
  のサイズは従来通り。BSD sum のみが新値になった。
- バナー・バリアントは全行 CRLF を実出力で確認（下記）。

## 変更 1：新仕様の定義

対象は `parts/44-core-a3.asm` の READY/MAIN のみ（結合ソースの
差分はこの 1 箇所だけであることを diff で確認済み）。

- READY. は **READY 入口でのみ**表示する：起動時、ダイレクト
  コマンド実行後、RUN/END/STOP の復帰時、エラー復帰時。
- 番号付き行の格納後はプロンプトを出さず MAIN（行入力）へ
  戻る（`STORE` 後の `BRA READY` → `BRA MAIN`）。
- 空行・スペースだけの行でも再表示しない（`BEQ READY` →
  `BEQ MAIN` ×2）。
- 原典の MAIN ループが READY 表示の下側に再入する構造と一致。
  格納後の状態リセットは STORE 内の RUNC→CLEARC が従来通り
  担う（CONT 不可化もそちらで処理済み）。

### ハーネスの更新

| スクリプト | 更新内容 |
|---|---|
| run_m1.py | READY. 出現回数の期待を 4 → **3**（起動・NEW 後・エラー後。空行は再表示なし）に変更、docstring も更新 |
| run_m3.py / run_m4.py / run_m5a.py / run_hw.py | payloads 系パーサに「数字で始まる行＝格納行、応答なし（payload ""、次エコーが直後に続く）」の規則を追加 |
| run_m5b.py / run_m5c.py / run_m5d.py / run_break.py | regions68 系は格納行を元々明示処理しており**無変更**で通過 |
| run_ext1.py | 格納行だった ("C", "10 A=1" / "10 A=0", 期待 "\r\nREADY.\r\n") の 2 件を ("L", …, None) に再分類。チェック総数が 132 → **130** になったのはこの 2 件分（格納行にはもう応答リージョンが無いため） |
| run_ext1.py / build.py / gen_msbasic68k.py | 忠実フレーバーの基準 size/sum を新値に更新 |

### テスト結果（全て従来通りの合否）

| ゲート | 通常 emu | emu_strict |
|---|---|---|
| run_m1〜m5c（m5d のカスケード内） | 全 exit 0 | 全 exit 0 |
| run_m5d | 116/118（既知 ulp 2 件のみ） | 116/118（同左） |
| run_hw（内部で両 emu） | PASS | （同左） |
| run_break | 16/16 | 16/16 |
| run_ext1 | 130/130 | 130/130 |

ASCIIART：run_m4（sim 忠実）、run_hw（hw 忠実、両 emu）、
run_ext1（ext-sim / ext-hw / ext-hw-strict）の全てで golden
（2,025 バイト、sum16 25584、CRC32 0D6D8795）とバイト一致。

## 変更 2：バナー・バリアント

- バナー定義を `parts/64-core-b3.asm` からパート対に切り出し：
  `65-banner-o.asm`（原典：`### COMMODORE BASIC ###` のみ）と
  `65-banner-c.asm`（バリアント）。残りは `66-core-b4.asm`。
  -o 選択時の結合ソースは切り出し前とテキスト同一（変更 1 の
  差分を除く）であることを確認済み。
- バリアントのバナー（1・2 行目は MEZ6502 版で Kyo が採用した
  のと同じ文面・形式。3 行目は 2026-11-21 に Kyo が候補から
  選択した出自表示）：
  ```
  ### COMMODORE BASIC ###
  COPYRIGHT 1977 BY MICROSOFT CO.
  PORTED FROM 6502 TO MC68000
  ```
  その下に BYTES FREE 行が従来通り続く。バナー増分は原典比
  +62 バイト（COPYRIGHT 行 +33、PORTED 行 +29）。
- **改行は全行 CRLF**。4 バリアント全てを実際に起動し、出力が
  `### COMMODORE BASIC ###\r\nCOPYRIGHT 1977 BY MICROSOFT CO.\r\nPORTED FROM 6502 TO MC68000\r\n 61440 BYTES FREE\r\n`
  （hw 系は 40960）となること、単独 CR／単独 LF が無いことを
  確認した（MEZ6502 の CR のみバナーで Tera Term 表示が崩れた
  事故の再発防止）。原典バナー版の出力に COPYRIGHT 行が無い
  ことも併せて確認。3 行目追加後、sim 系 2 変種では ASCIIART
  の golden バイト一致も再確認済み。
- 選択は build.py のバリアント名で行う（下表）。忠実フレーバー
  のバナーは -o のみで、従来通り原典のまま。

## 全バイナリ一覧（フレーバー × 配置 × バナー）

| バリアント名 | ファイル | サイズ | BSD sum | ローダ |
|---|---|---:|---:|---|
| sim（忠実・$0・原典） | msbasic68k.bin | 15,492 | **32410**（旧 32584） | ― |
| sim-c（忠実・$0・COPYRIGHT） | msbasic68k-c.bin | 15,554 | 22366 | ― |
| ext-sim（拡張・$0・原典） | msbasic68k-ext.bin | 16,526 | **1982**（旧 33635） | ― |
| ext-sim-c（拡張・$0・COPYRIGHT） | msbasic68k-ext-c.bin | 16,588 | 37826 | ― |
| hw（忠実・$30000・原典） | msbasic68k-hw.bin | 15,500 | **17566**（旧 5542） | msbasic68k-hw-loader.bas |
| hw-c（忠実・$30000・COPYRIGHT） | msbasic68k-hw-c.bin | 15,562 | 16058 | msbasic68k-hw-c-loader.bas |
| ext-hw（拡張・$30000・原典） | msbasic68k-hw-ext.bin | 16,534 | **18919**（旧 12581） | msbasic68k-hw-ext-loader.bas |
| ext-hw-c（拡張・$30000・COPYRIGHT） | msbasic68k-hw-ext-c.bin | 16,596 | 38803 | msbasic68k-hw-ext-c-loader.bas |

ビルド方法：`python3 build.py`（引数なしで全 8 種）、または
`python3 build.py sim-c` のようにバリアント名を 1 つ指定。
BYTES FREE は不変（sim 系 61440、hw 系 40960）。hw 系の
ZPBASE は従来通り（忠実 0x34000、拡張 0x34400）で、バナー
増分 +62 バイトでも配置アサーションは全て通過。

## 付随作業

- ファームウェア配列 `firmware/msbasic68k.c` / `.h` を、変更 1
  反映済みの拡張フレーバー（バナーは原典）で再生成：
  `gen_msbasic68k.py --bin ../phase1/msbasic68k-ext.bin
  --expect-size 16526 --expect-sum 1982` → 生成 C からの
  逆抽出でバイト完全一致と sum 1982 を自己検証済み。
- hw の正規ローダ（忠実 `msbasic68k-hw-loader.bas`、拡張
  `msbasic68k-hw-ext-loader.bas`）は build.py が新バイナリから
  再生成済み（内蔵の IMAGE 行と検証 sum も新値）。
  バリアント用ローダ 2 種も併せて生成された。
