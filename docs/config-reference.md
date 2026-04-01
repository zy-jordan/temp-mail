# 配置文件说明

这份文档专门说明 `temp-mail` 项目的配置项。

当前项目默认使用：

- 仓库根目录下的 `.env`
- 模板文件：[`../.env.example`](../.env.example)

最重要的一点是：

- **部署邮箱服务本身** 和 **切换邮箱后缀** 用到的是同一个 `.env`
- 但它们关注的变量不是一批

所以这份文档会把两类变量拆开讲。

## 1. 配置文件位置

项目里约定：

- 模板：[`../.env.example`](../.env.example)
- 实际配置：`/opt/temp-mail/.env`

一般流程是：

```bash
cd /opt/temp-mail
cp .env.example .env
```

然后只改你当前需要的变量。

## 2. 第一类：部署邮箱服务本身要用的变量

这类变量是你第一次部署 `temp-mail` 服务时必须关心的。

### `TEMP_MAIL_ROOT`

默认值：

```env
TEMP_MAIL_ROOT=/opt/temp-mail
```

作用：

- 项目的部署根目录
- 脚本默认按这个目录找代码、数据、虚拟环境

通常不建议改。

### `TEMP_MAIL_DATA_DIR`

默认值：

```env
TEMP_MAIL_DATA_DIR=/opt/temp-mail/data
```

作用：

- 存放数据库和运行数据的目录

### `TEMP_MAIL_DB_PATH`

默认值：

```env
TEMP_MAIL_DB_PATH=/opt/temp-mail/data/temp_mail.db
```

作用：

- SQLite 数据库文件路径

### `TEMP_MAIL_ADMIN_PASSWORD`

默认值：

```env
TEMP_MAIL_ADMIN_PASSWORD=change-me
```

作用：

- `temp-mail` API 的管理密码
- 调用下面这些接口时会用到：
  - `POST /admin/new_address`
  - `GET /admin/mails`
  - `GET /admin/mails/{id}`

这是部署时**必须改掉**的值。

### `TEMP_MAIL_HOST`

默认值：

```env
TEMP_MAIL_HOST=0.0.0.0
```

作用：

- `uvicorn` 监听地址
- `systemd` 启动模板会读取它

一般保持默认即可。

### `TEMP_MAIL_PORT`

默认值：

```env
TEMP_MAIL_PORT=8000
```

作用：

- `temp-mail` API 监听端口

如果你不想改端口，保持 `8000` 就行。

### `TEMP_MAIL_RETENTION_HOURS`

默认值：

```env
TEMP_MAIL_RETENTION_HOURS=1
```

作用：

- 清理脚本删除几小时前的旧邮件
- 被 [`../scripts/cleanup_old_mail.sh`](../scripts/cleanup_old_mail.sh) 使用

### `TEMP_MAIL_CLEANUP_ADDRESSES`

默认值：

```env
TEMP_MAIL_CLEANUP_ADDRESSES=true
```

作用：

- 清理旧邮件后，是否顺带清理没有邮件关联的旧地址

### `TEMP_MAIL_DOMAIN`

默认值：

```env
TEMP_MAIL_DOMAIN=temp-mail.example.com
```

作用：

- 邮箱服务使用的后缀
- 同时影响：
  - `Postfix` 配置
  - 测试邮件地址
  - API 创建邮箱时的域名
  - DNS 文档里的目标域名

这是部署时**必须改成你的真实邮箱域名**的值。

### `TEMP_MAIL_TEST_LOCAL_PART`

默认值：

```env
TEMP_MAIL_TEST_LOCAL_PART=deploycheck
```

作用：

- 端到端测试脚本使用的测试邮箱前缀
- 最终测试地址是：
  - `${TEMP_MAIL_TEST_LOCAL_PART}@${TEMP_MAIL_DOMAIN}`

一般保持默认即可。

## 3. 第二类：切换邮箱后缀时才会用到的变量

这类变量只在你已经把服务跑起来之后，准备从一个后缀切换到另一个后缀时才需要关心。

也就是说：

- **首次部署时，不一定要全部填好**
- **真正做域名切换时，再填完整**

### `SSH_HOST`

默认示例：

```env
SSH_HOST=YOUR_SERVER_IP
```

作用：

- 开发机编排脚本通过 SSH 连接哪台服务器
- 被 [`../scripts/run-remote-switch-temp-mail-domain.sh`](../scripts/run-remote-switch-temp-mail-domain.sh) 使用

### `SSH_PASSWORD`

默认示例：

```env
SSH_PASSWORD=changeme
```

作用：

- 开发机脚本登录服务端时使用的 SSH 密码

### `CF_API_TOKEN`

默认示例：

```env
CF_API_TOKEN=changeme
```

作用：

- 服务端脚本调用 Cloudflare DNS API 时使用
- 被 [`../scripts/switch-temp-mail-domain.sh`](../scripts/switch-temp-mail-domain.sh) 使用

注意：

- 这个 token 只需要在**切换域名**时用到
- 平时部署和日常运行 `temp-mail` 服务本身，不依赖它

### `CODEX_CONSOLE_PASSWORD`

默认示例：

```env
CODEX_CONSOLE_PASSWORD=changeme
```

作用：

- 开发机脚本登录本机 `codex-console` Web UI 时使用
- 用来调用 `codex-console` 自己的 API，更新 `temp_mail` 配置

### `CODEX_CONSOLE_BASE_URL`

默认值：

```env
CODEX_CONSOLE_BASE_URL=http://127.0.0.1:8000
```

作用：

- `run-remote-switch-temp-mail-domain.sh` 访问本机 `codex-console` 的地址

### `TEMP_MAIL_SERVICE_BASE_URL`

默认示例：

```env
TEMP_MAIL_SERVICE_BASE_URL=http://YOUR_SERVER_IP:8000
```

作用：

- 切换后，要把 `codex-console` 里的 `temp_mail.base_url` 更新成什么值

如果你希望 `codex-console` 永远通过 IP 访问你的 `temp-mail` 服务，就填 IP；如果你希望通过域名访问，就填域名。

### `CF_SERVER_IP`

默认示例：

```env
CF_SERVER_IP=YOUR_SERVER_IP
```

作用：

- 切换后，Cloudflare `A` 记录要指向哪个 IP
- 留空时会默认退回 `SSH_HOST`

### `CF_A_RECORD_ID`

默认值：

```env
CF_A_RECORD_ID=
```

作用：

- Cloudflare 上那条邮箱域名 `A` 记录的固定 `record id`
- 域名切换时，脚本会直接按这个 ID 更新记录

### `CF_MX_RECORD_ID`

默认值：

```env
CF_MX_RECORD_ID=
```

作用：

- Cloudflare 上那条邮箱域名 `MX` 记录的固定 `record id`
- 域名切换时，脚本会直接按这个 ID 更新记录

### `CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID`

默认值：

```env
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=
```

作用：

- `codex-console` 里那条 `temp_mail` 邮箱服务的固定 `service id`
- 域名切换时，开发机脚本会直接更新这条服务配置

### `BACKUP_RETENTION_DAYS`

默认值：

```env
BACKUP_RETENTION_DAYS=3
```

作用：

- 域名切换成功后，服务端清理几天前的 `/etc/postfix/*.bak*` 和 `/etc/mailname.bak*`

### `BACKUP_CLEANUP_ENABLED`

默认值：

```env
BACKUP_CLEANUP_ENABLED=true
```

作用：

- 是否启用域名切换后的旧备份清理

## 4. 最小部署配置

如果你只是第一次把邮箱服务搭起来，最小需要改的是这些：

```env
TEMP_MAIL_ADMIN_PASSWORD=一个强密码
TEMP_MAIL_DOMAIN=你的邮箱域名
```

通常其他部署变量保持默认就够了。

## 5. 最小切换后缀配置

如果你已经把服务跑起来了，只是要切换邮箱后缀，最关键的是这批：

```env
SSH_HOST=...
SSH_PASSWORD=...
CF_API_TOKEN=...
CODEX_CONSOLE_PASSWORD=...
CODEX_CONSOLE_BASE_URL=...
TEMP_MAIL_SERVICE_BASE_URL=...
CF_A_RECORD_ID=...
CF_MX_RECORD_ID=...
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=...
```

## 6. 推荐阅读顺序

### 只想部署邮箱服务

按这个顺序看：

1. [dns-setup.md](./dns-setup.md)
2. [quickstart.md](./quickstart.md)
3. [troubleshooting.md](./troubleshooting.md)

### 想切换邮箱后缀

按这个顺序看：

1. [temp-mail-id-discovery.md](./temp-mail-id-discovery.md)
2. [temp-mail-domain-switch-operations.md](./temp-mail-domain-switch-operations.md)

## 7. 一句话总结

- `TEMP_MAIL_*` 这一批，主要是**部署和运行邮箱服务本身**
- `SSH_*`、`CF_*`、`CODEX_CONSOLE_*` 这一批，主要是**切换邮箱后缀**
