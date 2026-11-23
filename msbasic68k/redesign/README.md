# MS-BASIC 68K R2 — 再設計版（32 ビット整数型＋高速 GC）

`../`（phase1）の MS-BASIC 68K を土台に、言語と実行系を
再設計した版です。ファームウェアのブートメニューでは
`R` キーで起動します（既定は EhBASIC、`M` は phase1）。
実機確認は 2026-11-23：129024 BYTES FREE、ASCIIART が
sim 予測と一致する 148 秒 @6MHz で完走。

## 何が変わったか

土台（R1、設計は `redesign-r0-design.md`）：

- **A1 メモリモデル**：32 ビットフルアドレス。行テーブル
  （6 バイト×2,048 行、RUN のたび再構築）、変数検索の
  ハッシュ化、リテラルキャッシュ。129,024 BYTES FREE
- インタプリタのソース構成は phase1 と同じ parts/ 分割で、
  差分は設定パート（`10-config-rd.asm` / `10-config-rdhw.asm`）
  とコアへの型拡張

R2（型意味論の決定は `redesign-r2-decision-2026-11-22.md`）：

- **int32 整数型**：`%` 変数は 32 ビット整数（BASIC-80 の
  16 ビットからの意図的な逸脱）。数値は二重表現で保持し、
  FAC には常に正確な FP シャドウを持つため、整数が
  浮動小数点に化けても値が化けない
- 整数同士の `+` `-` `*` は整数演算（溢れは静かに FP へ昇格）、
  `/` は常に FP、`\` と `MOD` を追加、整数 FOR も可
- PEEK/DEEK/LEEK は整数を返し、USR には型タグ
  （USRTYP、論理アドレス $1F2）を渡す
- ネイティブ数値パック（MULU ベースの乗算ほか）で
  FP 演算も高速化

C1（GC 改善、`redesign-gc-design-2026-11-23.md`）：

- 文字列 GC を「全ディスクリプタ再走査」方式から、
  ワークリスト＋基数ソート＋単一スイープ方式へ。移動順序と
  最終配置は従来と同一（観測可能な挙動は不変）で、
  等価性ハーネス `run_gc_equiv.py` で旧版と照合済み

## 性能（ホスト sim、サイクル数）

| ワークロード | R2+C1（本版） | EhBASIC |
|---|---|---|
| ASM.BAS ボス フルラン | **125.2G** | 157.5G |
| ASCIIART | 883.2M | 652M |

ボス（EhBASIC 用アセンブラ ASM.BAS の自己アセンブル）では
EhBASIC を逆転。ASCIIART は FP 主体のため GC 改善の対象外で、
まだ EhBASIC が速い。FOR-NEXT のマイクロベンチは
`fornext-bench-2026-11-23.md`、C1 後のプロファイルは
`redesign-r3-profile-2026-11-23.md`。

## ビルド

要 asm68k-py（作者環境では `~/workspace/mc68000-selfhost/
asm68k-py/`、build.py がそのパスを参照）。

```
python3 build.py rd     # sim / 開発用イメージ
python3 build.py rdhw   # 実機ブートメニュー用 resident イメージ
```

両者とも **19,794 バイト / BSD sum 52171** で、内容は
バイト単位で同一（A1 レイアウトがそのまま基板のマップに
一致するため。監査は `redesign-hw-flavour-2026-11-23.md`）。
build.py 内にピン（サイズ＋sum）が埋め込まれており、
ずれたらビルドが失敗する。引数なしの一括ビルドには
phase1 由来の旧バリアントも含まれるが、ゲート対象は
rd / rdhw のみ。

生成物（`msbasic68k-rd.asm` 等の連結ソース、`.lst`、
`.c`）はリポジトリに含めていない。ビルドで再生成される。

## 検証スイート

要 Musashi ベースのホスト sim（作者環境では
`~/workspace/mc68000-selfhost/sim/` の `emu`）と、
`../golden/asciiart-output.txt`（同梱）。

```
python3 run_rd.py        # rd に対する 233 件のゲート
python3 run_rdhw.py      # 同一スイートを rdhw で
python3 run_gc_equiv.py msbasic68k-rd-prec1.bin msbasic68k-rd.bin
                         # GC 等価性：C1 前イメージ（同梱）と現行を照合
```

スイートの実行時生成物（`*.script` / `*.out`）は
リポジトリに含めていない。

## 記録

- `redesign-r0-design.md` — 再設計の設計（A1、型意味論の決定リスト）
- `redesign-r2-decision-2026-11-22.md` — R2 の決定事項
- `redesign-r2-m1-results.md` 〜 `redesign-r2-m5-results.md`
  — R2 マイルストーン M1〜M5（M6 フルランは受け入れ記録へ）
- `redesign-gc-design-2026-11-23.md` — GC 改善 C1 の検討
- `redesign-gc-c1-results-2026-11-23.md` — C1 実装と検証
- `redesign-r2-acceptance-2026-11-23.md` — R2 受け入れ記録（確定数字）
- `redesign-r3-profile-2026-11-23.md` — C1 後の再プロファイル
- `redesign-hw-flavour-2026-11-23.md` — 実機統合の監査と予測
- `fornext-bench-2026-11-23.md` — FOR-NEXT マイクロベンチ

R1 のマイルストーン記録や R2.5 検討、ボス実走の生
トランスクリプト等は作者のアーカイブ側にのみある。

## ライセンス

原典 microsoft/BASIC-M6502 は MIT ライセンスです。本再設計の
追加部分も同じ条件で公開します。
