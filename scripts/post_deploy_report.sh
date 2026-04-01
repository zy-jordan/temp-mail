#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "缺少 .env，请先从 .env.example 复制一份" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TEMP_MAIL_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
TEMP_MAIL_DB_PATH="${TEMP_MAIL_DB_PATH:-${TEMP_MAIL_ROOT}/data/temp_mail.db}"
TEMP_MAIL_PORT="${TEMP_MAIL_PORT:-8000}"
TEMP_MAIL_DOMAIN="${TEMP_MAIL_DOMAIN:-}"
BASE_URL="http://127.0.0.1:${TEMP_MAIL_PORT}"

print_kv() {
  printf '%-28s %s
' "$1" "$2"
}

safe_cmd() {
  if "$@" 2>/dev/null; then
    return 0
  fi
  return 1
}

echo '===== Temp Mail 部署后自检报告 ====='
print_kv 'TEMP_MAIL_ROOT' "$TEMP_MAIL_ROOT"
print_kv 'TEMP_MAIL_DB_PATH' "$TEMP_MAIL_DB_PATH"
print_kv 'TEMP_MAIL_DOMAIN' "${TEMP_MAIL_DOMAIN:-<empty>}"
print_kv 'TEMP_MAIL_PORT' "$TEMP_MAIL_PORT"

echo
echo '[DNS]'
if command -v dig >/dev/null 2>&1 && [[ -n "$TEMP_MAIL_DOMAIN" ]]; then
  A_RECORD="$(dig +short "$TEMP_MAIL_DOMAIN" A | tail -n1 | tr -d '[:space:]')"
  MX_RECORD="$(dig +short "$TEMP_MAIL_DOMAIN" MX | awk 'NR==1{print $2}' | sed 's/\.$//')"
  print_kv 'A' "${A_RECORD:-<empty>}"
  print_kv 'MX' "${MX_RECORD:-<empty>}"
else
  echo 'dig 不可用或 TEMP_MAIL_DOMAIN 为空'
fi

echo
echo '[Ports]'
if command -v ss >/dev/null 2>&1; then
  PORT_25='closed'
  PORT_API='closed'
  if ss -ltn '( sport = :25 )' | grep -q ':25'; then PORT_25='listening'; fi
  if ss -ltn "( sport = :${TEMP_MAIL_PORT} )" | grep -q ":${TEMP_MAIL_PORT}"; then PORT_API='listening'; fi
  print_kv '25/tcp' "$PORT_25"
  print_kv "${TEMP_MAIL_PORT}/tcp" "$PORT_API"
else
  echo 'ss 不可用'
fi

echo
echo '[Services]'
if command -v systemctl >/dev/null 2>&1; then
  POSTFIX_STATUS="$(systemctl is-active postfix 2>/dev/null || true)"
  TEMP_MAIL_STATUS="$(systemctl is-active temp-mail 2>/dev/null || true)"
  print_kv 'postfix' "${POSTFIX_STATUS:-unknown}"
  print_kv 'temp-mail' "${TEMP_MAIL_STATUS:-unknown}"
else
  echo 'systemctl 不可用'
fi

echo
echo '[API]'
if command -v curl >/dev/null 2>&1; then
  if HEALTH="$(curl -fsS --max-time 5 "$BASE_URL/health" 2>/dev/null)"; then
    print_kv 'health' 'ok'
    print_kv 'payload' "$HEALTH"
  else
    print_kv 'health' 'failed'
  fi
else
  echo 'curl 不可用'
fi

echo
echo '[SQLite]'
if [[ -f "$TEMP_MAIL_DB_PATH" ]] && command -v sqlite3 >/dev/null 2>&1; then
  MAILS_COUNT="$(sqlite3 "$TEMP_MAIL_DB_PATH" 'select count(*) from mails;' 2>/dev/null || true)"
  ADDRESSES_COUNT="$(sqlite3 "$TEMP_MAIL_DB_PATH" 'select count(*) from addresses;' 2>/dev/null || true)"
  print_kv 'db_exists' 'yes'
  print_kv 'mails' "${MAILS_COUNT:-unknown}"
  print_kv 'addresses' "${ADDRESSES_COUNT:-unknown}"
else
  print_kv 'db_exists' 'no'
fi

echo
echo '[Postfix Config]'
if command -v postconf >/dev/null 2>&1; then
  print_kv 'myhostname' "$(postconf -h myhostname 2>/dev/null || true)"
  print_kv 'virtual_alias_domains' "$(postconf -h virtual_alias_domains 2>/dev/null || true)"
fi
if [[ -f /etc/postfix/virtual_alias_regexp ]]; then
  print_kv 'virtual_alias_regexp' "$(tr '
' ' ' < /etc/postfix/virtual_alias_regexp)"
fi
if [[ -f /etc/aliases ]]; then
  ALIAS_LINE="$(grep '^tempmail:' /etc/aliases 2>/dev/null || true)"
  print_kv 'aliases.tempmail' "${ALIAS_LINE:-<missing>}"
fi
