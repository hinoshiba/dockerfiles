dockerfiles
===

* 作業用コンテナをサクッと管理できるmakefileとその構成群
	* 各オプションは、makefileで支援
	* makefileは、同時に1つだけあげる、dockerfileやdokcerimage作成 or build環境としての支援のみを想定している

## 使い方

1. `<repository>/dockerfiles/<image name>/Dockerfile` を作成する
	* 含めるファイルがある場合は、`<repository>/dockerfiles/<image name>/files` 配下に入れておく
2. `make build target=<image name> [creater=<name>]` でbuildできる
	* 環境変数の、`http_proxy`, `https_proxy` を活用できるので必要に応じて設定しておく
	* `creater`を指定しない場合、環境変数の、`USER` の値が入る
		* 作成されるコンテナは、公開されている名前と被らないように`$USER/<image name>` か、`<creater>/<image name>` で作成される
3. `make run target=<image name> [creater=<name>] [root=y] [autorm=n] [mount=<path>]` で起動できる
	* `root=y`: uid, gidが、カレントユーザではなくrootで起動する。デフォルトは、uid, gidがカレントユーザになる
		* 引数オプション的に活用しているので、`root=n`であっても、`root=y`で動作する。値は関係ない
	* `autorm=n`: コンテナ停止後の自動削除を有効にする
		* 引数オプション的に活用しているので、`autorm=y`であっても、`autorm=n`で動作する。値は関係ない
	* `mount`: dockerのmountオプションのショートカット系。裏で`type=bind`で動作してくれる。src, dst のpathが同じ形になる
	* `make attach target=<image name>`
		* 起動済み同一コンテナに、アタッチする
4. `make clean target=<image name>`
	* イメージの削除を行う

### 特別な使い方: イメージ名: workbench

* 概要
	* 作業用コンテナを起動できます
	* カレントユーザを自動的にコンテナへ作成します
		* ENTRYPOINT で作成するので、イメージ上は反映されません
		* カレントユーザの環境変数ファイルをいくつかマウントもします
			* [ユーザ作成スクリプト ローカルマウントセクション一覧](../dockerfiles/workbench/add_local_user.sh#L33)
* 動作準備
	* 以下ディレクトリを掘る
		* `~/work/`
			* 作業データの共有を想定
		* `~/shared_cache/`
			* n回起動であっても保存が必要なキャッシュが保存される
				* e.g. histroyファイル, lockファイル, logファイル
		* gitの設定をしておく(`~/.gitconfig`)
		* gpgの準備をしておく(`~/gnupg`)
			* https://www.hinoshiba.com/public_docs/it/ope/create_gpg.html
			* https://www.hinoshiba.com/public_docs/it/ope/append_gpg_onGit.html

## リリース@dockerhub

1. builderの用意
	```
	docker buildx create --name <buildername>
	docker buildx use <buildername>
	docker buildx inspect --bootstrap
	```
2. login
	* `docker login`
3. build and push
	```
	docker buildx build --platform <platoform1,platoform2> -t <username>/<image name>:<version> --push ./dockerfiles/<image name>/.
	# docker buildx build --platform linux/arm64,linux/amd64,linux/386,linux/s390x,linux/arm/v7,linux/arm/v6 -t <username>/<image name>:<version> --push ./dockerfiles/<image name>/.
	```
4. logout
	* `docker logout`
1. tag付け対象削除
	* `docker rmi <username>/<image name>:<version>`
3. builderの削除
	```
	docker buildx use default
	docker buildx inspect --bootstrap
	docker buildx stop <buildername>
	docker buildx rm <buildername>
	```
