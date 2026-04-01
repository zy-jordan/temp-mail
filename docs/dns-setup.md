# DNS 配置说明

这份文档专门解释 `temp-mail` 项目需要的 DNS 配置。

目标场景：

- Ubuntu 单机
- 邮箱域名使用一个子域，例如 `temp-mail.example.com`
- 邮件由你自己的服务器直接收件
- 不走 Cloudflare Email Routing，不走 CDN 代理

## 目标效果

假设你的服务器公网 IP 是：

```text
1.2.3.4
```

你要配置的邮箱域名是：

```text
temp-mail.example.com
```

最终正确状态应该是：

- `A` 记录：`temp-mail.example.com -> 1.2.3.4`
- `MX` 记录：`temp-mail.example.com -> temp-mail.example.com`
- `A` 记录必须是 `仅 DNS`
- 不能开启 CDN 代理

## 为什么要这样配

`temp-mail` 这套服务是：

- 外部邮件发到 `xxx@temp-mail.example.com`
- DNS 的 `MX` 记录告诉对方：这封邮件应该投递到哪台邮件主机
- 你的服务器上的 `Postfix` 负责收这封邮件
- `mail_ingest.py` 再把邮件写入 SQLite

所以：

- `MX` 负责“邮件往哪投”
- `A` 负责“这个邮件主机的 IP 是多少”

## 在 Cloudflare 里怎么配

下面按 Cloudflare 的常见 DNS 面板来写。

### 1. 配置 A 记录

新增一条 `A` 记录：

- `Type`: `A`
- `Name`: `temp-mail`
- `IPv4 address`: `你的服务器公网 IP`
- `Proxy status`: `DNS only`
- `TTL`: `Auto`

如果你的主域是 `example.com`，那么：

- `Name` 填 `temp-mail`
- 最终生效的完整域名就是：
  - `temp-mail.example.com`

### 2. 配置 MX 记录

新增一条 `MX` 记录：

- `Type`: `MX`
- `Name`: `temp-mail`
- `Mail server`: `temp-mail.example.com`
- `Priority`: `10`
- `TTL`: `Auto`

如果你的主域是 `example.com`，那么：

- `Name` 填 `temp-mail`
- `Mail server` 填 `temp-mail.example.com`

## 在别的 DNS 提供商里怎么理解字段

不同平台字段名不一样，但本质是一样的：

### A 记录

要表达的是：

```text
temp-mail.example.com -> 1.2.3.4
```

常见字段映射：

- `Host` / `Name`: `temp-mail`
- `Value` / `Points to`: `1.2.3.4`
- `TTL`: `Auto` 或默认值

### MX 记录

要表达的是：

```text
temp-mail.example.com -> temp-mail.example.com
priority 10
```

常见字段映射：

- `Host` / `Name`: `temp-mail`
- `Mail server` / `Value` / `Points to`: `temp-mail.example.com`
- `Priority`: `10`
- `TTL`: `Auto` 或默认值

## 正确示例

如果你的域名是 `example.com`，服务器 IP 是 `1.2.3.4`，那么正确示例是：

### A

```text
Type: A
Name: temp-mail
Value: 1.2.3.4
Proxy: DNS only
TTL: Auto
```

### MX

```text
Type: MX
Name: temp-mail
Value: temp-mail.example.com
Priority: 10
TTL: Auto
```

## 常见错误

### 1. A 记录开了代理

错误：

- `Proxy status = Proxied`

后果：

- 外界看到的是 Cloudflare 的 IP
- 邮件服务不会按你的预期投到服务器

正确做法：

- 改成 `DNS only`

### 2. MX 指到了别的系统

错误示例：

- 指向 Cloudflare Email Routing
- 指向某个旧域名
- 指向根域名而不是你的邮件子域

后果：

- 邮件不会投到你的 `Postfix`

正确做法：

- `MX` 必须指向你的邮件主机名本身，例如：
  - `temp-mail.example.com`

### 3. Name 填错

错误示例：

- 把完整域名填进 `Name`
- 或把根域名填进去

这个要看 DNS 提供商的界面规则，但在 Cloudflare 里通常：

- `Name` 只填子域部分，例如 `temp-mail`

### 4. 改完 DNS 立刻测试失败

DNS 有传播时间，不一定是立刻全网生效。

所以你应该用 `dig` 看实际解析结果，而不是只盯着面板。

## 怎么验证 DNS 是否配对了

### 验证 A 记录

```bash
dig temp-mail.example.com A +short
```

预期输出：

```text
1.2.3.4
```

### 验证 MX 记录

```bash
dig temp-mail.example.com MX +short
```

预期输出：

```text
10 temp-mail.example.com.
```

注意最后那个点 `.` 是正常的。

### 验证公共解析

如果你怀疑本机缓存，可以直接查公共 DNS：

```bash
dig @1.1.1.1 temp-mail.example.com A +short
dig @1.1.1.1 temp-mail.example.com MX +short
```

## 什么时候可以继续下一步

只有当下面两条都对了，你才应该继续跑部署脚本：

```bash
dig temp-mail.example.com A +short
dig temp-mail.example.com MX +short
```

满足：

- `A` 返回你的服务器 IP
- `MX` 返回你的邮箱域名自己

## 和 `.env` 的关系

你在 `.env` 里填的：

```env
TEMP_MAIL_DOMAIN=temp-mail.example.com
```

必须和 DNS 里实际配置的邮箱域名一致。

也就是说：

- `.env` 里写 `temp-mail.example.com`
- DNS 就必须真的配出 `temp-mail.example.com`

不能一个写旧域名，一个配新域名。
