# Ubuntu 单机部署说明

## 目标路径

本项目默认部署到：

- `/opt/temp-mail`
- `/opt/temp-mail/data`
- `/opt/temp-mail/data/temp_mail.db`
- `/opt/temp-mail/venv`

## 1. 克隆代码

```bash
git clone <your-repo> /opt/temp-mail
cd /opt/temp-mail
cp .env.example .env
```

## 2. 修改 `.env`

至少改这些：

```env
TEMP_MAIL_ADMIN_PASSWORD=一个强密码
TEMP_MAIL_DOMAIN=temp-mail.example.com
```

## 3. 初始化系统环境

```bash
sudo /opt/temp-mail/scripts/bootstrap_ubuntu.sh
```

它会安装：

- `postfix`
- `sqlite3`
- `python3`
- `python3-venv`
- `python3-pip`
- `swaks`

并创建：

- `/opt/temp-mail/venv`
- `/opt/temp-mail/data/temp_mail.db`

在继续之前，建议先确认 DNS 已正确配置：

- [DNS 配置说明](./dns-setup.md)

## 4. 应用 Postfix 配置

```bash
sudo TEMP_MAIL_DOMAIN=temp-mail.example.com /opt/temp-mail/scripts/apply_postfix_config.sh
```

这一步会：

- 更新 `myhostname`
- 更新 `virtual_alias_domains`
- 更新 `virtual_alias_maps`
- 写入 `/etc/postfix/virtual_alias_regexp`
- 更新 `/etc/aliases` 中的 `tempmail` pipe
- 写入 `/etc/mailname`
- 执行 `newaliases`
- 重启 `postfix`

## 5. 安装 systemd 服务

```bash
sudo /opt/temp-mail/scripts/install_service.sh
```

查看状态：

```bash
sudo systemctl status temp-mail --no-pager
```

## 6. 安装 cron 清理任务

```bash
sudo /opt/temp-mail/scripts/setup_cron.sh
```

默认每小时清理 1 小时前的邮件。

## 7. 测试 API

```bash
curl http://127.0.0.1:8000/health
```

创建地址：

```bash
curl -X POST http://127.0.0.1:8000/admin/new_address \
  -H 'Content-Type: application/json' \
  -H 'x-admin-auth: 你的管理密码' \
  -d '{"enablePrefix": true, "name": "demo", "domain": "temp-mail.example.com"}'
```

## 8. 测试收件

```bash
swaks --to demo@temp-mail.example.com --from hello@test.com --server 127.0.0.1
```

然后查询：

```bash
curl "http://127.0.0.1:8000/admin/mails?address=demo@temp-mail.example.com&limit=20&offset=0" \
  -H "x-admin-auth: 你的管理密码"
```

## DNS 要求

你需要自己在 DNS 提供商处配置：

- `A`：`temp-mail.example.com -> 你的服务器 IP`
- `MX`：`temp-mail.example.com -> temp-mail.example.com`

邮件服务主机名必须是 `仅 DNS`，不能走 CDN 代理。
