# Everything Claude Code (ECC)

`claude-codex` の起動時に [Everything Claude Code](https://github.com/affaan-m/ECC)
を Claude Code の native plugin として初期設定します。旧 URL
`affaan-m/everything-claude-code` は現在 `affaan-m/ECC` に転送されます。
plugin ID は `ecc@dockerfiles-ecc` です。

skills・commands・agents は plugin の名前空間で利用でき、既存の
`~/.claude/skills` やリポジトリの `CLAUDE.md`、rules を置き換えません。
Codex 用の外部 installer や Git hooks は自動実行しません。
既存の共通 coding skills は従来の bootstrap が別途配置します。

## バージョンとインストール

- 対象: [v2.2.3](https://github.com/affaan-m/ECC/releases/tag/v2.2.3)
  （2026-10-01 公開、導入時の 14 日 cooldown を満たす）。
- 固定 commit: `c05b2d6614f62f6db0047669aa4eefb223d478f9`。
- helper: `dockerfiles/claude-codex/setup_ecc.sh`。
- 保存先: `~/.claude/dockerfiles-ecc/` と Claude が管理する plugin cache。
  `CLAUDE_CONFIG_DIR` を設定している場合は、そのディレクトリを使います。

専用の local marketplace に GitHub plugin source の `ref` と `sha` を指定します。
Claude が取得する **plugin 本体** の checkout を固定しており、可変な `main` を
起動のたびに取り込みません。これは Claude の
[marketplace schema](https://code.claude.com/docs/en/plugins/marketplace-reference)
にある正式な source 形式です。上流の `install.sh` や npm installer を経由せず、
`claude plugin marketplace add` と `claude plugin install` を使います。

初回の通信に失敗した場合は警告を出してシェル起動を継続し、次の起動で再試行します。
全処理が成功した場合だけ commit を含む完了印を保存します。
通常の再起動では通信や CLI を再実行しません。
同じ永続ディレクトリを複数のコンテナが共有する場合は、bootstrap を排他制御して
plugin 設定や依存モジュールの更新が競合しないようにします。

## 自動 hooks

ECC v2.2.3 の hooks には、Bash 操作の制限、編集ファイルの自動整形・型チェック、
操作観測とセッション情報のローカル保存などがあります。普段の開発操作を変えるため、
新規導入時は native CLI の `--config hooks_enabled=false` でこれらの自動処理を
無効にします。skills・commands・agents は利用できます。

確認した実装は固定 commit の
[hooks 登録](https://github.com/affaan-m/ECC/blob/c05b2d6614f62f6db0047669aa4eefb223d478f9/hooks/hooks.json)、
[hook 有効判定](https://github.com/affaan-m/ECC/blob/c05b2d6614f62f6db0047669aa4eefb223d478f9/scripts/lib/hook-flags.js)、
PreToolUse/PostToolUse/lifecycle の dispatcher、フォーマット・観測処理です。
`hooks_enabled` が native plugin option として各 dispatcher の有効判定に渡ることを
確認しています。plugin 全体の安全性を保証する監査ではありません。

ユーザーがすでに設定した `hooks_enabled`、hook profile、plugin の disabled 状態は
維持します。hooks を使いたい場合は、上流の動作を確認してからコンテナ内で設定できます。

```sh
printf '%s\n' '{"hooks_enabled":"true","hook_profile":"minimal"}' |
  claude plugin configure ecc@dockerfiles-ecc --values-stdin
```

Claude を再起動すると適用されます。戻す場合は `hooks_enabled` を `"false"` にします。
利用する CLI の詳細は [native plugin commands](https://code.claude.com/docs/en/plugins/cli-reference)
を参照してください。`--config` 等を持たない古い Claude では導入に失敗し、完了印を残さず
次回再試行します。

## 付属 MCP と追加依存

上流の [.mcp.json](https://github.com/affaan-m/ECC/blob/c05b2d6614f62f6db0047669aa4eefb223d478f9/.mcp.json)
には `npx -y chrome-devtools-mcp@1.10.1` で起動する Chrome DevTools MCP が含まれます。
これは hooks の設定と独立しており、plugin が有効な Claude セッションでは
[自動的に接続・起動](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers)
されます。ブラウザー操作には Chrome 等の実行環境が別途必要です。
必要がなければ Claude の `/mcp` パネルで当該サーバーを無効にできます（プロジェクト単位）。
bootstrap は上流 plugin のソース・MCP 定義や、他の MCP 設定を変更しません。

Claude 2.1.330 の native dependency installer は上流 `package.json` の `overrides`
に未対応のため、その段階では npm dependencies が未導入になります。これは
[パッケージ管理の制約](https://code.claude.com/docs/en/plugins/loading#limits-on-the-dependency-install)
であり、bootstrap が `sql.js`、`ajv`、`js-yaml`、`@iarna/toml` の runtime dependencies を
補完します。state store・context profile 等を使うための手動セットアップは不要です。

補完前に native install record の commit/path と `package.json`・`package-lock.json`
の SHA-256 を検証します。専用 staging directory で
`npm ci --omit=dev --ignore-scripts --no-audit --no-fund` を実行し、4 つの直接依存を Node で
ロードできた場合だけ `node_modules` を配置します。npm の user/global config は分離し、
上流のソース、lockfile、hooks、MCP、Claude の設定を変更しません。
失敗した場合は既存の `node_modules` を保持し、完了印を残さず次回に再試行します。

固定 lockfile の production 依存は推移依存を含め 9 パッケージです。npm registry の
公開日時と integrity を確認済みで、最も新しいものは `fast-uri@3.1.7`
（2026-09-02 公開）です。全件が 14 日 cooldown を満たし、取得元と integrity は lockfile
で固定します。開発用依存、lifecycle scripts、上流の installer は実行しません。

## 起動時の制御

| 環境変数 | 動作 |
| --- | --- |
| `ECC_BOOTSTRAP=0` | ECC の初期設定・更新をスキップ |
| `SKILLS_BOOTSTRAP=0` | ECC を含む skills 初期設定全体をスキップ |
| `SKILLS_REFRESH=1` | 固定 commit の marketplace/plugin を再確認・更新 |

`SKILLS_REFRESH=1` でも未確認の最新リリースへは進みません。新バージョンの採用には
helper の固定値の更新と hooks の再確認が必要です。
opt-out はすでに導入済みの plugin を削除・無効化する操作ではありません。
利用自体を止める場合は `claude plugin disable ecc@dockerfiles-ecc --scope user` を使います。

手動導入済みの `ecc@ecc` または旧
`everything-claude-code@everything-claude-code` が存在する場合は、その設定を優先して
追加・更新しません。`dockerfiles-ecc` という名前に別の marketplace が登録されている
場合も、上書きせず失敗を通知します。

## 検証

```sh
python3 -m unittest discover -s tests -p 'test_ecc_bootstrap.py' -v
bash -n dockerfiles/claude-codex/setup_ecc.sh
```

テストは空白を含む一時 HOME と fake CLI で実行し、実ユーザーの設定やネットワークへ
アクセスしません。固定 source、初回の hooks 無効化、既存設定の保持、再試行、refresh、
opt-out、別 marketplace の保護を検証します。

2026-11-21 に macOS arm64 の実 Claude CLI 2.1.330 でも、一時 HOME と独立した
`CLAUDE_CONFIG_DIR`、認証環境変数を引き継がない環境で次を確認しました。
CLI は公式 native 配布から取得し、manifest の SHA-256 とコード署名を確認しています。

- helper による native install が成功し、`installed_plugins.json` の `gitCommitSha` が
  固定 commit と一致。
- 取得された plugin manifest、hooks、MCP 設定、有効判定の実装が確認済み source と一致。
- `plugin configure --json` の `hooks_enabled` が `false`。
- 通常の再起動が設定を変更せず、`SKILLS_REFRESH=1` も固定版のまま成功。
- ユーザーが明示した hook 設定、disabled 状態、既存 permissions/env が refresh 後も保持。
- Node 26.13.1 / npm 11.20.0 で production 依存 9 パッケージの補完に成功。
  TOML/YAML の parse、Ajv の validate、sql.js の in-memory SQLite query が成功し、
  plugin source・lockfile・Claude settings は変更されていないことを確認。
  `plugin list --json` にあった dependencies-refused note も解消。
- `plugin validate` が exit 0。上流 `CLAUDE.md` は plugin のプロジェクト context としては
  自動読込されない旨の warning があり、これを含めてユーザーの既存 `CLAUDE.md` を維持。

LLM 呼び出しや実セッション、MCP サーバー・Chrome の起動は行っていません。
Linux コンテナ内の実セッションと上流の個別ワークフローは別途検証が必要です。
