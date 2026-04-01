# 故障排查

## 1. `25` 端口没监听

检查：

```bash
ss -ltn '( sport = :25 )'
sudo systemctl status postfix --no-pager
```

## 2. `/admin/mails` 查不到邮件

检查：

```bash
sudo systemctl status temp-mail --no-pager
curl http://127.0.0.1:8000/health
sqlite3 /opt/temp-mail/data/temp_mail.db 'select id,address,subject,created_at from mails order by rowid desc limit 10;'
```

## 3. `unknown user` 或邮件被 bounce

通常是 Postfix catch-all 没配好。检查：

```bash
postconf myhostname
postconf virtual_alias_domains
cat /etc/postfix/virtual_alias_regexp
grep '^tempmail:' /etc/aliases
```

## 4. `codex-console` 接不上

检查 `temp_mail` 配置里的：

- `domain`
- `base_url`
- `admin_password`

## 5. DNS 看起来不对

先对照这份文档：

- [DNS 配置说明](./dns-setup.md)

检查：

```bash
dig temp-mail.example.com A +short
dig temp-mail.example.com MX +short
```

## 6. 一次性查看整体状态

```bash
sudo /opt/temp-mail/scripts/post_deploy_report.sh
```

这会把 DNS、端口、systemd、API、SQLite、Postfix 配置一起打出来。
