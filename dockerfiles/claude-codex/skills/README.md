coding-knowhow skills (Agent Skills)
===

`make target=claude` / `make target=codex` で起動する `claude-codex` イメージへ、
**coding のノウハウを書き溜めておくための置き場所** です。
ここに置いた skill は、コンテナ起動時に Claude Code / Codex 双方から使える場所へ
自動で配線されます。

> **注意 (用語):**
> このディレクトリの「skills」は、Claude が手順・知識を必要に応じて読み込む
> [Agent Skills](https://code.claude.com/docs/en/skills) (`SKILL.md` 形式) のことです。
> 起動時に導入する marketplace の **plugin** (`codex` / `security-guidance` 等) を指す
> [標準skills (plugins)](../../../docs/claude-codex/skills.md) とは別物です。

## 形式

1 skill = 1 ディレクトリ + `SKILL.md`。

```
skills/
├── README.md                 # このファイル
├── _template/
│   └── SKILL.md              # 雛形 (`_` 始まりは配線対象外)
└── <skill-name>/
    └── SKILL.md              # ノウハウ本体
```

`SKILL.md` は YAML frontmatter + 本文 (Markdown) で書きます。

```markdown
---
name: <skill-name>
description: この skill が何をするもので、いつ使うのか。Claude はこの一文で
  呼び出すか判断するため、トリガー (対象言語・作業・キーワード) を具体的に書く。
---

# 本文: 具体的な手順・規約・チェックリスト・注意点を書く
```

## 収録済み skill

| skill | 内容 |
| --- | --- |
| [`readable-code`](./readable-code/SKILL.md) | 可読性重視のコーディング規約 (自明なコメント排除 / 目的コメント / ガード節による早期リターン / 正常系を浅いインデントへ / 複雑なワンライナー回避 / 意味のある命名) |

## 追加のしかた

```sh
cp -r _template <skill-name>
$EDITOR <skill-name>/SKILL.md   # frontmatter の name を <skill-name> に合わせる
```

- `<skill-name>` は kebab-case (小文字・ハイフン)。ディレクトリ名と frontmatter の
  `name` を一致させる。
- `_` または `.` で始まるディレクトリ (`_template` 等) は雛形・下書き扱いで、
  コンテナへは配線されません。
- ノウハウは repo に入るので、追加・更新は **PR レビュー** を通して共有されます。

## どうやって Claude / Codex に届くか

* イメージビルド時に、このディレクトリが `/opt/coding-skills` へ焼き込まれます
  (`Dockerfile` の `COPY ./skills`)。
* コンテナ起動時に [`setup_skills.sh`](../setup_skills.sh) が best-effort / 冪等で配線します。
	* **Claude Code**: 各 skill を `~/.claude/skills/<name>` へ symlink。Claude が
	  personal skill として自動発見します。
	* **Codex**: 同じツリーを `~/.codex/coding-skills` から参照できるようにします。
* 内容を変更すると `dockerfiles/claude-codex/` 配下の差分としてイメージが再ビルドされ、
  週次の再ビルドでも取り込まれます。

## 制御 (環境変数)

[標準skills (plugins)](../../../docs/claude-codex/skills.md) と同じスイッチを共有します。

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `SKILLS_BOOTSTRAP` | `1` | `0` で skills 系のセットアップを丸ごとスキップ |
| `SKILLS_REFRESH` | `0` | `1` で sentinel を無視して再リンク |

冪等性のための sentinel: `~/.claude/.coding-skills.bootstrap`
(消すか `SKILLS_REFRESH=1` で再配線)。

## 参照

* Agent Skills: <https://code.claude.com/docs/en/skills>
* このリポジトリでの説明: [docs/claude-codex/coding-skills.md](../../../docs/claude-codex/coding-skills.md)
