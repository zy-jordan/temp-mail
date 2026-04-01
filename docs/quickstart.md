# Quickstart

这是给新手的最短路径。

## 1. 克隆仓库到服务器

```bash
git clone <your-repo> /opt/temp-mail
cd /opt/temp-mail
cp .env.example .env
```

## 2. 修改 `.env`

如果你想先理解每个变量是干什么的，先看：

- [配置文件说明](./config-reference.md)

至少改这几个：

```env
TEMP_MAIL_ADMIN_PASSWORD=一个强密码
TEMP_MAIL_DOMAIN=temp-mail.example.com
TEMP_MAIL_TEST_LOCAL_PART=deploycheck
```

## 3. 配 DNS

你需要自己在 DNS 提供商处配置：

- `A`: `temp-mail.example.com -> 服务器公网 IP`
- `MX`: `temp-mail.example.com -> temp-mail.example.com`

如果你不熟 DNS，先看这份文档再继续：

- [DNS 配置说明](./dns-setup.md)

## 4. 一键部署

```bash
sudo /opt/temp-mail/scripts/deploy.sh
```

## 5. 成功标志

如果部署成功，最后会看到：

```text
端到端测试通过: deploycheck@temp-mail.example.com
部署完成
===== Temp Mail 部署后自检报告 =====
```

如果部署失败，脚本退出前也会尽量打印这份自检报告，方便直接定位卡点。
