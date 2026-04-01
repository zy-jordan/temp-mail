# Temp Mail 域名切换操作手册

## 目的

这套脚本用于把自建 `temp_mail` 服务的邮箱后缀从当前服务端正在使用的后缀，切换到新的目标后缀，并在成功后同步更新本机 `codex-console` 的 `temp_mail` 配置。

脚本分为两层：

- `scripts/run-remote-switch-temp-mail-domain.sh`
  运行在开发机；负责读取本机 `.env`、SSH 到服务端执行迁移、再调用本机 `codex-console` API 同步配置。
- `scripts/switch-temp-mail-domain.sh`
  运行在服务端；负责 Cloudflare DNS 更新、Postfix 配置切换、自测和备份清理。

## 当前约定

- 所有敏感变量只维护在开发机的 `.env`
- Cloudflare API 请求只在服务端执行
- 服务端当前后缀是唯一可信来源
- Cloudflare DNS 使用固定 `record id` 更新，不按后缀模糊查找
- `codex-console` 使用固定 `service id` 更新，不按后缀模糊查找
- 服务端成功迁移后，默认清理 3 天前的 `/etc/postfix/*.bak*` 和 `/etc/mailname.bak*`

## 需要维护的文件

- 环境变量模板：[`../.env.example`](../.env.example)
- 开发机脚本：[`../scripts/run-remote-switch-temp-mail-domain.sh`](../scripts/run-remote-switch-temp-mail-domain.sh)
- 服务端脚本：[`../scripts/switch-temp-mail-domain.sh`](../scripts/switch-temp-mail-domain.sh)

## `.env` 必填项

如果你想先理解每个变量分别属于“部署邮箱服务”还是“切换邮箱后缀”，先看：

- [配置文件说明](./config-reference.md)

在仓库根目录创建 `.env`，至少包含：

```env
SSH_HOST=YOUR_SERVER_IP
SSH_PASSWORD=你的SSH密码
CF_API_TOKEN=你的Cloudflare Token
TEMP_MAIL_ADMIN_PASSWORD=你的temp-mail管理密码
CODEX_CONSOLE_PASSWORD=你的codex-console访问密码
CODEX_CONSOLE_BASE_URL=http://127.0.0.1:8000
TEMP_MAIL_SERVICE_BASE_URL=http://YOUR_SERVER_IP:8000
CF_SERVER_IP=YOUR_SERVER_IP
CF_A_RECORD_ID=你的A记录ID
CF_MX_RECORD_ID=你的MX记录ID
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=你的service id
BACKUP_RETENTION_DAYS=3
BACKUP_CLEANUP_ENABLED=true
```

说明：

- `TEMP_MAIL_SERVICE_BASE_URL` 目前按你的现状固定为 `http://YOUR_SERVER_IP:8000`
- `CF_A_RECORD_ID`、`CF_MX_RECORD_ID` 是 Cloudflare 上那条邮箱后缀记录对应的固定 ID
- `CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID` 是 `codex-console` 里那条 `temp_mail` 服务的固定 ID
- `CODEX_CONSOLE_BASE_URL` 当前使用 `http://127.0.0.1:8000`，脚本会自动对这个地址使用 `curl --noproxy '*'`

## 日常切换命令

切到目标新后缀：

```bash
cd /path/to/temp-mail
./scripts/run-remote-switch-temp-mail-domain.sh temp-mail.example.com
```

如果以后要切回旧后缀：

```bash
cd /path/to/temp-mail
./scripts/run-remote-switch-temp-mail-domain.sh tempmail.example.com
```

注意：

- 这个脚本只传一个参数，这个参数始终是“目标新后缀”
- 脚本不会让你手动传旧后缀；旧后缀从服务端当前 `Postfix` 配置自动读取

## 脚本实际做的事

### 开发机脚本

`run-remote-switch-temp-mail-domain.sh` 会：

1. 读取本机 `.env`
2. SSH 到服务端，读取当前 `myhostname` 作为旧后缀
3. 如果服务端当前后缀已经等于目标后缀：
   - 跳过远程迁移
   - 只同步 `codex-console`
4. 否则把本地 `switch-temp-mail-domain.sh` 通过 SSH 流式喂给远程 `bash`
5. 远程成功后，调用本机 `codex-console` API，更新固定 `service_id` 对应的 `temp_mail` 配置：
   - `domain = new_domain`
   - `base_url = TEMP_MAIL_SERVICE_BASE_URL`

### 服务端脚本

`switch-temp-mail-domain.sh` 会：

1. 读取服务端当前 `Postfix` 后缀
2. 用固定 `CF_A_RECORD_ID` / `CF_MX_RECORD_ID` 更新 Cloudflare DNS
3. 备份并改写：
   - `/etc/postfix/main.cf`
   - `/etc/postfix/virtual_alias_regexp`
   - `/etc/mailname`
4. 执行：
   - `newaliases`
   - `systemctl restart postfix`
5. 做 DNS 重试校验
   - 如果 Cloudflare 刚更新还没传播，会重试
   - 重试后仍未收敛时，只打 warning，不中断整个流程
6. 做 `temp_mail` API 自测
7. 默认清理 3 天前的旧备份

## 成功后的核对点

### 服务端

```bash
postconf myhostname
postconf virtual_alias_domains
cat /etc/postfix/virtual_alias_regexp
cat /etc/mailname
```

预期：

- `myhostname` 是目标新后缀
- `virtual_alias_domains` 是目标新后缀
- `virtual_alias_regexp` 的正则匹配目标新后缀
- `/etc/mailname` 是目标新后缀

### DNS

```bash
dig temp-mail.example.com A +short
dig temp-mail.example.com MX +short
```

预期：

- `A` 指向 `YOUR_SERVER_IP`
- `MX` 指向 `temp-mail.example.com.`

### codex-console

脚本成功时会输出类似：

```text
[run-remote-switch] codex-console 更新完成: service_id=2
[run-remote-switch] old_domain=...
[run-remote-switch] new_domain=...
[run-remote-switch] base_url=http://YOUR_SERVER_IP:8000
```

## 常见问题

### 1. 参数传反了

错误示例：

```bash
./scripts/run-remote-switch-temp-mail-domain.sh tempmail.example.com
```

如果你本来想切到 `temp-mail.example.com`，这条命令会把它迁回旧后缀。

记住：

- 传入值永远是“目标新后缀”

### 2. 本机 `curl` 命中代理返回 `502`

这个已经在脚本里处理了。

针对 `CODEX_CONSOLE_BASE_URL=http://127.0.0.1:8000`，脚本会自动使用：

```bash
curl --noproxy '*'
```

### 3. Cloudflare DNS 刚改完就校验失败

这个也已经在脚本里处理了。

现在会：

- 重试等待传播
- 本机解析和公共解析都检查
- 最后仍未收敛时只 warning，不直接中断整个流程

## 旧数据清理

如果你想清理旧后缀的邮箱历史数据，可在服务端执行：

```bash
sqlite3 /opt/temp-mail/data/temp_mail.db "DELETE FROM mails WHERE address LIKE '%@旧后缀'; DELETE FROM addresses WHERE address LIKE '%@旧后缀';"
```

## 备份清理策略

默认策略：

- 删除 3 天前的：
  - `/etc/postfix/main.cf.bak*`
  - `/etc/postfix/virtual_alias_regexp.bak*`
  - `/etc/mailname.bak*`

如需关闭：

```env
BACKUP_CLEANUP_ENABLED=false
```

如需修改保留天数：

```env
BACKUP_RETENTION_DAYS=7
```
