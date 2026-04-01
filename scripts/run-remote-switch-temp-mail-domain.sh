#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  先在 ./.env 中配置好以下变量：
    SSH_HOST
    SSH_PASSWORD
    CF_API_TOKEN
    TEMP_MAIL_ADMIN_PASSWORD
    CODEX_CONSOLE_PASSWORD

  可选但推荐固定的 ID：
    CF_A_RECORD_ID
    CF_MX_RECORD_ID
    CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID

  然后执行：
    ./scripts/run-remote-switch-temp-mail-domain.sh <new-domain> [ssh-user] [cf-zone-name]

示例:
  ./scripts/run-remote-switch-temp-mail-domain.sh temp-mail.example.com

注意:
  - 这里传入的是目标新后缀，不是旧后缀

说明:
  - 本脚本会优先加载同项目根目录下的 .env
  - 同名环境变量会覆盖 .env 中的值
  - 旧后缀以服务端当前 Postfix 配置为准
  - Cloudflare DNS 相关调用只在服务端执行，但变量统一从本机 .env 透传
  - 会通过 SSH 把本地 switch-temp-mail-domain.sh 直接喂给远程 bash 执行，不在服务器落盘
  - 如果 ssh-user 是 root，则远程命令不加 sudo
  - 远程成功后，会调用本机 codex-console API 更新 temp_mail 配置
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1" >&2
    exit 1
  }
}

shell_quote() {
  python3 -c 'import shlex,sys; print(shlex.quote(sys.argv[1]))' "$1"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

require_cmd ssh
require_cmd sshpass
require_cmd python3
require_cmd curl
require_cmd mktemp

NEW_DOMAIN="$1"
SSH_USER="${2:-root}"
CF_ZONE_NAME="${3:-${NEW_DOMAIN#*.}}"
LOCAL_SWITCH_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/switch-temp-mail-domain.sh"
[[ -f "$LOCAL_SWITCH_SCRIPT" ]] || { echo "缺少本地脚本: $LOCAL_SWITCH_SCRIPT" >&2; exit 1; }

SSH_HOST="${SSH_HOST:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
CF_API_TOKEN="${CF_API_TOKEN:-}"
TEMP_MAIL_ADMIN_PASSWORD="${TEMP_MAIL_ADMIN_PASSWORD:-}"
CF_SERVER_IP="${CF_SERVER_IP:-$SSH_HOST}"
CF_A_RECORD_ID="${CF_A_RECORD_ID:-}"
CF_MX_RECORD_ID="${CF_MX_RECORD_ID:-}"
CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID="${CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID:-}"
CODEX_CONSOLE_PASSWORD="${CODEX_CONSOLE_PASSWORD:-}"
CODEX_CONSOLE_BASE_URL="${CODEX_CONSOLE_BASE_URL:-http://127.0.0.1:8000}"
TEMP_MAIL_SERVICE_BASE_URL="${TEMP_MAIL_SERVICE_BASE_URL:-http://${NEW_DOMAIN}:8000}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-3}"
BACKUP_CLEANUP_ENABLED="${BACKUP_CLEANUP_ENABLED:-true}"

[[ -n "$SSH_HOST" ]] || { echo "缺少环境变量 SSH_HOST" >&2; exit 1; }
[[ -n "$SSH_PASSWORD" ]] || { echo "缺少环境变量 SSH_PASSWORD" >&2; exit 1; }
[[ -n "$CF_API_TOKEN" ]] || { echo "缺少环境变量 CF_API_TOKEN" >&2; exit 1; }
[[ -n "$TEMP_MAIL_ADMIN_PASSWORD" ]] || { echo "缺少环境变量 TEMP_MAIL_ADMIN_PASSWORD" >&2; exit 1; }
[[ -n "$CODEX_CONSOLE_PASSWORD" ]] || { echo "缺少环境变量 CODEX_CONSOLE_PASSWORD" >&2; exit 1; }

export SSHPASS="$SSH_PASSWORD"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)

if [[ "$SSH_USER" == "root" ]]; then
  REMOTE_PREFIX=""
else
  REMOTE_PREFIX="sudo "
fi

REMOTE_OLD_DOMAIN_CMD="${REMOTE_PREFIX}postconf -h myhostname | tr -d '[:space:]'"
OLD_DOMAIN="$(sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$REMOTE_OLD_DOMAIN_CMD")"
[[ -n "$OLD_DOMAIN" ]] || { echo '无法从服务端读取当前后缀' >&2; exit 1; }

echo "[run-remote-switch] 服务端当前后缀: ${OLD_DOMAIN}"

if [[ "$OLD_DOMAIN" == "$NEW_DOMAIN" ]]; then
  echo '[run-remote-switch] 服务端当前后缀已经是目标后缀，跳过远程迁移，只同步 codex-console 配置...'
else
  echo '[run-remote-switch] 开始执行远程域名迁移脚本...'
REMOTE_CMD=$(cat <<CMD
${REMOTE_PREFIX}env \
  CF_API_TOKEN=$(shell_quote "$CF_API_TOKEN") \
  CF_ZONE_NAME=$(shell_quote "$CF_ZONE_NAME") \
  TEMP_MAIL_ADMIN_PASSWORD=$(shell_quote "$TEMP_MAIL_ADMIN_PASSWORD") \
  CF_SERVER_IP=$(shell_quote "$CF_SERVER_IP") \
  CF_A_RECORD_ID=$(shell_quote "$CF_A_RECORD_ID") \
  CF_MX_RECORD_ID=$(shell_quote "$CF_MX_RECORD_ID") \
  BACKUP_RETENTION_DAYS=$(shell_quote "$BACKUP_RETENTION_DAYS") \
  BACKUP_CLEANUP_ENABLED=$(shell_quote "$BACKUP_CLEANUP_ENABLED") \
  bash -s -- $(shell_quote "$OLD_DOMAIN") $(shell_quote "$NEW_DOMAIN")
CMD
)
  sshpass -e ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$REMOTE_CMD" < "$LOCAL_SWITCH_SCRIPT"
  echo '[run-remote-switch] 远程迁移完成，开始更新本机 codex-console 邮箱服务配置...'
fi

echo '[run-remote-switch] 开始更新本机 codex-console 邮箱服务配置...'
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

curl --noproxy "*" -fsS -c "$COOKIE_JAR" -X POST "${CODEX_CONSOLE_BASE_URL}/login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "password=${CODEX_CONSOLE_PASSWORD}&next=/" >/dev/null

if ! grep -q 'webui_auth' "$COOKIE_JAR"; then
  echo 'codex-console 登录失败，未拿到 webui_auth cookie' >&2
  exit 1
fi

SERVICES_JSON="$(curl --noproxy "*" -fsS -b "$COOKIE_JAR" "${CODEX_CONSOLE_BASE_URL}/api/email-services?service_type=temp_mail")"
if [[ -n "$CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID" ]]; then
  SERVICE_ID="$CODEX_CONSOLE_TEMP_MAIL_SERVICE_ID"
else
  SERVICE_ID="$({ printf '%s' "$SERVICES_JSON" | python3 -c 'import json,sys; data=json.load(sys.stdin); services=data.get("services", []); old=sys.argv[1]; target=None
for service in services:
    cfg=service.get("config") or {}
    if cfg.get("domain") == old:
        target=service
        break
if target is None and len(services) == 1:
    target=services[0]
if target is None:
    raise SystemExit(1)
print(target["id"])' "$OLD_DOMAIN"; } )" || {
    echo '未找到唯一可更新的 temp_mail 服务，请先确认 codex-console 中的 temp_mail 配置。' >&2
    exit 1
  }
fi

PATCH_PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"config": {"domain": sys.argv[1], "base_url": sys.argv[2]}}))' "$NEW_DOMAIN" "$TEMP_MAIL_SERVICE_BASE_URL")"

curl --noproxy "*" -fsS -b "$COOKIE_JAR" -X PATCH "${CODEX_CONSOLE_BASE_URL}/api/email-services/${SERVICE_ID}" \
  -H 'Content-Type: application/json' \
  --data "$PATCH_PAYLOAD" >/dev/null

VERIFY_JSON="$(curl --noproxy "*" -fsS -b "$COOKIE_JAR" "${CODEX_CONSOLE_BASE_URL}/api/email-services/${SERVICE_ID}/full")"
VERIFY_OK="$({ printf '%s' "$VERIFY_JSON" | python3 -c 'import json,sys; data=json.load(sys.stdin); cfg=data.get("config") or {}; print("ok" if cfg.get("domain")==sys.argv[1] and cfg.get("base_url")==sys.argv[2] else "fail")' "$NEW_DOMAIN" "$TEMP_MAIL_SERVICE_BASE_URL"; } )"

if [[ "$VERIFY_OK" != 'ok' ]]; then
  echo 'codex-console API 更新后校验失败' >&2
  printf '%s\n' "$VERIFY_JSON" >&2
  exit 1
fi

echo "[run-remote-switch] codex-console 更新完成: service_id=${SERVICE_ID}"
echo "[run-remote-switch] old_domain=${OLD_DOMAIN}"
echo "[run-remote-switch] new_domain=${NEW_DOMAIN}"
echo "[run-remote-switch] base_url=${TEMP_MAIL_SERVICE_BASE_URL}"
