# M6 結果メモ ― ソース・ファクタリング（バイト同一ゲート）

MS-BASIC 68K 移植の単一ファイル `msbasic68k.asm`（5,667 行）を、
「これからのベース」としてバリアント生成と機械依存を継ぎ目で
分離した。書き直しではなく分離であり、受け入れゲート
（両バリアントのバイト完全一致＋全回帰従来通り）を全て満たした。

## 新しいファイル構成

ソースは `phase1/parts/` のパートファイル群が正本になった。

| パート | 役割 | 継ぎ目 |
|---|---|---|
| `00-header.asm` | ファイルヘッダ（履歴・規約）。バリアント中立 | レイアウト記述は config 側へ移し、ヘッダにはポインタだけ残した |
| `10-config-sim.asm` | 配置：SIM 変種（$0 イメージ） | レイアウトコメント＋変種依存 EQU 5 本（ZPBASE / TXTTABV / MEMSIZV / STACKTOP / FNTABV） |
| `10-config-hw.asm` | 配置：HW 変種（$30000 ランディングゾーン） | 同上（HW 値） |
| `20-equates.asm` | EQU 一式（バリアント非依存） | ACIA、サイズ（BUFLEN / DSCLEN / ZPSIZE）、仮想 ZP スロット、トークン値 |
| `30-entry-sim.asm` | エントリ：SIM 変種 | ORG $000000＋リセットベクタ対（SSP / PC） |
| `30-entry-hw.asm` | エントリ：HW 変種 | ORG $030000＋HWENTRY スタブ（CALL $30000 入口） |
| `40-core-a.asm` | インタプリタ本体 A | STMDSP / RESLST / INIT / 主ループ / 文 / エラー処理。機械層の直前まで |
| `50-machine.asm` | 機械層 | MONCOUT / MONRDKEY / MONPOLKEY / ISCNTC / BRKCHK＋PUSHBK、CRDO / STROUT、PRTDEC / DIV10 |
| `60-core-b.asm` | インタプリタ本体 B | M3 浮動小数点コア以降（M4 / M5 節を含む）〜 END |

- パート境界は既存のセクション境界に合わせた。特に機械層は
  本体内の元の位置のまま切り出してあり（移動していない）、
  ルーチンの分割・改名・並べ替えは一切していない。
  原典 microsoft/BASIC-M6502 との対応コメントもそのまま残る。
- 分割前の単一ファイルは `phase1/archive/msbasic68k-v1.5-singlefile.asm`
  に参照用として保存した。

## バリアント選択の方法

- ビルド入口は `phase1/build.py` に統一した。
  `python3 build.py` で両変種、`build.py sim` / `build.py hw`
  で片方を生成する。
- 変種は config パートと entry パートの**選択**で決まる。
  build.py が
  `00-header → 10-config-<変種> → 20-equates → 30-entry-<変種>
  → 40-core-a → 50-machine → 60-core-b`
  の順に連結し、GENERATED バナーを付けて統合ソース
  （`msbasic68k.asm` / `msbasic68k-hw.asm`）を書き出し、
  asm68k-py でアセンブルする。統合ソースは生成物なので
  編集対象はパート側。
- 旧 `build_hw.py` の文字列書き換え（アンカ置換）は**廃止**した。
  同名ファイルは run_hw.py が名前で呼ぶための薄いシムとして残し、
  `build.py hw` へ委譲する（終了ステータスも伝播）。
  HW 変種のレイアウトアサーションとローダ（.bas）生成は
  build.py 側へ移植した。
- asm68k-py の INCLUDE は採用しなかった。pass0 の INCLUDE は
  テープスロット前提のプロトタイプ機構（INCLUDE_MAP 固定）で
  汎用のファイル INCLUDE ではなく、将来の ASM.BAS 自己
  アセンブル（INCLUDE を持たない）とも相性が悪いため。
  連結方式なら統合ソース自体が従来通りの ASM.BAS サブセット
  単一ファイルとして残る。

## 受け入れゲート結果

### バイト完全一致（分割前ゴールデンと cmp）

| 生成物 | 結果 |
|---|---|
| `msbasic68k.bin` | **一致**（15,492 バイト、BSD sum 32584） |
| `msbasic68k-hw.bin` | **一致**（15,500 バイト、BSD sum 5542） |
| `msbasic68k.c` / `msbasic68k-hw.c` | 一致（副次確認） |
| `msbasic68k-hw-loader.bas` | 一致（副次確認） |
| `.lst` | アドレス／バイト列は一致。差分はソース行番号のみ（パートヘッダ分のずれ） |

### 全回帰（従来通り）

| テスト | emu | emu_strict |
|---|---|---|
| run_m1 | 9/9 PASS | PASS（exit 0） |
| run_m2 | 13/13 PASS | PASS（exit 0） |
| run_m3 | 33/33 PASS | PASS（exit 0） |
| run_m4 | 32/32 PASS | PASS（exit 0） |
| run_m5a | 65/65 PASS | 65/65 PASS |
| run_m5b | 81/81 PASS | 81/81 PASS |
| run_m5c | 111/111 PASS | 111/111 PASS |
| run_m5d | **116/118**（下記） | **116/118**（下記） |
| run_hw | **28/28 PASS** | （両 emu を内包） |
| run_break | **16/16 PASS** | （両 emu を内包） |

- run_m5d の FAIL 2 件は既知の 1-ulp 差分のみで、従来と同一：
  (1) `2^31` の表示末尾 1 桁（…365 vs …366）、
  (2) `COS(3.14159265)`（-.999999999 vs -1）。
  新規差分はゼロ。run_m5d の exit 1 はこの 2 件による設計通り。
- 分岐チェッカ：run_hw 内で check_branches.py /
  check_short_branches.py とも **0 bad**。
  sim 側も run_m4〜m5d / run_break 内蔵のチェッカが全て PASS。

### ファーム用配列

`~/workspace/msbasic-68k/firmware/msbasic68k.c` は、
ファクタリング後の `msbasic68k.bin` から `gen_msbasic68k.py`
で再生成しても `.h` ともども**バイト同一**になることを確認した。
よってファーム側の配列はそのまま有効（差し替え不要）。

## 運用メモ

- 編集は `parts/` に対して行い、`python3 build.py` してから
  run_*.py を回す。run_*.py は従来通り `msbasic68k.asm` を
  直接アセンブルするので、パート編集後はビルドを挟むこと
  （統合ソース先頭の GENERATED バナーが目印）。
- run_hw.py は無改造で通る（build_hw.py シム経由）。
