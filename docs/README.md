dockerfiles
===

作業用コンテナをサクッと管理できるmakefileとその構成群  

## 基本的な使い方

1. `<repository>/dockerfiles/<image name>/Dockerfile` を作成する
	* 含めるファイルがある場合は、`<repository>/dockerfiles/<image name>/files` 配下に入れておく
2. `make target=<image name>`
	* build時に、環境変数の、`http_proxy`, `https_proxy` を活用できるので必要に応じて設定しておく
		* それらの変数は、起動後のコンテナには引き継がれない
	* オプションについては、[オプション詳細](./options.md) を確認
3. 作業を行う
	* 別窓が必要になった場合、`make target=<image name>` で追加attachができる
4. `make stop target=<image name>`
	* イメージの停止を行う
		* 各種コンテナは、デフォルトで、daemonモード、rmオプション有効で起動するので、データ削除に注意
5. `make clean target=<image name>`
	* イメージの削除を行う

### 特別な使い方: イメージ名: workbench

* 概要
	* 作業用コンテナを起動できます
	* カレントユーザを自動的にコンテナへ作成します
		* ENTRYPOINT で作成するので、イメージ上は反映されません
		* カレントユーザの環境変数ファイルをいくつかマウントもします
			* [ユーザ作成スクリプト ローカルマウントセクション一覧](../dockerfiles/workbench/exec_user.sh#L30)
	* docker outside docker がいじれるようにしてあります。mountのpathは、host側のpathになるので気をつけてください
* 利用準備
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
* アップデート
	* `make target=workbench cname=develop` のように、コンテナ名オプションを活用することで、編集場所と同時に起動できます。アップデート確認できます
* 便利なセットアップ
	* `alias work='cd ~/git/github.com/hinoshiba/dockerfiles && make target=workbench'` を、host側の.bashrcに登録することで、workコマンドで一発起動


## リリース@dockerhub

本環境で作成して、最終的にdockerhubへアップロードする際の手順  

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
