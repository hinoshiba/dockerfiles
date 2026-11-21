オプション詳細
===

引数オプションの説明です  

|オプション|説明|使用例|
|:---:|:---|:---:|
|`target=<name>`|原則必須オプションです。<br> 起動ターゲットを指定します。<br> [Dockerfileの格納PATH](../dockerfiles/) 名と一致するものが`name`に入ります。|`target=workbench`|
|`tag=<version>`|起動ターゲットのバージョンを指定します。<br>デフォルトは、`latest`を指定します。自動生成されるバージョンは、`date '+%Y%U'`フォーマットで指定されています。|`tag=202301`|
|`mount=<path>`|コンテナにマウントしたいpathをfull-path指定します。<br> コンテナの同一pathへ**書き込み有りで**マウントされます。|`mount=/var/service/work/`|
|`port=<port>`|コンテナからホストに解放したいポートを指定します。<br> `127.0.0.1:<port>` でホスト側から接続できるようになります。|`port=80`|
|`creater=<name>`|イメージの作成者タグに使用します。<br> 指定がない場合、`hinoshiba`を使用します。|`creater=john`|
|`cname=<name>`|起動するコンテナ名を指定します。<br> 複数のコンテナインスタンスを起動したい時に使用します。|`cname=develop`|
|`autorm=n`|起動したコンテナの停止時自動削除オプションを無効化します。<br> 指定無し時は、自動削除が有効です。<br>値は見ていません。`autorm=y`であっても、`autorm=n`の挙動をします。|-|
|`daemon=n`|起動したコンテナのデーモンオプションを無効化します。<br> 指定無し時は、デーモンオプションが有効です。<br>値は見ていません。`daemon=y`であっても、`daemon=n`の挙動をします。|-|
|`root=y`|起動したコンテナのアタッチユーザをrootにします。<br> 指定無し時は、ローカルユーザのuidを用いてアタッチします。<br>値は見ていません。`root=n`であっても、`root=y`の挙動をします。|-|
|`cmd=<cmd>`|起動したコンテナで実行するコマンドを指定します。<br>コマンドへ引数を与える場合は、`cmd="<cmd> <arg1> <arg2>"`のように`"`で囲います。<br>デフォルトは、/bin/bashです。|`cmd="/usr/bin/init.sh run"`|
|`work_dir=<work directory>`|起動したコンテナが作業場所とするディレクトリを指定します。<br>dockerの-wと等しいです。|`work_dir=/var/service/work/`|
|`localimg=y`|localimgモードで動作します。docker pullをせず、手元のdockerfileをbuild, runします。<br>`cname=localhost creater=localhost`のaliasです。両方指定する場合、本オプションが優先されます。<br>値は見ていません。`root=n`であっても、`root=y`の挙動をします。|-|

全て指定すると、以下のようなイメージになります。  
```bash
$ make target=workbench mount=/var/service/work port=80 creater=john cname=develop autorm=n daemon=n root=y workdir=/var/service/work cmd="/usr/bin/init.sh run"
```

# 使用例

### 起動中のコンテナの横に別インスタンスとしてテストイメージをトライアンドエラーしたい場合
```bash
$ make target=python port=80 cname=develop daemon=n root=y
```

`cname`の値を指定することで、既存インスタンスとは別に起動できます。  
加えて、`daemon=n` することで、確認後に即停止でき、自動削除され便利に扱えます。  
特別なイメージ出ない限り、制限されない`root=y`で実行すると幸せです。  


### 手元のpythonを雑に試したい
```bash
$ make target=python mount=/home/john/src/pythoncodes/
```

`root=y`オプションをつけないことにより、手元のソースコードに対する一時ファイルの作成などが、同一uidで実行でき、権限問題に悩まされなくなります。  

## 実行環境の選択

| オプション | 説明 |
| --- | --- |
| `engine=auto` | 既定値。Apple silicon / macOS 26 以降は Apple container、それ以外は Docker |
| `engine=apple` / `engine=docker` | 使用する実行環境を明示。イメージとコンテナの保管先は別々 |
| `auto_install=n` | 未導入の Apple container の自動インストールを無効化。指定しなければ Homebrew 経由、Homebrew がない場合は Apple 公式の署名済み package で導入 |
| `ssh_agent=<socket>` | 転送元の SSH Agent を明示。1Password の Agent にも使用可能 |
| `docker_socket=<path>` | Docker/Compose 連携用の Unix socket を指定 |
| `docker_ssh_agent=<path>` | Docker daemon 側から見える SSH Agent socket。Apple workbench 内から起動する Docker コンテナへの Agent 転送元を指定 |
| `docker_socket=n` | Docker 連携を明示的に無効化。通常の workbench では指定不要 |
| `CONTAINER_MEMORY=4g` | Apple container の実行時メモリ。既定値 4 GiB |
| `CONTAINER_BUILD_MEMORY=4g` | Apple container のビルド時メモリ。既定値 4 GiB |

既存の `work_dir` と、上表に記載していた `workdir` はどちらも使用できます。
`creater` の既定値は `hinoshiba` です。`builder` は互換用の別名として使用できます。
`localimg=y` は選択した実行環境でビルドしてから起動し、pull は行いません。
`nocache=n` はビルドキャッシュを有効化します（従来どおり、未指定時は `--no-cache`）。
`autorebuild=n` は週番号の代わりに `latest` をビルドの世代識別に使用します。

workbench の `cmd` は従来どおり Bash のコマンドとして評価します。
`cmd='echo "$HOME"; id -u; echo "$$"'` のように外側を単引用符で囲むと、
`$` の式をホストや Make で展開せず、workbench 内のシェルへ渡せます。
他のターゲットでは引数として渡すため、パイプなどを使う場合は
`cmd="bash -c 'echo hello | cat'"` のようにシェルを明示してください。
詳細と検証範囲は [実行環境と互換性確認](./container-runtimes.md) を参照してください。
