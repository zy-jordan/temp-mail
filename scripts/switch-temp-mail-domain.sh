#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  sudo CF_API_TOKEN=xxx [CF_ZONE_ID=xxx|CF_ZONE_NAME=example.com] [CF_SERVER_IP=x.x.x.x] \
       [TEMP_MAIL_ADMIN_PASSWORD=xxx] [TEMP_MAIL_API_URL=http://127.0.0.1:8000] \
       ./scripts/switch-temp-mail-domain.sh <new-domain>

或：
  sudo CF_API_TOKEN=xxx [CF_ZONE_ID=xxx|CF_ZONE_NAME=example.com] [CF_SERVER_IP=x.x.x.x] \
       [TEMP_MAIL_ADMIN_PASSWORD=xxx] [TEMP_MAIL_API_URL=http://127.0.0.1:8000] \
       ./scripts/switch-temp-mail-domain.sh <old-domain> <new-domain>

说明:
  - 以邮件服务端当前配置为准
  - Cloudflare DNS 使用记录 ID 直接更新，不走新增/删除
  - 若提供 TEMP_MAIL_ADMIN_PASSWORD，会自动执行 swaks + API 查询自测
  - 默认清理 3 天前的 /etc/postfix/*.bak* 和 /etc/mailname.bak* 备份
USAGE
}

log() {
  printf '[switch-temp-mail-domain] %s\n' "$*"
}

fail() {
  printf '[switch-temp-mail-domain] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 && $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  fail "请使用 root 或 sudo 运行此脚本"
fi

require_cmd curl
require_cmd python3
require_cmd dig
require_cmd newaliases
require_cmd systemctl
require_cmd swaks
require_cmd postconf

if [[ $# -eq 1 ]]; then
  PROVIDED_OLD_DOMAIN=""
  NEW_DOMAIN="$1"
else
  PROVIDED_OLD_DOMAIN="$1"
  NEW_DOMAIN="$2"
fi

CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE_ID="${CF_ZONE_ID:-}"
CF_ZONE_NAME="${CF_ZONE_NAME:-}"
CF_SERVER_IP="${CF_SERVER_IP:-}"
CF_A_RECORD_ID="${CF_A_RECORD_ID:-}"
CF_MX_RECORD_ID="${CF_MX_RECORD_ID:-}"
TEMP_MAIL_ADMIN_PASSWORD="${TEMP_MAIL_ADMIN_PASSWORD:-}"
TEMP_MAIL_API_URL="${TEMP_MAIL_API_URL:-http://127.0.0.1:8000}"
TEMP_MAIL_TEST_LOCAL_PART="${TEMP_MAIL_TEST_LOCAL_PART:-switchcheck$(date +%s)}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-3}"
BACKUP_CLEANUP_ENABLED="${BACKUP_CLEANUP_ENABLED:-true}"

MAIN_CF="/etc/postfix/main.cf"
VIRTUAL_ALIAS_REGEXP="/etc/postfix/virtual_alias_regexp"
MAILNAME_FILE="/etc/mailname"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
CF_API_BASE="https://api.cloudflare.com/client/v4"

[[ -n "$CF_API_TOKEN" ]] || fail "缺少环境变量 CF_API_TOKEN"
[[ -f "$MAIN_CF" ]] || fail "缺少 $MAIN_CF"

json_extract() {
  local expr="$1"
  python3 -c 'import json,sys; data=json.load(sys.stdin); value=eval(sys.argv[1], {"__builtins__": {}}, {"data": data}); import json as _json; print("" if value is None else (_json.dumps(value) if isinstance(value,(dict,list)) else value))' "$expr"
}

cf_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" "${CF_API_BASE}${endpoint}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H 'Content-Type: application/json' \
      --data "$data"
  else
    curl -fsS -X "$method" "${CF_API_BASE}${endpoint}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H 'Content-Type: application/json'
  fi
}

cf_assert_success() {
  local payload="$1"
  local ok
  ok="$(printf '%s' "$payload" | json_extract 'data.get("success")')"
  if [[ "$ok" != "True" && "$ok" != "true" ]]; then
    printf '%s\n' "$payload" >&2
    fail "Cloudflare API 返回失败"
  fi
}

cf_get_zone_id() {
  if [[ -n "$CF_ZONE_ID" ]]; then
    printf '%s\n' "$CF_ZONE_ID"
    return 0
  fi

  [[ -n "$CF_ZONE_NAME" ]] || CF_ZONE_NAME="${OLD_DOMAIN#*.}"
  printf "[switch-temp-mail-domain] Zone name: %s\n" "$CF_ZONE_NAME" >&2

  local payload zone_id
  payload="$(cf_api GET "/zones?name=${CF_ZONE_NAME}&status=active&match=all")"
  cf_assert_success "$payload"
  zone_id="$(printf '%s' "$payload" | json_extract 'data["result"][0]["id"] if data.get("result") else ""')"
  [[ -n "$zone_id" ]] || fail "无法根据 zone name 找到 Cloudflare Zone: $CF_ZONE_NAME"
  printf '%s\n' "$zone_id"
}

cf_get_record_payload() {
  local zone_id="$1"
  local record_type="$2"
  local record_name="$3"
  local payload
  payload="$(cf_api GET "/zones/${zone_id}/dns_records?type=${record_type}&name=${record_name}&match=all")"
  cf_assert_success "$payload"
  printf '%s' "$payload"
}

cf_update_a_records_by_id() {
  local zone_id="$1"
  local old_name="$2"
  local new_name="$3"
  local ip="$4"
  local payload count line id body resp

  if [[ -n "$CF_A_RECORD_ID" ]]; then
    body="$(python3 -c 'import json,sys; print(json.dumps({"type":"A","name":sys.argv[1],"content":sys.argv[2],"ttl":1,"proxied":False}, ensure_ascii=False))' "$new_name" "$ip")"
    resp="$(cf_api PUT "/zones/${zone_id}/dns_records/${CF_A_RECORD_ID}" "$body")"
    cf_assert_success "$resp"
    log "已按固定记录 ID 更新 A 记录: ${old_name} -> ${new_name} ($CF_A_RECORD_ID)"
    return 0
  fi

  payload="$(cf_get_record_payload "$zone_id" A "$old_name")"
  count="$(printf '%s' "$payload" | json_extract 'len(data.get("result", []))')"
  [[ "$count" != "0" ]] || fail "Cloudflare 中未找到旧后缀 A 记录: $old_name"

  while IFS=$'	' read -r id body; do
    [[ -n "$id" ]] || continue
    resp="$(cf_api PUT "/zones/${zone_id}/dns_records/${id}" "$body")"
    cf_assert_success "$resp"
    log "已按记录 ID 更新 A 记录: ${old_name} -> ${new_name} ($id)"
  done < <(
    CF_PAYLOAD="$payload" python3 -c 'import json, os, sys; payload=json.loads(os.environ["CF_PAYLOAD"]); new_name=sys.argv[1]; ip=sys.argv[2]
for item in payload.get("result", []):
    body=json.dumps({"type":"A","name":new_name,"content":ip,"ttl":item.get("ttl",1),"proxied":False}, ensure_ascii=False)
    print(item["id"] + "\t" + body)' "$new_name" "$ip"
  )
}

cf_update_mx_records_by_id() {
  local zone_id="$1"
  local old_name="$2"
  local new_name="$3"
  local payload count id body resp

  if [[ -n "$CF_MX_RECORD_ID" ]]; then
    body="$(python3 -c 'import json,sys; print(json.dumps({"type":"MX","name":sys.argv[1],"content":sys.argv[1],"priority":10,"ttl":1}, ensure_ascii=False))' "$new_name")"
    resp="$(cf_api PUT "/zones/${zone_id}/dns_records/${CF_MX_RECORD_ID}" "$body")"
    cf_assert_success "$resp"
    log "已按固定记录 ID 更新 MX 记录: ${old_name} -> ${new_name} ($CF_MX_RECORD_ID)"
    return 0
  fi

  payload="$(cf_get_record_payload "$zone_id" MX "$old_name")"
  count="$(printf '%s' "$payload" | json_extract 'len(data.get("result", []))')"
  [[ "$count" != "0" ]] || fail "Cloudflare 中未找到旧后缀 MX 记录: $old_name"

  while IFS=$'	' read -r id body; do
    [[ -n "$id" ]] || continue
    resp="$(cf_api PUT "/zones/${zone_id}/dns_records/${id}" "$body")"
    cf_assert_success "$resp"
    log "已按记录 ID 更新 MX 记录: ${old_name} -> ${new_name} ($id)"
  done < <(
    CF_PAYLOAD="$payload" python3 -c 'import json, os, sys; payload=json.loads(os.environ["CF_PAYLOAD"]); new_name=sys.argv[1]
for item in payload.get("result", []):
    body=json.dumps({"type":"MX","name":new_name,"content":new_name,"priority":item.get("priority",10),"ttl":item.get("ttl",1)}, ensure_ascii=False)
    print(item["id"] + "\t" + body)' "$new_name"
  )
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\\/&]/\\&/g'
}

escape_regex_literal() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{|]/\\&/g'
}

backup_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cp "$path" "${path}.bak.${TIMESTAMP}"
    log "已备份: ${path}.bak.${TIMESTAMP}"
  fi
}

set_or_replace_postconf_line() {
  local key="$1"
  local value="$2"
  local escaped_value
  escaped_value="$(escape_sed_replacement "$value")"

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$MAIN_CF"; then
    sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*$|${key} = ${escaped_value}|" "$MAIN_CF"
  else
    printf '\n%s = %s\n' "$key" "$value" >> "$MAIN_CF"
  fi
}

resolve_server_ip() {
  if [[ -n "$CF_SERVER_IP" ]]; then
    printf '%s\n' "$CF_SERVER_IP"
    return 0
  fi

  local resolved
  resolved="$(dig +short "$OLD_DOMAIN" A | tail -n1 | tr -d '[:space:]')"
  [[ -n "$resolved" ]] || fail "无法解析旧后缀 A 记录，请显式传入 CF_SERVER_IP"
  printf '%s\n' "$resolved"
}

get_server_domain() {
  local host alias
  host="$(postconf -h myhostname | tr -d '[:space:]')"
  alias="$(postconf -h virtual_alias_domains | tr -d '[:space:]')"

  [[ -n "$host" ]] || fail "服务端 myhostname 为空"
  [[ -n "$alias" ]] || fail "服务端 virtual_alias_domains 为空"
  [[ "$host" == "$alias" ]] || fail "服务端配置不一致: myhostname=$host, virtual_alias_domains=$alias"
  printf '%s\n' "$host"
}

assert_server_state_before() {
  local origin
  origin="$(postconf -h myorigin | tr -d '[:space:]')"
  [[ "$origin" == "/etc/mailname" ]] || fail "myorigin 不是 /etc/mailname: 当前 $origin"
  log "迁移前服务端检查通过: domain=$OLD_DOMAIN"
}

assert_server_state_after() {
  local host alias origin mailname
  host="$(postconf -h myhostname | tr -d '[:space:]')"
  alias="$(postconf -h virtual_alias_domains | tr -d '[:space:]')"
  origin="$(postconf -h myorigin | tr -d '[:space:]')"
  mailname="$(tr -d '[:space:]' < "$MAILNAME_FILE")"

  [[ "$host" == "$NEW_DOMAIN" ]] || fail "myhostname 未切换: 当前 $host"
  [[ "$alias" == "$NEW_DOMAIN" ]] || fail "virtual_alias_domains 未切换: 当前 $alias"
  [[ "$origin" == "/etc/mailname" ]] || fail "myorigin 被改坏了: 当前 $origin"
  [[ "$mailname" == "$NEW_DOMAIN" ]] || fail "/etc/mailname 未切换: 当前 $mailname"
  log "迁移后服务端检查通过: domain=$NEW_DOMAIN"
}

warn() {
  printf '[switch-temp-mail-domain] %s
' "$*" >&2
}

assert_dns_after() {
  local tries new_a new_mx public_a public_mx
  tries="${DNS_VERIFY_RETRIES:-20}"

  for ((i=1; i<=tries; i++)); do
    new_a="$(dig +short "$NEW_DOMAIN" A | tail -n1 | tr -d '[:space:]')"
    new_mx="$(dig +short "$NEW_DOMAIN" MX | awk 'NR==1{print $2}' | sed 's/\.$//')"
    public_a="$(dig @1.1.1.1 +short "$NEW_DOMAIN" A | tail -n1 | tr -d '[:space:]' || true)"
    public_mx="$(dig @1.1.1.1 +short "$NEW_DOMAIN" MX | awk 'NR==1{print $2}' | sed 's/\.$//' || true)"

    if [[ "$new_a" == "$SERVER_IP" && "$new_mx" == "$NEW_DOMAIN" ]]; then
      log "迁移后 DNS 检查通过: A=$new_a, MX=$new_mx"
      return 0
    fi

    if [[ "$public_a" == "$SERVER_IP" && "$public_mx" == "$NEW_DOMAIN" ]]; then
      log "迁移后公共 DNS 检查通过: A=$public_a, MX=$public_mx"
      return 0
    fi

    if (( i < tries )); then
      sleep 3
    fi
  done

  warn "DNS 记录已通过 Cloudflare API 更新，但即时校验仍未收敛；继续执行。"
  warn "本机解析: A=${new_a:-<empty>} MX=${new_mx:-<empty>}"
  warn "公共解析: A=${public_a:-<empty>} MX=${public_mx:-<empty>}"
  return 0
}

run_temp_mail_self_test() {
  if [[ -z "$TEMP_MAIL_ADMIN_PASSWORD" ]]; then
    log "未提供 TEMP_MAIL_ADMIN_PASSWORD，跳过 API 自测"
    return 0
  fi

  local address payload test_subject
  address="${TEMP_MAIL_TEST_LOCAL_PART}@${NEW_DOMAIN}"
  test_subject="switch-domain-${TIMESTAMP}"

  log "开始自测收件链路: $address"
  swaks --to "$address" --from hello@test.com --server 127.0.0.1 --header "Subject: ${test_subject}" --body "temp mail domain switch self-test ${TIMESTAMP}" >/dev/null
  sleep 2
  payload="$(curl -fsS "${TEMP_MAIL_API_URL}/admin/mails?address=${address}&limit=20&offset=0" -H "x-admin-auth: ${TEMP_MAIL_ADMIN_PASSWORD}")"
  if ! printf '%s' "$payload" | grep -Fq "$test_subject"; then
    printf '%s\n' "$payload" >&2
    fail "API 自测未查到测试邮件: $address"
  fi

  log "API 自测通过: $address"
}

cleanup_old_backups() {
  local deleted days enabled path
  days="$BACKUP_RETENTION_DAYS"
  enabled="${BACKUP_CLEANUP_ENABLED,,}"

  [[ "$days" =~ ^[0-9]+$ ]] || fail "BACKUP_RETENTION_DAYS 必须是非负整数: $days"
  if [[ "$enabled" == "false" || "$enabled" == "0" || "$enabled" == "no" ]]; then
    log "已禁用备份清理，跳过"
    return 0
  fi

  deleted=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    rm -f "$path"
    deleted=$((deleted + 1))
    log "已清理过期备份: $path"
  done < <(
    find /etc/postfix -maxdepth 1 -type f \(       -name 'main.cf.bak' -o -name 'main.cf.bak.*' -o       -name 'virtual_alias_regexp.bak' -o -name 'virtual_alias_regexp.bak.*'     \) -mtime +"$days" -print
    find /etc -maxdepth 1 -type f \(       -name 'mailname.bak' -o -name 'mailname.bak.*'     \) -mtime +"$days" -print
  )

  log "备份清理完成: 删除 ${deleted} 个文件（保留 ${days} 天内备份）"
}

SERVER_DOMAIN="$(get_server_domain)"
OLD_DOMAIN="${PROVIDED_OLD_DOMAIN:-$SERVER_DOMAIN}"
[[ "$OLD_DOMAIN" == "$SERVER_DOMAIN" ]] || fail "传入旧后缀与服务端不一致: arg=$OLD_DOMAIN, server=$SERVER_DOMAIN"
[[ "$OLD_DOMAIN" != "$NEW_DOMAIN" ]] || fail "旧后缀和新后缀不能相同"

assert_server_state_before
ZONE_ID="$(cf_get_zone_id)"
SERVER_IP="$(resolve_server_ip)"

log "开始迁移 DNS: ${OLD_DOMAIN} -> ${NEW_DOMAIN}"
log "Cloudflare Zone ID: ${ZONE_ID}"
log "目标 A 记录 IP: ${SERVER_IP}"

cf_update_a_records_by_id "$ZONE_ID" "$OLD_DOMAIN" "$NEW_DOMAIN" "$SERVER_IP"
cf_update_mx_records_by_id "$ZONE_ID" "$OLD_DOMAIN" "$NEW_DOMAIN"

backup_file "$MAIN_CF"
backup_file "$VIRTUAL_ALIAS_REGEXP"
backup_file "$MAILNAME_FILE"

set_or_replace_postconf_line "myhostname" "$NEW_DOMAIN"
set_or_replace_postconf_line "virtual_alias_domains" "$NEW_DOMAIN"
set_or_replace_postconf_line "virtual_alias_maps" "regexp:/etc/postfix/virtual_alias_regexp"
set_or_replace_postconf_line "myorigin" "/etc/mailname"

NEW_DOMAIN_REGEX="$(escape_regex_literal "$NEW_DOMAIN")"
printf '/^.+@%s$/ tempmail\n' "$NEW_DOMAIN_REGEX" > "$VIRTUAL_ALIAS_REGEXP"
printf '%s\n' "$NEW_DOMAIN" > "$MAILNAME_FILE"

newaliases
systemctl restart postfix

assert_server_state_after
assert_dns_after
run_temp_mail_self_test
cleanup_old_backups

printf '\n'
log "域名迁移完成: ${OLD_DOMAIN} -> ${NEW_DOMAIN}"
printf '\n'
printf '如需清理旧后缀历史数据，可执行:\n'
printf '  sqlite3 /opt/temp-mail/data/temp_mail.db "DELETE FROM mails WHERE address LIKE '\''%%@%s'\''; DELETE FROM addresses WHERE address LIKE '\''%%@%s'\'';"\n' "$OLD_DOMAIN" "$OLD_DOMAIN"
