# メンテナ向けメモ

このリポジトリを直すときの注意。プラグインを使うだけの人には関係ない。

## 正本は作者の手元

正本は作者の手元（`~/.claude`）にある。このリポジトリは、その中から他の人にも配る価値があるものを選んで写した配布用の写し。

- `coding-loop/skills/coding-loop/SKILL.md` ← `~/.claude/skills/coding-loop/SKILL.md` の写し
- `coding-loop/agents/worker.md` ← `~/.claude/agents/worker.md` の写し

直すときは手元を先に直し、使って確かめてからこのリポジトリへ写す。写しだけを直さない。手元で試している途中のものは写さない。

`SKILL.md` は手元と同じ内容で写せる。作業役の名前は、どちらでも通じる書き方（`worker`、このプラグイン経由なら `coding-loop:worker`）にしてある。`worker.md` も手元と同じ内容で写せる。

## 進め方の指示（毎セッションに載るもの）

`coding-loop/hooks-handlers/session-start.sh` に、進め方の指示を JSON の 1 行として埋め込んでいる。中身は手元の `~/.claude/rules/` にある次の 3 本と同じ趣旨だが、別の形なので写しても自動では揃わない。

- `delegate-work.md`（手作業は作業役に委譲する）
- `ask-user-question.md`（質問は選択式にする）
- `memory-policy.md`（プロジェクト固有の情報はプロジェクト内に置く）

これらのルールを直したら、`session-start.sh` も直す。環境に依存する記述（サブエージェントのモデル指定、nodenv、worktree の運用）は配布物に入れない。

## 確認

このリポジトリを直したら次を実行する。

- `python3 -m json.tool` で `.claude-plugin/marketplace.json` と各 `plugin.json`、`coding-loop/hooks/hooks.json` が通ること
- `bash coding-loop/hooks-handlers/session-start.sh | python3 -m json.tool` が通ること
- `coding-loop/skills/coding-loop/SKILL.md` が 120 行・10240 バイト以内であること
- `SKILL.md` と `worker.md` が手元の同名ファイルと `diff` で一致していること
