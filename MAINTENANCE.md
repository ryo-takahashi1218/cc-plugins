# メンテナ向けメモ

このリポジトリを直すときの注意。プラグインを使うだけの人には関係ない。

## 正本の場所

次の 2 ファイルは、このリポジトリが正本。作者の手元（`~/.claude`）からはシンボリックリンクで参照している。片方だけ直すということが起きない。

- `coding-loop/skills/coding-loop/SKILL.md` ← `~/.claude/skills/coding-loop`（ディレクトリごとリンク）
- `coding-loop/agents/worker.md` ← `~/.claude/agents/worker.md`

直すときはこのリポジトリのファイルを編集する。手元で編集しても同じファイルを触ることになる。

リンクの向き先が変わるので、このリポジトリで作業するときはブランチを直接切り替えず、worktree を使う。切り替えると作業中のセッションのスキル内容が変わる。

## 進め方の指示（毎セッションに載るもの）

`coding-loop/hooks-handlers/session-start.sh` に、進め方の指示を JSON の 1 行として埋め込んでいる。中身は作者の手元の `~/.claude/rules/` にある次の 3 本と同じ趣旨だが、別ファイルなので自動では揃わない。

- `delegate-work.md`（手作業は作業役に委譲する）
- `ask-user-question.md`（質問は選択式にする）
- `memory-policy.md`（プロジェクト固有の情報はプロジェクト内に置く）

これらのルールを直したら、`session-start.sh` も直す。環境に依存する記述（サブエージェントのモデル指定、nodenv、worktree の運用）は配布物に入れない。

直したあとは `bash coding-loop/hooks-handlers/session-start.sh | python3 -m json.tool` が通ることを確認する。

## 確認

プラグインを直したら次を実行する。

- `python3 -m json.tool` で `.claude-plugin/marketplace.json` と各 `plugin.json`、`coding-loop/hooks/hooks.json` が通ること
- `bash coding-loop/hooks-handlers/session-start.sh | python3 -m json.tool` が通ること
- `coding-loop/skills/coding-loop/SKILL.md` が 120 行・10240 バイト以内であること
