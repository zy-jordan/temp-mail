# temp-mail

自建的临时邮箱服务，面向 `codex-console` 的 `temp_mail` 邮箱服务适配层。

当前目标环境是 **Ubuntu 单机**，并保留这套固定部署路径：

- 应用目录：`/opt/temp-mail`
- 数据目录：`/opt/temp-mail/data`
- 数据库：`/opt/temp-mail/data/temp_mail.db`
- 虚拟环境：`/opt/temp-mail/venv`

## 仓库结构

```text
app/
  api.py
  config.py
  db.py
  mail_ingest.py
scripts/
  bootstrap_ubuntu.sh
  init_db.py
  cleanup_old_mail.sh
  install_service.sh
  setup_cron.sh
  apply_postfix_config.sh
  post_deploy_report.sh
  switch-temp-mail-domain.sh
  run-remote-switch-temp-mail-domain.sh
deploy/
  systemd/temp-mail.service
  cron/cleanup-old-mail.cron
  postfix/
    main.cf.example
    virtual_alias_regexp.example
    aliases.example
docs/
  ubuntu-deployment.md
pyproject.toml
.env.example
```

## 功能

- 提供 `temp_mail` 兼容 API：
  - `POST /admin/new_address`
  - `GET /admin/mails`
  - `GET /admin/mails/{id}`
- 通过 `Postfix` + catch-all 收件
- 使用 `SQLite` 存储地址和邮件
- 支持 `systemd` 常驻运行
- 支持 `cron` 定时清理旧邮件

## 快速开始

### 1. 准备部署目录

把仓库放到：

```bash
/opt/temp-mail
```

例如：

```bash
git clone <your-repo> /opt/temp-mail
cd /opt/temp-mail
cp .env.example .env
```

### 2. 新手一键部署

```bash
sudo /opt/temp-mail/scripts/deploy.sh
```

这个入口会自动完成：

- 安装 Ubuntu 依赖
- 初始化数据库
- 应用 Postfix 配置
- 安装 `systemd` 服务
- 安装 `cron` 清理任务
- 执行端到端自测
- 打印部署后自检报告

### 3. 分步部署

如果你不想一键执行，也可以按下面顺序单独跑：

```bash
sudo /opt/temp-mail/scripts/bootstrap_ubuntu.sh
/opt/temp-mail/venv/bin/python /opt/temp-mail/scripts/init_db.py
sudo TEMP_MAIL_DOMAIN=temp-mail.example.com /opt/temp-mail/scripts/apply_postfix_config.sh
sudo /opt/temp-mail/scripts/install_service.sh
sudo /opt/temp-mail/scripts/setup_cron.sh
```

## API 开发运行

在仓库根目录执行：

```bash
python3 -m venv /opt/temp-mail/venv
/opt/temp-mail/venv/bin/pip install -e .
TEMP_MAIL_ADMIN_PASSWORD=change-me /opt/temp-mail/venv/bin/uvicorn app.api:app --host 0.0.0.0 --port 8000
```

## 配置

参考 [`.env.example`](.env.example)。最关键的变量有：

- `TEMP_MAIL_ADMIN_PASSWORD`
- `TEMP_MAIL_DB_PATH`
- `TEMP_MAIL_RETENTION_HOURS`
- `TEMP_MAIL_DOMAIN`

## 代码审查结论

这次整理前，我对现有实现做了快速审查，主要发现并顺手修掉了这几个问题：

1. `db.py` 路径硬编码，导致仓库运行方式和服务端运行方式耦合过死。
2. `api.py` 直接 `from db import get_conn`，不利于打包和从仓库根目录运行。
3. 没有数据库初始化入口，新机器部署时必须手工建表。
4. SQLite 没有显式设置 `WAL` 和 `busy_timeout`，并发场景下更容易碰到锁等待问题。

现在这些问题都已经被整理进项目结构和脚本里了。

## 域名切换

如果你已经在生产上跑通这套服务，后续需要切换邮箱后缀，可以使用：

- `scripts/switch-temp-mail-domain.sh`：服务端迁移脚本
- `scripts/run-remote-switch-temp-mail-domain.sh`：开发机编排脚本

相关文档：

- [docs/temp-mail-domain-switch-operations.md](docs/temp-mail-domain-switch-operations.md)
- [docs/temp-mail-id-discovery.md](docs/temp-mail-id-discovery.md)

## 文档

- DNS 配置说明见 [docs/dns-setup.md](docs/dns-setup.md)
- 详细部署说明见 [docs/ubuntu-deployment.md](docs/ubuntu-deployment.md)
- 域名切换说明见 [docs/temp-mail-domain-switch-operations.md](docs/temp-mail-domain-switch-operations.md)
- ID 查询说明见 [docs/temp-mail-id-discovery.md](docs/temp-mail-id-discovery.md)
