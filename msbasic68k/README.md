# MS-BASIC 68K — Microsoft BASIC の MC68000 移植

Microsoft が 2025 年に MIT ライセンスで公開した 6502 版 BASIC の
公式ソース（microsoft/BASIC-M6502、CBM BASIC 2 相当）を、MC68000 へ
移植したものです。6502 版の ROM イメージをゴールデンとして、
出力がバイト単位で一致することを検証しながら移植しました
（受け入れ試験は Mandelbrot 描画プログラム ASCIIART.BAS）。

ファームウェア本体からはブートメニューで選択して起動できます
（起動後 3 秒以内にキー入力。`M` = 本ページの MS-BASIC 68K、
`R` = 再設計版 R2（`redesign/`）、それ以外またはタイムアウトで
EhBASIC）。統合の詳細は `firmware/dualboot-integration.md` を
参照してください。
2026-11-22 に実機で確認済み：メニュー選択、61440 BYTES FREE、
ASCIIART の出力がゴールデンとバイト一致（約227 秒 @6MHz）、
CTRL-C ブレーク、無入力タイムアウトでの EhBASIC 起動。
2026-11-23 にトリプルブート化し実機で確認済み：`M` で
61440 BYTES FREE とコンマ NEXT のスモークテスト
（`NEXT J,I`）合格、`R` で 129024 BYTES FREE、ASCIIART が
148 秒 @6MHz（ホスト sim の予測 147.2 秒と一致）。

## 拡張（EXT1）

原典の言語仕様を保ったまま、MS Extended BASIC の流儀で以下を追加：

- `&H` 16 進リテラル（符号なし、最大 &HFFFFFFFF）
- `USR`（ベクタは論理アドレス $334、POKE 820/821 で設定）
- `DEEK / DOKE / LEEK / LOKE`（奇数アドレス可、ビッグエンディアン）
- `INSTR`、`ELSE`

仕様の根拠は `m7-ext1-results.md`。

## 再設計 R2（`redesign/`）

phase1 を土台に、32 ビット整数型（int32、二重表現）と
32 ビットメモリモデル（A1）、高速化した文字列 GC（C1）を
備えた再設計版です。ブートメニューの `R` キーで起動します。
ASM.BAS ボスのフルランではホスト sim で EhBASIC を上回り
ました（125.2G vs 157.5G サイクル）。詳細は
`redesign/README.md`。

## フォルダ構成

- `parts/` — アセンブリソース（パート分割、ビルドで連結）
- `build.py` — ビルド入口。8 バリアント（忠実版 / 拡張版 ×
  $0 配置 / $30000 配置 × 通常バナー / スクリーンショット用 -c バナー）
- `run_*.py` — 検証スイート（Musashi ベースのホスト sim が必要）
- `msbasic68k-hw-*-loader.bas` — EhBASIC 上から $30000 版を
  読み込むためのローダ（ファーム書き換えなしの導入経路）
- `hw-ext-test-checklist.md` — 実機テスト手順
- `m*-results.md` — 各マイルストーンの検証記録
- `next-comma-fix-results.md` — コンマ NEXT 修正の記録
  （phase1 へのバックポート）
- `redesign/` — 再設計版 R2（ソース、ビルド、検証記録）
- `golden/` — ASCIIART のゴールデン出力
  （`redesign/` のスイートが参照）
- `firmware/` — ブート統合メモ、配列生成スクリプト、diff

## ライセンス

原典 microsoft/BASIC-M6502 は MIT ライセンスです。本移植の
追加部分も同じ条件で公開します。帰属表示は原典のものを
保持してください。

## 既知の事項

- 数値演算は原典の 5 バイト浮動小数点をそのまま移植しているため、
  速度は EhBASIC の約 1/2（ASCIIART 実機比較）です。
- 忠実版には原典の癖も残しています（数値 PRINT の末尾スペース等、
  詳細は各 results メモ）。
- 2026-11-22 に、原典ゴールデンとの照合で見つかった比較演算の
  バグ 2 件（FCOMP の符号違いパス、PERFORM2 のマスク破壊）を
  修正しました。経緯はソース内コメントと本リポジトリ外の
  移植記録にあります。
- コンマ NEXT（`NEXT J,I` のような複数変数 NEXT）が壊れて
  いたのを 2026-11-22 に修正しました（再設計側で先に直した
  もののバックポート）。経緯は `next-comma-fix-results.md`。
  現在のイメージはすべて修正済みです。
