# phase1 コンマ NEXT 修正 結果記録（2026-11-22）

redesign ツリーの R2-M4 Part 0 修正（`redesign-r2-m4-results.md`）の phase1 へのバックポート。Kyo の承認済みタイミング（R2-M6 後ではなく前倒し実施の判断はメイン側の引き継ぎに従う）。作業は phase1/ 内のみ。redesign/ は無変更。

## 根本原因の phase1 での確認

コード形状は redesign と同型（phase1 は原典サイズの **44 バイトフレーム**、INT フレーム無し）。`parts/64-core-b3.asm` の NX_EXIT が `LEA 44(A2),SP` で SP をフレーム上端までリセットするため、最上位フレームの直下（FORSP−4）に積まれた文ディスパッチの戻りアドレスが取り残される。コンマが続く場合、次の変数のループが継続するとループバックの `RTS`（NX_FD 経路末尾）が、内側フレームの先頭 4 バイトではなく外側フレーム先頭の 4 バイト（マーカー＋FORPNT 上位）を pop して暴走する。

修正前の実プローブ（ext-sim イメージ、格納プログラム＋RUN）で redesign と同一の症状分離を再現：

- 内側が終了し外側が継続する `NEXT J,I`（I: 1 TO 2、J: 1 TO 3、S を数える）→ **`?NF ERROR IN 20`**（本来 S=6）
- 両ループがコンマ段で同時に終了する `NEXT J,I`（I/J とも 1 TO 1）→ 正常（S=1）

CHRGOT によるコンマ検出自体は正しい（redesign 側の結論と同じ）。

## 修正（parts/64-core-b3.asm、NX_EXIT のコンマ分岐に 1 命令）

次の変数を処理する直前に、退避済みの戻りアドレスを積み直す。redesign の 52 バイト版と同一ロジックで、フレームサイズとコメントだけを phase1 に合わせた：

```
        MOVE.L  NEXTRET,-(SP)  ; NEXT-fix (backport of the redesign
                                ; tree's R2-M4 Part 0 fix): ...
        BRA     NX_GO
```

- 継続した場合：ループバックの RTS がこの複製を pop して正しく戻る（SP は FORSP に復帰）
- 終了した場合：その変数の NX_EXIT が再び SP をリセットするので、複製は元の戻りアドレスと同様に破棄される
- エラー（?NF 等）の場合：エラー処理が SP を丸ごと初期化するので無害

bare NEXT・単独 NEXT・不一致変数の ?NF・フレーム巻き戻しの意味論は不変。イメージは全フレーバーとも **+6 バイト**（MOVE.L 命令 1 個分）。

## サイズ／sum の変化（旧 → 新）

| フレーバー | 旧 | 新 |
|---|---|---|
| faithful sim（msbasic68k.bin） | 15,496 B / sum 23356 | **15,502 B / sum 21454** |
| faithful hw（msbasic68k-hw.bin） | 15,504 B / sum 58202 | **15,510 B / sum 7283** |
| ext sim（msbasic68k-ext.bin） | 16,530 B / sum 32550 | **16,536 B / sum 25401** |
| ext hw（msbasic68k-hw-ext.bin） | 16,538 B / sum 47886 | **16,544 B / sum 64252** |

faithful のピンは `build.py` の TARGETS と docstring、および `run_ext1.py` 内の参照値（docstring、faithful 照合チェック、gate 7 の復元チェック）を新値へ更新済み（旧ピンの履歴は build.py docstring に連記）。-c バナー変種も同じく +6 バイト（sim-c 15,564/42036、hw-c 15,572/10975、ext-sim-c 16,598/6729、ext-hw-c 16,606/34407）だが、元々ピン留め対象外。

## 新規回帰チェック（run_ext1.py の SESSION に 11 件）

redesign の Part 0 チェックの FP 形ミラー（phase1 に整数 FOR は無い）：

- ネスト FP `NEXT J,I`（外側継続、総和 9）
-  trip 数の異なるネスト `NEXT J,I`（総和 8）
- 3 重ネストを `NEXT K,J,I` で一括クローズ（総和 8）
- フレームの無い変数 `NEXT I,J` → `?NF ERROR IN 10` の保存
- ダイレクトモードのコンマ NEXT 一行実行（総和 9）
- 単独 NEXT＋bare NEXT の混在が従来通り（総和 4）

`run_m5d.py` 側には追加していない：あちらのセッションは CBM ゴールデンとのバイト比較が本旨で、コンマ NEXT は 68K 側セッション（run_ext1）が自然な置き場のため。共有コア（64-core-b3.asm）は両フレーバー共通で、ext 側のチェックがそのまま効く。

## ゲート結果（全て phase1 自身のスイート）

| ゲート | 結果 |
|---|---|
| `python3 build.py`（全フレーバー） | **PASS**（新ピンで byte-identity 成立） |
| `python3 run_m5d.py` | **116/118**（FAIL は既知の 1-ulp 2 件のみ：`PRINT 10^38; 2^31` と `COS(3.14159265)`） |
| `python3 run_ext1.py`（emu） | **141/141 PASS**（従来 130 + 新規 11） |
| `MSB_EMU=<emu_strict のフルパス> python3 run_ext1.py` | **141/141 PASS** |
| `python3 run_break.py` | **16/16 PASS** |
| `python3 run_hw.py` | **28/28 PASS**（HW: PASS） |
| ASCIIART ゴールデン | 各スイートで **バイト一致**（sum16 25584 / CRC32 0D6D8795） |

注：run_ext1.py の MSB_EMU はパスとして解釈されるため、スポットチェックでは emu_strict のフルパスを指定した（素の名前だと実行ファイルが見つからず即死する）。

## ファームウェア／GitHub への注意（重要）

**この修正は phase1 のソースとビルド成果物にのみ入っている。** ファームウェア配列の再生成、デュアルブートローダ（msbasic68k-hw-loader.bas / msbasic68k-hw-ext-loader.bas は build.py が再生成する DATA 埋め込みだが、ファーム側の組み込みイメージ自体）は本作業の範囲外で未実施。**実機ファームウェアと公開リポジトリ（github.com/kyo-ta04/EMUC68000-PGA2350B）は、Kyo が別途判断するまで修正前のビルドのまま**である。
