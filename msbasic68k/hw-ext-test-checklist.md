# HW 実機テスト チェックリスト — MS-BASIC 68K 拡張版（M8 READY 修正済み）

2026-11-21 作成、2026-11-22 更新（FCOMP / PERFORM2 忠実度修正を反映して
全数字を再生成）。A（ローダ経由スモーク）→ B（デュアルブート・ファーム）の順。
数字はすべて sim 検証済み／ファイル直読みのものだけ。
※ Stage B は 2026-11-22 に旧イメージ（16,526 / sum 1982）で実機検証済み。
今回の更新はバグ修正2件のみ（+4 バイト）で、再書き込み後の確認は
起動＋ASCIIART＋USR の短縮版で足りる。

## A. ローダ経由スモークテスト（ファーム書き換えなし）

- 使うファイル：`msbasic68k-hw-ext-loader.bas`
  - イメージ 16,538 バイト、BSD sum **47886**（ローダ先頭の IMAGE 行と検証行で一致確認済み）
- 事前（コールドスタートのたびに）：
  1. `LOKE $844A,$30000`
  2. `CLEAR`
- ローダを投入して `RUN`
  - 期待：`LOAD OK - 16538 BYTES AT $30000, SUM 47886`
  - 失敗時：`LOAD FAIL: n MISMATCHES, SUM=...` が出る（そのまま CALL しない）
- `LOAD OK` が出てから `CALL $30000` を打つ
  - ⚠ **CALL は先行入力できない**。RUN 中は EhBASIC のブレークチェックが待機中の入力を食べてしまう
- 期待する起動表示：
  ```
  ### COMMODORE BASIC ###
   40960 BYTES FREE
  READY.
  ```
  （正規ローダは原典バナー1行。スクショ用3行バナー `-c` は別ローダ `msbasic68k-hw-ext-c-loader.bas`、16,600 バイト、sum **25420**）
- 時間の目安（@6 MHz、sim 実測 1.131e9 サイクル）：
  - `RUN` → MS-BASIC `READY.` まで **約 3 分（189 秒）**
  - 内訳：ローダ本体（DATA 16,534 個の POKE 一巡＋検証・sum の二巡目）188.5 秒 ＋ `CALL $30000` → バナー 0.5 秒
  - ASCIIART はさらに **約 224 秒**（6 MHz 実測系譜の値。旧記入の110秒は
    2026-11-21 のクロック訂正で撤回済み）、golden 一致が期待値。CTRL-C ブレークも効くはず
- 終了：MS-BASIC からは戻れない。**出口はリセット**（EhBASIC に戻る）

## B. デュアルブート・ファームのベンチ（本命・A が通ってから）

- ファームウェア配列は READY 修正＋FCOMP/PERFORM2 修正済み拡張イメージから再生成済み：16,530 バイト、sum **32550**（バナーは原典のまま）
- ビルド＆書き込みは Kyo 側
- 期待する起動：
  - メニュー 3 秒待ち → 何も押さなければ EhBASIC
  - `M` → MS-BASIC、**61440 BYTES FREE**、READY.
  - リセットでメニューに戻る

## 参考

- 仕様の根拠：`phase1/m7-ext1-results.md`「各項目の意味論と判断」（5 項目：&H / USR / DEEK・DOKE・LEEK・LOKE / INSTR / ELSE）
- 結果メモ：`phase1/m8-banner-ready-results.md`（全ゲート合格：run_ext1 130/130、run_break 16/16、ASCIIART 全変種 golden 一致）
