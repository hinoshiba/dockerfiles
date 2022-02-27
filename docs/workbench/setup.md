workbench 利用準備
===

# 1. 設定ファイルの設置

## 1.1. SSH設定ファイルの設置(`~/.ssh`)

## 1.2. PGPの設定(`~/.gnupg`)
* https://www.hinoshiba.com/public_docs/it/ope/create_gpg.html

## 1.3. gitの設定(`~/.gitconfig` の設置)
* https://www.hinoshiba.com/public_docs/it/ope/append_gpg_onGit.html

## 1.4. muttの追加設定の用意

1. `~/.muttrc.passwords.gpg` を作成する
	1. `~/.muttrc.passwords` を作成し、パスフレーズを登録する
		```
		set imap_pass="<password>"
		set smtp_pass="<password>"
		```
	2. PGPで暗号化する
		* `gpg -r <id> -e ~/.muttrc.passwords`
	3. 平文ファイルを削除する
		* `rm ~/.muttrc.passwords`
2. `~/.muttrc.add`
	* 基本設定
		```
		set imap_user = "<imap_user>"
		set ssl_starttls=yes
		set folder = "<imap_server>"
		set smtp_url = "<smtp_server>"

		set realname="<email address>"
		set from="<email address>"
		my_hdr Return-Path: <email address>
		```
	* PGP署名する場合は以下
		```
		set pgp_autosign = yes
		set pgp_replysign = yes
		set pgp_verify_sig = yes
		set pgp_timeout = 0
		unset pgp_strict_enc
		set pgp_sign_as="<key id>"
		```
3. `~/.muttrc.signature`
	* 任意の、メール末尾の文字列

# 2. 作業用ディレクトリを掘る

|path|説明|
|:---:|:---|
|`~/work/`|作業データの共有|
|`~/.shared_cache/`|n回起動であっても保存が必要なキャッシュが保存される|

# 3. docker設定の、キーbind変更

1. `~/.docker/config.json` へ、以下のエントリを追加する
	* `{ "detachKeys": "ctrl-\\" }`
