claude-codex 標準skills (plugins)
===

`make target=claude` / `make target=codex` で起動する `claude-codex` イメージには、
起動時に「標準skills」として、Claude Code / OpenAI Codex の公式・準公式 plugin を
自動セットアップする仕組みを入れています。

> **用語の区別:** このページの「標準skills」は marketplace の **plugin** のことです。
> coding のノウハウを `SKILL.md` 形式で書き溜める **Agent Skills** は
> [coding-knowhow skills](./coding-skills.md) を参照してください。

## 何が入るか

コンテナ起動時 (`exec_user.sh` の `update_startup_tools`) に
[`setup_skills.sh`](../../dockerfiles/claude-codex/setup_skills.sh) が実行され、
以下を **冪等 (idempotent) かつ best-effort** で導入します。

### Claude Code 側

| plugin | marketplace (source) | 用途 |
| --- | --- | --- |
| `codex` | `openai/codex-plugin-cc` (OpenAI公式) | Claude Code から Codex を叩く。`/codex:review`, `/codex:adversarial-review`, `/codex:rescue`, `/codex:status` ほか |
| `security-guidance` | `anthropics/claude-plugins-official` (Anthropic公式) | コード生成と同時にセキュリティレビューを行う公式 plugin。injection / unsafe deserialization / 危険なDOM API / ハードコードされた secret などを検出 |

### Codex 側

| plugin | source | 用途 |
| --- | --- | --- |
| `cc-plugin-codex` | `sendbird/cc-plugin-codex` (Apache-2.0) | Codex から Claude Code を叩く。`$cc:review`, `$cc:adversarial-review`, `$cc:rescue`, `$cc:status` ほか |

> Codex 側は plugin ファイルの配置までを自動化します。Codex を初回起動したあと、
> Codex 内で一度だけ `$cc:setup` を実行して認証・配線を完了させてください。
>
> この `$cc:setup` は忘れやすいため、`make target=codex` で **Codex を起動する直前に
> 画面へリマインダーを表示**します（未完了のときのみ）。完了してリマインダーを消したい
> 場合は、コンテナ内で次を実行してください。
>
> ```sh
> touch ~/.codex/.cc-plugin-codex.ready
> ```

## メンテナンス継続性 (なぜ起動時セットアップなのか)

* コンテナ内の `~/.claude` / `~/.codex` は host の `~/.shared_ai_cache/` 配下 (`~/.shared_ai_cache/.claude`, `~/.shared_ai_cache/.codex`) からマウントされ永続化されるため、導入状態はホスト側に残ります。
	* host のデフォルトの `~/.claude*` / `~/.codex*` は使わないので、ホスト直の設定には影響しません。
* 起動のたびに `setup_skills.sh` を流すことで、plugin 集合を常に収束させます
  (導入済みなら高速に no-op)。
* イメージ自体は週次で再ビルドされ、`@openai/codex` と `claude` 本体は起動毎に更新されるため、
  基盤CLIも新しい状態を保てます。

これにより「公式の更新に追従しやすい形」で plugin を追加・維持できます。

## 制御 (環境変数)

`make` 実行時に環境変数で挙動を変えられます (Makefile が `docker run` へ引き渡します)。

```sh
# 標準skills のセットアップを完全に無効化する
SKILLS_BOOTSTRAP=0 make target=claude

# 既に導入済みでも強制的に再インストール / plugin update する
SKILLS_REFRESH=1 make target=claude
```

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `SKILLS_BOOTSTRAP` | `1` (有効) | `0` でこのセットアップを丸ごとスキップ |
| `SKILLS_REFRESH` | `0` | `1` で sentinel を無視して再インストール / 更新 |

冪等性のための sentinel:

* Claude: `~/.claude/.standard-skills.bootstrap`
* Codex: `~/.codex/.cc-plugin-codex.bootstrap`

このファイルを消すか `SKILLS_REFRESH=1` を付ければ再セットアップされます。

## 参照

* Claude Code Plugins: <https://code.claude.com/docs/en/plugins-reference>
* security-guidance (公式): <https://code.claude.com/docs/en/security-guidance>
* openai/codex-plugin-cc: <https://github.com/openai/codex-plugin-cc>
* sendbird/cc-plugin-codex: <https://github.com/sendbird/cc-plugin-codex>
* anthropics/claude-plugins-official: <https://github.com/anthropics/claude-plugins-official>
