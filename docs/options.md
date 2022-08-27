オプション詳細
===

引数オプションの説明です  

|オプション|説明|使用例|
|:---:|:---|:---:|
|`target=<name>`|原則必須オプションです。<br> 起動ターゲットを指定します。<br> [Dockerfileの格納PATH](../dockerfiles/) 名と一致するものが`name`に入ります。|`target=workbench`|
|`mount=<path>`|コンテナにマウントしたいpathをfull-path指定します。<br> コンテナの同一pathへ**書き込み有りで**マウントされます。|`mount=/var/service/work/`|
|`port=<port>`|コンテナからホストに解放したいポートを指定します。<br> `127.0.0.1:<port>` でホスト側から接続できるようになります。|`port=80`|
|`creater=<name>`|イメージの作成者タグに使用します。<br> 指定がない場合、環境変数`USER`値を使用します。|`creater=john`|
|`cname=<name>`|起動するコンテナ名を指定します。<br> 複数のコンテナインスタンスを起動したい時に使用します。|`cname=develop`|
|`autorm=n`|起動したコンテナの停止時自動削除オプションを無効化します。<br> 指定無し時は、自動削除が有効です。<br>値は見ていません。`autorm=y`であっても、`autorm=n`の挙動をします。|-|
|`daemon=n`|起動したコンテナのデーモンオプションを無効化します。<br> 指定無し時は、デーモンオプションが有効です。<br>値は見ていません。`daemon=y`であっても、`daemon=n`の挙動をします。|-|
|`root=y`|起動したコンテナのアタッチユーザをrootにします。<br> 指定無し時は、ローカルユーザのuidを用いてアタッチします。<br>値は見ていません。`root=n`であっても、`root=y`の挙動をします。|-|
|`cmd=<cmd>`|起動したコンテナで実行するコマンドを指定します。<br>コマンドへ引数を与える場合は、`cmd="<cmd> <arg1> <arg2>"`のように`"`で囲います。<br>デフォルトは、/bin/bashです。|`cmd="/usr/bin/init.sh run"`|

全て指定すると、以下のようなイメージになります。  
```bash
$ make target=workbench mount=/var/service/work port=80 creater=john cname=develop autorm=n daemon=n root=y cmd="/usr/bin/init.sh run"
```

# 使用例

### 起動中のコンテナの横に別インスタンスとしてテストイメージをトライアンドエラーしたい場合
```bash
$ make target=nginx port=80 cname=develop daemon=n root=y
```

`cname`の値を指定することで、既存インスタンスとは別に起動できます。  
加えて、`daemon=n` することで、確認後に即停止でき、自動削除され便利に扱えます。  
特別なイメージ出ない限り、制限されない`root=y`で実行すると幸せです。  


### 手元のpythonを雑に試したい
```bash
$ make target=python3 mount=/home/john/src/pythoncodes/
```

`root=y`オプションをつけないことにより、手元のソースコードに対する一時ファイルの作成などが、同一uidで実行でき、権限問題に悩まされなくなります。  
