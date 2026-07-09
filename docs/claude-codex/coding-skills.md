claude-codex coding-knowhow skills (Agent Skills)
===

`make target=claude` / `make target=codex` で起動する `claude-codex` イメージには、
**coding のノウハウを書き溜めておく置き場所** を用意しています。
ここに置いた skill は、コンテナ起動時に Claude Code / Codex 双方が使える場所へ
自動で配線されます。

> **用語の区別:**
> このページの「skills」は、Claude が必要に応じて読み込む
> [Agent Skills](https://code.claude.com/docs/en/skills) (`SKILL.md` 形式) のことです。
> 起動時に導入する marketplace の **plugin** を指す
> [標準skills (plugins)](./skills.md) とは別物なので混同しないでください。

## 置き場所

[`dockerfiles/claude-codex/skills/`](../../dockerfiles/claude-codex/skills/) が
バージョン管理された唯一の source of truth です。1 skill = 1 ディレクトリ + `SKILL.md`。

```
dockerfiles/claude-codex/skills/
├── README.md         # 書き方・追加手順
├── _template/        # 雛形 (`_` 始まりは配線対象外)
│   └── SKILL.md
└── <skill-name>/
    └── SKILL.md      # ノウハウ本体
```

追加のしかたや `SKILL.md` の書式は
[skills/README.md](../../dockerfiles/claude-codex/skills/README.md) を参照してください。
ノウハウは repo に入るので、追加・更新は **PR レビュー** を通して共有されます。

## どうやって Claude / Codex に届くか

1. イメージビルド時に `skills/` が `/opt/coding-skills` へ焼き込まれます
   ([`Dockerfile`](../../dockerfiles/claude-codex/Dockerfile) の `COPY ./skills`)。
2. コンテナ起動時に [`setup_skills.sh`](../../dockerfiles/claude-codex/setup_skills.sh)
   の `setup_coding_skills` が **best-effort / 冪等** で配線します。
	* **Claude Code**: 各 skill を `~/.claude/skills/<name>` へ symlink。
	  Claude が personal skill として自動発見します。
	* **Codex**: 同じツリーを `~/.codex/coding-skills` から参照できるようにします。
3. `skills/` 配下を変更すると `dockerfiles/claude-codex/` の差分としてイメージが
   再ビルドされ、週次の再ビルドでも取り込まれます。

`~/.claude` / `~/.codex` は host の `~/.shared_ai_cache/` 配下からマウントされ
永続化されるため、配線状態はホスト側に残ります。

## 制御 (環境変数)

[標準skills (plugins)](./skills.md) と同じスイッチを共有します。

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `SKILLS_BOOTSTRAP` | `1` (有効) | `0` で skills 系のセットアップを丸ごとスキップ |
| `SKILLS_REFRESH` | `0` | `1` で sentinel を無視して再リンク |

冪等性のための sentinel: `~/.claude/.coding-skills.bootstrap`
(このファイルを消すか `SKILLS_REFRESH=1` を付ければ再配線されます)。

## 参照

* Agent Skills (公式): <https://code.claude.com/docs/en/skills>
* 置き場所と書式: [skills/README.md](../../dockerfiles/claude-codex/skills/README.md)
* 標準skills (plugins): [skills.md](./skills.md)
