# 共通 coding skills

このリポジトリを clone して Claude Code / Codex で開くと、コンテナを起動せずに
同じ `SKILL.md` を利用できます。登録用の個人設定やインストール操作は不要です。

## 配置

| 場所 | 用途 |
| --- | --- |
| `dockerfiles/claude-codex/skills/` | 編集する原本。イメージにも同梱 |
| `.agents/skills` | Codex のリポジトリ内 discovery。原本への相対 symlink |
| `.claude/skills` | Claude Code 用。`.agents/skills` への相対 symlink |
| `.codex/skills` | 同じ内容を参照する互換 alias |

リンクは clone / worktree の場所を移しても有効です。Git の symlink を保持して取得してください。
CLI の読み込み場所は [Codex 公式](https://learn.chatgpt.com/docs/build-skills) と
[Claude Code 公式](https://code.claude.com/docs/en/skills) に従います。
ほかの Agent Skills 対応ツールからも原本の `SKILL.md` を参照できますが、
そのツール固有の discovery 設定は必要に応じて行ってください。

## 収録内容

- [readable-code](../../dockerfiles/claude-codex/skills/readable-code/SKILL.md): 読みやすい命名と制御構造。
- [verify-deliverables](../../dockerfiles/claude-codex/skills/verify-deliverables/SKILL.md): 要求・成果物・検証結果の対応を確認。
  [元資料の検討記録](fable5-review.md) も公開しています。

## コンテナ内

`make target=claude` / `make target=codex` では、原本を `/opt/coding-skills` に同梱し、
起動のたびに各 skill を `~/.agents/skills/<name>`、`~/.claude/skills/<name>`、
`~/.codex/skills/<name>` へリンクします。従来の `~/.codex/coding-skills` も残します。
新しい skill は次回起動で追加されるため、以前の sentinel を消す必要はありません。
既存のユーザー所有ファイル・ディレクトリ・別リンクとの衝突時は、その設定を保持して通知します。

`~/.claude` / `~/.codex` は host の `~/.shared_ai_cache/` からマウントされます。
ホストの通常の `~/.claude` / `~/.codex` を変更しません。
`SKILLS_BOOTSTRAP=0` はコンテナの配線処理を停止します。
`SKILLS_REFRESH=1` は外部 plugin の再導入用で、ローカル skill の追加には不要です。
リポジトリ内の alias による読み込みにはこれらの環境変数は影響しません。

## 追加

リポジトリのルートで実行します。

```sh
cp -R docs/claude-codex/skill-template dockerfiles/claude-codex/skills/<skill-name>
# SKILL.md の name / description と本文を書き換える
make check
```

名前は小文字・数字・ハイフンで、ディレクトリ名と frontmatter の `name` を合わせます。
テンプレート・下書きは discovery 対象の外に置いてください。
原本の変更は alias とイメージの双方へ反映されます。
外部 marketplace plugin の導入は [標準 plugins](skills.md) を参照してください。
