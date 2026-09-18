# cc-plugins

Claude Code 向けの自作プラグインを配布するマーケットプレイス。入っているのは `coding-loop`（推奨）と `loop-eng`（非推奨。coding-loop に移行）の 2 つ。

## coding-loop（推奨）

コードを書く・直す依頼で自動で使われる進め方。スキル 1 本と作業役エージェント 1 体だけの軽い構成。導入と中身は `coding-loop/README.md` を見る。loop-eng を使っている場合は、coding-loop を入れて loop-eng を外す（両方入れると二重に発火する）。スキル・作業役エージェント・進め方の指示がすべて含まれているので、入れれば環境が揃う。

## loop-eng（非推奨）

coding-loop に移行しました。以下は loop-eng を使い続ける場合の説明です。

- Claude Code のバージョンが 2.1.154 以上であること(`claude --version` で確認する)
- 有料プランであること
- Pro プランの場合は `/config` を開き「Dynamic workflows」を自分でONにする(OFFのままだと workflow が動かない)
- 組織(Team/Enterprise)が `disableWorkflows` で無効化している場合、workflow は使えない

## 導入手順

1. `/plugin marketplace add ryo-takahashi1218/cc-plugins`
2. `/plugin install loop-eng@cc-plugins`
3. `/reload-plugins`
4. **(必須)** `/plugin` を開き、Marketplaces タブから `cc-plugins` を選び、自動更新をONにする
   - 自作(サードパーティ)のマーケットプレイスは自動更新が既定でOFFになっている。この手順を飛ばすと、改良した内容がいつまでも届かない。

## 更新の届き方

- セッション開始後、最大10分のランダムな遅延で更新が取得される
- 反映されるのは `/reload-plugins` を実行したとき、または次回 Claude Code 起動時

## 入っているもの

- スキル `loop-engineering`(「実装して」「直して」等の依頼で自動起動する)
- スラッシュコマンド `/loop-eng:review-loop`(レビューと修正を指摘0件になるまで自動で往復する)
- エージェント `loop-eng:reviewer`(厳格レビュー専任)
- エージェント `loop-eng:fixer`(指摘を1件ずつ最小修正する)
- エージェント `loop-eng:implementer`(計画を受けてテスト先行で実装する役)
- エージェント `loop-eng:coding-orchestrator`(重い依頼を最初から最後まで回す司令塔。合格条件づくり・進め方の判断・完成判定を担い、自分ではコードを書かず上の役に委譲する)
- workflow `loop-eng:loop-engineering-large-A`(多ファイル・重い仕様のときだけ使う大規模向け)
- `rules/common/testing.md`(レッド→グリーンのテスト方針。同梱の役が参照する資料)
- `rules/common/predicate-writing.md`(合格条件の書き方。同梱の役が参照する資料)

## 使い方

「実装して」「直して」等の依頼をすると、スキルが自動で起動し、合格条件づくり → テスト先行 → 実装 → レビュー往復 → 完了判定、という流れで進む。

## リポジトリの構成

- `.claude-plugin/marketplace.json` — マーケットプレイス定義(このリポジトリに入っているプラグイン一覧)。直下に置く
- `coding-loop/` — 推奨プラグイン本体(スキル・作業役エージェント・進め方の指示)
- `loop-eng/` — 非推奨プラグイン本体(スキル・スラッシュコマンド・エージェント・workflow・同梱資料)

メンテナ向けの注意は `MAINTENANCE.md` にある。
