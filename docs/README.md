dockerfiles
===

作業用コンテナをサクッと管理できるmakefileとその構成群  

## 基本的な使い方

1. `<repository>/dockerfiles/<image name>/Dockerfile` を作成する
	* 含めるファイルがある場合は、`<repository>/dockerfiles/<image name>/files` 配下に入れておく
2. `make target=<image name>`
	* build時に、環境変数の、`http_proxy`, `https_proxy` を活用できるので必要に応じて設定しておく
		* それらの変数は、起動後のコンテナには引き継がれない
	* build時には、週単位でtagがつき、latestが更新される
		* 強制的に古い環境を利用する場合は、`start attach` で個別起動し、`TAG`オプションでバージョンを指定
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
* [利用準備](./workbench/setup.md) をした環境で利用できる
* 編集
	* `make target=workbench localimg=y daemon=n` のように、オプションを指定することで、localモードで動作しつつ、debugが容易
* 便利なセットアップ
	* `alias work='cd ~/git/github.com/hinoshiba/dockerfiles && make target=workbench'` を、host側の.bashrcに登録することで、workコマンドで一発起動

abcdefg
