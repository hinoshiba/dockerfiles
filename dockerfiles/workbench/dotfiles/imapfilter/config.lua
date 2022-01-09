options.timeout = 120
options.subscribe = true

local account = IMAP {
    server = 'outlook.office365.com',
    username = 'username@example.com',
    password = 'password',
    ssl = 'ssl2',
}
account.INBOX:check_status()

----------------
-- filter     --
----------------
-- auto filter --
msg = account["INBOX"]:is_unseen() * (
	account["INBOX"]:contain_from("no-reply@mercari.jp") +
	account["INBOX"]:contain_from("support@getmimo.com") +
	account["INBOX"]:contain_from("info@ameba.jp") +
	account["INBOX"]:contain_from("appletvapp@new.itunes.com") +
	account["INBOX"]:contain_from("feedback@moneyforward.com") +
	account["INBOX"]:contain_from("sp_news@spmm.ameba.jp")
  )
msg:mark_seen()
msg:move_messages(account["00_SPAM"])

------ smap read------
msg = account["00_SPAM"]:is_unseen()
msg:mark_seen()
