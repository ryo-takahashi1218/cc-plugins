# coding-loop

コードを書く・直す依頼（「実装して」「直して」「機能を追加して」「バグを直して」）で自動で使われる進め方です。スキル 1 本と、実際にファイルを書く作業役エージェント 1 体だけで動きます。

## 何をするか

1. 依頼の大きさで強さを決めて 1 行で宣言する。A（フル）・B（ミニ）・C（省略）。迷ったら一段下げ、お金・認証・データが絡めば上げる。
2. 利用者から見える変化があれば、実装より先に `features/<機能名>.feature` に振る舞い（Scenario）を書く。
3. A では合格条件（VISION）を `docs/vision/` に書き、全文を見せて承認を得る。
4. 作業役に「失敗するテスト → 赤の確認 → 最小実装 → 緑 → verify」を任せ、赤と緑の実行ログを受け取る。
5. ビルトインの code-review で往復し、本番に影響する不具合と利用者に見える不具合だけ直す。止まったら simplify を 1 回かける。
6. verify・ID ごとのテスト・assert の中身・実物の動作を順に確かめ、`~/.claude/logs/coding-loop.tsv` に 1 行記録する。

## 前提

- Claude Code の最新版。ビルトインの `code-review`・`simplify`・`run` スキルと AskUserQuestion が使えること。
- ネット接続や外部の CLI は要らない。Dynamic workflows の設定も要らない。

## 導入

1. `/plugin marketplace add ryo-takahashi1218/cc-plugins`
2. `/plugin install coding-loop@cc-plugins`
3. `/reload-plugins`
4. `/plugin` の Marketplaces タブで `cc-plugins` の自動更新を ON にする（自作マーケットプレイスは既定で OFF）。

## loop-eng から移る場合

- `/plugin uninstall loop-eng@cc-plugins` で外す。両方入っていると「実装して」で 2 つのスキルが同時に発火する。
- 秘書エージェントをコピーして使っている場合、その仕分け表にある implementer・coding-orchestrator・fixer・reviewer は不要になる。コードの作業は coding-loop に任せ、秘書からはそれらの呼び出しを外す。
- プロジェクト側の `features/` と `docs/vision/` はそのまま使える。

## 入っているもの

- スキル `coding-loop`（自動で発火する）
- エージェント `coding-loop:worker`（ファイルを書く作業役。指示された範囲だけ変更し、赤→緑の証拠を報告する）

## 記録

1 回の作業ごとに `~/.claude/logs/coding-loop.tsv` に 1 行足される。列は、日付、プロジェクト、強さ、Scenario の要否、赤を見たか、レビュー回数、直した指摘の件数、結果、備考。後から「この進め方が効いているか」を数えるためのもので、無ければ自動で作られる。
