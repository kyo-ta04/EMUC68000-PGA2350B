# MS-BASIC 68K移植 Phase 1 / M1 結果（2026-11-18）

結論: **M1 出口条件 PASS**。`python3 run_m1.py` で再実行可能（アセンブル→sim 実行→判定まで一括）。

## 成果物

- `msbasic68k.asm` — M1 ソース（537 バイトにアセンブル、$0000–$0218）
- `run_m1.py` — 検証スクリプト（入力: 空行 → NEW → FOO、全て CR 終端）
- 副産物: `msbasic68k.bin` / `.c` / `.lst`、`m1.script` / `m1.out`

## 採用配置（sim イメージ用）

| 領域 | アドレス | 備考 |
|---|---|---|
| コード | $000000– | リセットベクタ $0=SSP / $4=PC で起動 |
| 仮想ゼロページ | $010000 | 使用 $011F バイト |
| TXTTAB | $020000 | プログラム領域 |
| MEMSIZ | $02F000 | 文字列領域はここから下向き |
| スタックトップ | $030000 | 初期 SSP |

ZP ミラーは原典（m6502.asm 730–942 行、REALIO=3 配置）の**並び順と前半オフセットを維持**（CHARAC=$0A、ENDCHR=$0B、…、BUF=$17）。ポインタスロットは 68K のアドレスが 16 ビットに収まらないため 2→4 バイトに widening し、TXTTAB 以降のオフセットはその分ずらしてソース先頭コメントに一覧表を明記した。主要ポインタ（TXTTAB/VARTAB/ARYTAB/STREND/FRETOP/FRESPC/MEMSIZ）と TXTPTR は EQU で命名。TXTPTR は M1 ではメモリスロット保持とし、レジスタ保持 CHRGET 化は M2 で行う（キックオフメモからの意図的な先送り）。

原典 INIT は RAM プローブで MEMSIZ を決めるが、sim のメモリマップは固定なので MEMSIZV からの設定に置き換えた（実機移植時に再検討）。

## トランスクリプト実物（m1.out、改行を可視化）

```
### COMMODORE BASIC ###\r\n
 61440 BYTES FREE\r\n
\r\nREADY.\r\n
\r\n              <- 空行のエコー（CR→CRLF）
\r\nREADY.\r\n
NEW\r\n           <- 入力エコー
\r\nREADY.\r\n
FOO\r\n           <- 入力エコー
?SN ERROR\r\n
\r\nREADY.\r\n
```

BYTES FREE の 61440 は MEMSIZ($02F000) − TXTTAB($020000) の実計算値で、PRTDEC（32 ビット 10 進化）経由で表示している。

## 出口条件の判定（run_m1.py の自動判定、全 PASS）

- バナーと BYTES FREE が出る: PASS
- READY. が出る（計 4 回＝初期・空行後・NEW 後・エラー後）: PASS
- 入力エコーが返る（NEW / FOO とも CRLF 付きで確認）: PASS
- NEW の後に READY. が再表示される: PASS
- FOO に対して ?SN ERROR が出て READY. に戻る: PASS
- emu 終了コード 0（--until "?SN ERROR" 到達）: PASS

行入力の仕様: CR で確定、CRLF をエコー。LF は無視（CR 正の行末規律どおり）。BS/DEL は 1 文字消去（BS・空白・BS をエコー）。バッファ長 128、満杯時は呑み込む。

## 実装したもの

- INIT: ZP ミラー全域クリア、TEMPPT 初期化、SCRATCH、CURLIN=$FFFF（ダイレクトモード、原典準拠）、バナー表示
- SCRATCH（NEW の実体）: TXTTAB/VARTAB/ARYTAB/STREND/FRETOP/FRESPC/MEMSIZ 再初期化、テキスト先頭バイト 0
- 機械層 3 プリミティブ: MONCOUT（TDRE ポーリング、全レジスタ保存）、MONRDKEY（RDRF ポーリング、ブロッキング）、ISCNTC（非ブロッキング、Z フラグで有無を返す）
- STROUT（NUL 終端文字列出力）、PRTDEC＋DIV10（DIVU 2 段による 32 ビット ÷10）

## 踏んだ問題と対処

1. **asm68k-py が EVEN 擬似命令に未対応**（unhandled opcode でアセンブルエラー）。文字列定数をファイル末尾に置く構成だったため、単に除去して解決。配置上の実害なし。
2. **DIV10 のバグで BYTES FREE が「061440」と表示された**。原因は SWAP＋CLR.W で上位ワードを取り出す際、CLR.W が下位ワードを消すため取り出すワードを取り違え、剰余が落ちていたこと。ANDI.L #$0000FFFF でマスクする形と、合成側を MOVE.W 一発に直して修正。「61440」で正しく表示されることを確認。16 ビット超の値（例: 1000000）でも机上検証済み。

## M2 への引き継ぎ

- TXTPTR のレジスタ保持化と CHRGET サブルーチン化は M2 のトークナイズと同時に行う。
- NEW の照合は現在「NEW」完全一致のみ（前後空白や小文字は ?SN ERROR 行き）。トークナイザが入る M2 で原典準拠に置き換わる前提の仮実装。
- LOAD/SAVE は未着手（M2 でスタブ予定、Phase 1 スコープ外）。
