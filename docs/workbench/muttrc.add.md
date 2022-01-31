muttrcのaddについて
===

* `~/.muttrc.add`
* workbenchのmuttに加筆されます
	* 0行だと、muttrcが生えません
	* mountの都合で、使わない場合もファイル生やしておいてください
* 基本的に、以下のパラメータを設定できれば動くはずです

```
set imap_user = "username@example.com"
set imap_pass = "password"
set ssl_starttls=yes
set folder = "imaps://outlook.office365.com:993"
set smtp_url = "smtp://username@example.com@smtp.office365.com:587/"
set smtp_pass = "password"
set hostname = outlook.office365.com
set realname="username@example.com"
set from="username@example.com"
set use_from="yes"
set envelope_from="yes"
my_hdr Return-Path: username@example.com
```
