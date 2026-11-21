# コンテナ実行環境と workbench の互換性確認

`make target=workbench` は、対応する Apple silicon / macOS では Apple
`container` を優先し、それ以外では Docker を使用します。コンテナ内の OS は
これまでと同じ Linux / Ubuntu です。Dockerfile と配布する OCI イメージも共通です。

```sh
make target=workbench                       # ホストに応じて選択
make target=workbench engine=docker         # Docker を明示
make target=workbench engine=apple          # Apple container を明示
make target=workbench auto_install=n        # 実行環境の自動インストールを禁止
```

Apple container が未導入なら、Homebrew がある場合は `brew install container` を実行します。
Homebrew がない場合は、[Apple の最新 release](https://github.com/apple/container/releases/latest)
から署名済み installer package を取得します。配布 metadata に SHA-256 がある場合は照合し、
macOS の `pkgutil --check-signature` が成功した package だけを `installer` で導入します。
この場合は macOS の管理者パスワードが必要になることがあります。`auto_install=n` では
どちらの方法による導入も行いません。

Apple container は Docker daemon / Docker API の実装ではありません。
`engine=apple` は workbench 自体の実行環境を選びます。workbench 内の
`docker`、`docker compose`、devcontainers、言語テンプレートなどが利用する
Docker daemon は引き続き別途必要です。Apple と Docker のイメージ保管場所、
コンテナ一覧、ビルドキャッシュも別です。実行環境を切り替えた後は、その環境で
イメージを pull または build してください。

この変更の entrypoint を含むイメージを使用してください。公開イメージの更新前や
ソース変更の検証時は `make target=workbench localimg=y nocache=n` で手元からビルドできます。

## 共有ファイル・認証

| ホスト側 | コンテナでの用途 | アクセス |
| --- | --- | --- |
| `~/work`、`~/git` | 同じ絶対パスで作業 | 読み書き |
| `~/.shared_cache` | bash 履歴、Vim、screen の永続化 | 読み書き |
| `~/Downloads` | ダウンロードした資料の参照 | 読み取り専用 |
| `~/.ssh` | SSH 設定 | 読み取り専用 |
| `~/.ssh/known_hosts` | 接続先ホスト鍵の記録 | 読み書き |
| `~/.gnupg` 内の指定したファイル・ディレクトリ | GPG 鍵・信頼情報 | 読み取り専用 |
| `~/.gitconfig` | コンテナの Git 設定の初期値 | 読み取り専用 |
| `~/.docker.credential.gpg`、`~/.screen_layout` | Docker 認証・screen 設定 | 読み取り専用 |
| `~/.shared_ai_cache/.codex`、`.claude`、`.claude.json` | AI ツールの設定・認証・履歴 | 読み書き |
| `~/.shared_ai_cache` | workbench 内から起動する AI コンテナの状態・追加設定の検出。同じ絶対パスで共有 | 読み書き |
| `mount=<path>` | 任意の追加作業フォルダ | 読み書き |

Apple container の `--mount type=bind` は、1.0.0 ではファイルと Unix socket を
受け付けないため、共有には `--volume` を使用します。ホストの Unix socket は
仮想マシンとの通信として転送されます。
([Apple の mount parser](https://github.com/apple/container/blob/1.0.0/Sources/Services/ContainerAPIService/Client/Parser.swift),
[socket 転送実装](https://github.com/apple/container/blob/1.0.0/Sources/Services/RuntimeLinux/Server/RuntimeService.swift))

1Password の SSH Agent も通常の SSH Agent と同様に転送します。転送元は
`ssh_agent=<socket>` の明示指定、`ssh -G github.com` が返す使用可能な
`IdentityAgent`、`SSH_AUTH_SOCK` の順に選びます。これにより、macOS の標準 Agent と
1Password を併用している場合も GitHub 向けの設定を利用できます。別のホスト向けの
Agent を使う場合は `ssh_agent` を指定してください。
([1Password の Agent 設定](https://www.1password.dev/ssh/agent/compatibility))

Apple container では `--ssh` を使用し、コンテナ内の `SSH_AUTH_SOCK` は実行環境が設定します。
ホストの 1Password がロックされている場合や承認が必要な鍵は、通常どおりホストでの
解除・承認が必要です。鍵そのものをコンテナにコピーする必要はありません。
([Apple の SSH Agent 転送](https://github.com/apple/container/blob/1.0.0/docs/how-to.md#mount-your-host-ssh-authentication-socket-in-your-container))

検出した `IdentityAgent` のパスにも socket を転送するため、ホストの SSH 設定を
書き換える必要はありません。AI 用コンテナではホームパスを `/home/<user>` に、
workbench の `.ssh` 配下は共有先の `.host.ssh` に対応させます。ホストごとに異なる
複数の Agent を選択する設定は、利用する接続先それぞれで確認してください。

```sh
make target=workbench ssh_agent="$HOME/.1password/agent.sock"
make target=workbench docker_socket=/path/to/local/docker.sock
```

workbench 内から Docker コンテナを起動する場合、Docker daemon が参照できる
Agent socket が必要です。Apple の VM 内だけにある `SSH_AUTH_SOCK` は Docker
daemon から参照できないため、既定では従来の Docker Desktop 用
`/run/host-services/ssh-auth.sock` を使用します。別の Docker daemon を使用する場合は、
`docker_ssh_agent=/path/on/docker/host/agent.sock` でその daemon から見えるパスを指定します。
この情報は `DOCKERFILES_DOCKER_SSH_SOCK` として workbench とその子コンテナに引き継ぎます。

Docker Desktop 経由の転送は Desktop 側の Agent 設定を使用します。Apple 側の
`ssh_agent` を指定しても、Desktop 側の Agent が自動で同じものへ切り替わるわけではありません。
1Password の鍵が必要な場合は、workbench 内だけでなく、その先の Docker コンテナ内でも
`ssh-add -l` で確認してください。Agent を公開 TCP ポートへ中継することはありません。

`.ai-ignore` 用の一時マスクは、共有する `~/.shared_cache` 内に作成し、AI コンテナの
終了時に削除します。これにより Apple workbench 内から Docker を起動する場合も、
Docker daemon が同じ絶対パスのマスクを参照できます。

`docker_socket=n` を明示した場合だけ、コンテナ内の Docker 連携を無効にできます。
指定がない場合は必要な Docker daemon/socket が利用できなければ、原因を表示して
起動を止めます。

## ネットワークと端末の差異

`port=8000` は両方の実行環境でホストの `127.0.0.1:8000` に公開します。
コンテナ内のサービスは `0.0.0.0:8000` など、コンテナのネットワークインターフェイス
で待ち受けてください。コンテナ内の `127.0.0.1` はホストの localhost とは別です。

Apple container はコンテナごとに VM と IP アドレスを持ちます。Docker Desktop の
`host.docker.internal`、Docker のネットワーク名、Compose の名前解決をそのまま
Apple container に引き継ぐことはできません。ホストサービスへの接続にはホストの
到達可能な IP または Apple の DNS 設定を使用します。localhost 用 DNS の追加は
管理者権限が必要で、Private Relay にも影響するため、自動では変更しません。
([Apple のホストサービス接続手順](https://github.com/apple/container/blob/1.0.0/docs/how-to.md#access-a-host-service-from-a-container))

macOS 15 ではコンテナ間通信などの制限があるため、Apple container の自動選択対象は
macOS 26 以降です。Intel Mac と Linux は Docker を使用します。
([Apple の対応環境](https://github.com/apple/container#requirements),
[macOS 15 の制限](https://github.com/apple/container/blob/1.0.0/docs/technical-overview.md#macos-15-limitations))

対話起動と `attach` では TTY と標準入力を維持します。`make test` やリダイレクトされた
非対話実行では TTY のない環境も確認対象です。Docker の `detachKeys` 設定は Apple
container には適用されないので、普段の作業では `screen` の detach と、別端末からの
`make target=workbench` による追加シェルも確認してください。

## 回帰確認の一覧

以下は移行時・実行環境更新時の確認項目です。自動テストの成功だけで、1Password の
実際の承認操作やネットワークの個別設定まで検証済みという意味にはなりません。
実機確認はテスト用のコンテナ名と一時フォルダを使い、日常利用のコンテナと分けます。

| 分野 | 確認する動作 |
| --- | --- |
| 実行環境選択 | macOS / Linux、Apple silicon / Intel、自動選択と明示選択、未導入時と自動インストール無効時 |
| 起動・終了 | pull、build、start、追加 attach、stop、対象イメージだけの clean、終了コード |
| 既存オプション | `tag`、`creater`、`cname`、`localimg`、`daemon`、`autorm`、`root`、`cmd`、`work_dir`、`mount`、`port` |
| OS・ユーザ | Ubuntu、UID/GID、ホームパス、sudo、ja_JP.UTF-8、Asia/Tokyo、root 起動 |
| 端末 | TTY、端末サイズ変更、Ctrl-C、screen、別窓の追加 attach、標準入力・出力のパイプ |
| 共有フォルダ | ホスト→コンテナと逆方向の更新、作成したファイルの UID、空白入りパス、読み取り専用マウント |
| 設定・永続化 | Git 設定、known_hosts 更新、GPG 読み出し、bash 履歴、Vim 状態、screen ログ |
| SSH・1Password | Agent の socket、一般ユーザでの接続、鍵一覧取得、署名要求、ロック解除・承認、再 attach |
| ネットワーク | DNS、外部 HTTPS、ホストから公開ポートへの接続、ホストへの接続、コンテナ間通信 |
| Docker 連携 | workbench 内の `docker version`、`docker run`、`docker compose version`、テンプレート、devcontainers |
| Claude / Codex | 共有キャッシュ、ホストの既定設定を変更しないこと、`.ai-ignore`、起動前ビルド、追加引数、skills |
| ビルド | 両 runtime で同じ Dockerfile、バージョンタグと latest、proxy build args、キャッシュ指定 |
| コマンド・ツールチェーン | 既存の日常コマンド、Python 拡張モジュール、Node/npm、Go、Rust/clippy/rustfmt/rust-analyzer、Docker CLI/Compose |

```sh
# 実行環境を使わない launcher / runtime の回帰テスト
python3 -m unittest discover -s tests -p 'test_*.py'

# 実機での一回限りの起動例（runtime ごとに実行）
make test target=workbench engine=apple cmd='id'
make test target=workbench engine=docker cmd='id'

# 独立した対話確認用コンテナ
make target=workbench engine=apple cname=workbench-check
make stop target=workbench engine=apple cname=workbench-check
```

イメージ軽量化では、ビルド途中の Python ソース・成果物、パッケージキャッシュ、
重複する Node 配布物を除去する方針です。コマンドや toolchain の削減とは分けて扱い、
サイズ比較は同じアーキテクチャ・バージョン・圧縮条件で行います。

## Issue #308 の実機検証記録（2026-11-21）

Apple silicon / macOS 26.5.2 / Apple container 1.0.0 と、独立した検証用
Docker Engine 29.10.0（Linux arm64）で確認しました。

- `make check`: 102 件の回帰テストとシェル構文確認。
- 同じ workbench イメージで `tests/workbench-image-smoke.sh` が両 runtime とも成功。
  日常コマンド、Python 拡張、Rust / Go / Node、Docker CLI / Compose、locale を確認。
- Apple 側の実起動で UID/GID、sudo、空白を含むホーム・共有パス、Downloads の
  読み取り専用、known_hosts 更新、Git 設定、GPG の読み取り専用キーによる署名を確認。
- テスト専用 SSH Agent と鍵で、`IdentityAgent` の socket 別名経由のアクセスと
  Agent による署名・検証を確認。Apple が生成する socket のモード・親ディレクトリも修正。
- DNS・外部 HTTPS、localhost 公開ポート、Apple コンテナ間、VM gateway 上の
  ホストサービスへの接続を確認。TTY 初期サイズ・実行中のリサイズ・Ctrl-C、
  screen のセッション作成・一覧・終了も確認。非対話端末からのデーモン起動、
  初期化直後の追加 attach、停止・自動削除、root 起動も確認。
- Apple workbench 内から `docker version`、`docker compose version`、
  `docker run` とそのコンテナの外部通信を確認。Docker 側でも Make 経由のユーザ作成・sudo を確認。
- 同日の公開 arm64 workbench と比較して、PATH 内の実行可能コマンド名 754 個、
  インストール済みパッケージ名 289 個の削除はゼロ。圧縮イメージは約 1.025 GB から
  約 762 MB へ、約 25.6% 削減。Python の既存の不足だった bz2 / lzma / sqlite3 も修復。

1Password アプリ本体のロック解除・承認 UI、個人の実鍵による認証、利用者固有の VPN / DNS、
AI サービスへの実ログインはこの検証に含めません。自動インストールは既存環境を変更せず
モックで分岐・署名検証・失敗時の中止を確認しました。Docker Desktop 固有のネットワーク・
Agent 動作が必要な場合は `engine=docker` を使用できます。
