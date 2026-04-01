# Temp Mail ID 查询手册

## 目的

这份文档只解决一件事：**怎么查出脚本需要的 3 个固定 ID**。

包括：

- `CF_A_RECORD_ID`
- `CF_MX_RECORD_ID`
- `CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID`

这些 ID 建议固定写进开发机的 `.env`，避免脚本按后缀模糊匹配时碰到脏数据或历史配置。

## 最终写入 `.env` 的字段

```env
CF_A_RECORD_ID=...
CF_MX_RECORD_ID=...
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=...
```

## 0. 先创建 Cloudflare API Token

这一步建议先做，因为后面的 `CF_A_RECORD_ID` / `CF_MX_RECORD_ID` 查询都要用到它。

### 在哪里创建

按 Cloudflare Dashboard 当前路径：

1. 登录 Cloudflare Dashboard。
2. 进入 `My Profile`。
3. 打开 `API Tokens`。
4. 点击 `Create Token`。
5. 选择 `Create Custom Token`。

### 这个场景建议的最小权限

如果你继续沿用当前脚本里的 `CF_ZONE_NAME=example.com` 方式，建议给这个 token：

- `Zone` / `DNS` / `Edit`
- `Zone` / `Zone` / `Read`

资源范围选：

- `Include` -> `Specific zone` -> `example.com`

原因：

- `DNS Edit` 用来查询、更新 `A` / `MX` 记录
- `Zone Read` 用来根据 `CF_ZONE_NAME` 查 `zone id`

如果你已经把 `CF_ZONE_ID` 固定写进脚本或环境变量，不再需要按 zone name 查询，那么可以进一步缩小成：

- `Zone` / `DNS` / `Edit`

### 是否要加来源 IP 限制

按你当前的使用方式，Cloudflare API 只在**服务端**执行，所以 token 可以加来源 IP 限制，但要注意：

- 允许的来源 IP 应该是**服务端出口 IP**
- 如果你把开发机出口 IP 排除在外，那么开发机本地就查不了 Cloudflare DNS API

你现在这套脚本是允许这样做的，因为：

- Cloudflare DNS 查询和更新都在服务端执行
- 开发机只负责 SSH 调度和更新 `codex-console`

### 创建后保存什么

创建完成后，至少要保存：

- `CF_API_TOKEN`

如果你后面还准备把 `zone id` 也固定下来，可以顺手再查：

- `CF_ZONE_ID`

### 官方文档

我参考的是 Cloudflare 官方文档：

- Create API token: https://developers.cloudflare.com/cloudflare-one/api-terraform/scoped-api-tokens/
- API token permissions: https://developers.cloudflare.com/fundamentals/api/reference/permissions/
- DNS Records API: https://developers.cloudflare.com/api/resources/dns/

## 1. 查询 Cloudflare DNS 的两个 record id

### 为什么要在服务端查

你当前的 `CF_API_TOKEN` 做了来源 IP 限制，所以 Cloudflare DNS API 只能从**服务端出口 IP**调用成功。

也就是说：

- `CF_A_RECORD_ID`
- `CF_MX_RECORD_ID`

要在**服务端**查，不要在本机查。

### 需要准备的变量

在服务端 shell 里准备：

```bash
export CF_API_TOKEN='你的CloudflareToken'
export CF_ZONE_NAME='example.com'
export OLD_DOMAIN='当前正在使用的邮箱后缀'
```

例如：

```bash
export CF_API_TOKEN='你的CloudflareToken'
export CF_ZONE_NAME='example.com'
export OLD_DOMAIN='temp-mail.example.com'
```

### 一条命令查出 3 个值

在服务端执行：

```bash
python3 - <<'PY'
import json
import os
import urllib.request

cf_api_token = os.environ['CF_API_TOKEN']
cf_zone_name = os.environ['CF_ZONE_NAME']
old_domain = os.environ['OLD_DOMAIN']


def req(url: str):
    request = urllib.request.Request(
        url,
        headers={
            'Authorization': f'Bearer {cf_api_token}',
            'Content-Type': 'application/json',
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


zone_payload = req(
    f'https://api.cloudflare.com/client/v4/zones?name={cf_zone_name}&status=active&match=all'
)
zone_id = zone_payload['result'][0]['id']

a_payload = req(
    f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?type=A&name={old_domain}&match=all'
)
mx_payload = req(
    f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?type=MX&name={old_domain}&match=all'
)

print('CF_ZONE_ID=' + zone_id)
print('CF_A_RECORD_ID=' + a_payload['result'][0]['id'])
print('CF_MX_RECORD_ID=' + mx_payload['result'][0]['id'])
PY
```

正常情况下会输出类似：

```text
CF_ZONE_ID=xxxx
CF_A_RECORD_ID=xxxx
CF_MX_RECORD_ID=xxxx
```

### 查完后怎么核对

你可以再单独检查一下这两个 ID 对应的记录是不是你想要的当前后缀：

```bash
export CF_ZONE_ID='上一步输出的 CF_ZONE_ID'
export CF_A_RECORD_ID='上一步输出的 CF_A_RECORD_ID'
export CF_MX_RECORD_ID='上一步输出的 CF_MX_RECORD_ID'

curl -s "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_A_RECORD_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H 'Content-Type: application/json'

curl -s "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_MX_RECORD_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H 'Content-Type: application/json'
```

你重点看返回里的：

- `type`
- `name`
- `content`

预期应该是：

- `A` 记录：`name = 当前旧后缀`
- `MX` 记录：`name = 当前旧后缀`

## 2. 查询 `CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID`

### 这个 ID 在哪里查

这个 ID 不在服务端查，而是在**开发机**通过 `codex-console` 自己的 API 查。

原因：

- `codex-console` 配置存在本机的应用数据库里
- 最稳的入口就是它自己的 API

### 需要准备的变量

在开发机 shell 里准备：

```bash
export CODEX_CONSOLE_BASE_URL='http://127.0.0.1:8000'
export CODEX_CONSOLE_PASSWORD='你的codex-console访问密码'
export OLD_DOMAIN='当前 codex-console 里 temp_mail 配置使用的后缀'
```

例如：

```bash
export CODEX_CONSOLE_BASE_URL='http://127.0.0.1:8000'
export CODEX_CONSOLE_PASSWORD='你的codex-console访问密码'
export OLD_DOMAIN='temp-mail.example.com'
```

### 先说明 `COOKIE_JAR` 是什么

`COOKIE_JAR` 不是从 `codex-console` 里查出来的值。

它只是你**本机自己指定的一个临时文件路径**，用来让 `curl` 保存登录后的 cookie。

最简单的写法就是固定写死一个路径：

```bash
COOKIE_JAR='/tmp/codex-console.cookies.txt'
```

如果你想每次都生成一个独立临时文件，也可以用：

```bash
COOKIE_JAR="$(mktemp /tmp/codex-console.cookies.XXXXXX.txt)"
```

关键点只有一个：

- `curl -c "$COOKIE_JAR"` 会把登录后的 cookie 写进去
- 后面的 `curl -b "$COOKIE_JAR"` 会复用这个 cookie 去调用 API

### 一条命令查出 `service id`

在开发机执行：

```bash
COOKIE_JAR='/tmp/codex-console.cookies.txt'

curl --noproxy '*' -s -c "$COOKIE_JAR" -X POST "${CODEX_CONSOLE_BASE_URL}/login"   -H 'Content-Type: application/x-www-form-urlencoded'   --data "password=${CODEX_CONSOLE_PASSWORD}&next=/" >/dev/null

curl --noproxy '*' -s -b "$COOKIE_JAR" "${CODEX_CONSOLE_BASE_URL}/api/email-services?service_type=temp_mail" |
python3 -c 'import json,sys; old=sys.argv[1]; data=json.load(sys.stdin)
for service in data.get("services", []):
    cfg = service.get("config") or {}
    if cfg.get("domain") == old:
        print("CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=" + str(service["id"]))
        break' "$OLD_DOMAIN"
```

正常情况下会输出类似：

```text
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=your-service-id
```

### 查完后怎么核对

继续执行：

```bash
export CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID='上一步输出的 service id'

curl --noproxy '*' -s -b "$COOKIE_JAR" \
  "${CODEX_CONSOLE_BASE_URL}/api/email-services/${CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID}/full"
```

你重点看返回里的：

- `service_type`
- `config.domain`
- `config.base_url`

预期应该是：

- `service_type = temp_mail`
- `config.domain = OLD_DOMAIN`

## 3. 写回 `.env`

把查出来的值写回开发机的 `.env`：

```env
CF_A_RECORD_ID=你查出来的A记录ID
CF_MX_RECORD_ID=你查出来的MX记录ID
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID=你查出来的service id
```

## 4. 推荐的实际流程

每次准备切换后缀时，按这个顺序来：

1. 在服务端查：
   - `CF_A_RECORD_ID`
   - `CF_MX_RECORD_ID`
2. 在开发机查：
   - `CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID`
3. 把它们写进开发机 `.env`
4. 再执行切换脚本：

```bash
cd /path/to/temp-mail
./scripts/run-remote-switch-temp-mail-domain.sh 目标新后缀
```

## 5. 常见问题

### 1. Cloudflare API 在开发机查失败

如果报类似这类错误：

```text
Cannot use the access token from location
```

说明 `CF_API_TOKEN` 做了来源 IP 限制。此时不要在开发机查，改到服务端查。

### 2. `codex-console` API 返回 `502`

如果你本机开了代理，访问 `127.0.0.1:8000` 可能被代理环境变量劫持。

所以这里统一使用：

```bash
curl --noproxy '*'
```

### 3. `temp_mail` 服务不止一条

如果你在 `codex-console` 里配置了多条 `temp_mail` 服务，必须按 `config.domain == OLD_DOMAIN` 精确匹配，不要只取第一条。
