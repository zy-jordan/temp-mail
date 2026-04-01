#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

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

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量: $name" >&2
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1" >&2
    exit 1
  }
}

require_var TEMP_MAIL_ROOT
require_var TEMP_MAIL_DATA_DIR
require_var TEMP_MAIL_DB_PATH
require_var TEMP_MAIL_ADMIN_PASSWORD
require_var TEMP_MAIL_DOMAIN

require_cmd python3
require_cmd dig
require_cmd ss

if [[ "$TEMP_MAIL_ROOT" != "/opt/temp-mail" ]]; then
  echo "警告: TEMP_MAIL_ROOT 当前不是 /opt/temp-mail，而是 $TEMP_MAIL_ROOT" >&2
fi

if [[ -d "$TEMP_MAIL_ROOT" && ! -w "$TEMP_MAIL_ROOT" ]]; then
  echo "目录存在但当前不可写: $TEMP_MAIL_ROOT" >&2
  exit 1
fi

mkdir -p "$TEMP_MAIL_DATA_DIR"

A_RECORD="$(dig +short "$TEMP_MAIL_DOMAIN" A | tail -n1 | tr -d '[:space:]')"
MX_RECORD="$(dig +short "$TEMP_MAIL_DOMAIN" MX | awk 'NR==1{print $2}' | sed 's/\.$//')"

if [[ -z "$A_RECORD" ]]; then
  echo "警告: $TEMP_MAIL_DOMAIN 当前没有解析到 A 记录" >&2
fi
if [[ "$MX_RECORD" != "$TEMP_MAIL_DOMAIN" ]]; then
  echo "警告: $TEMP_MAIL_DOMAIN 的 MX 当前不是自指向，当前值: ${MX_RECORD:-<empty>}" >&2
fi

if ss -ltn '( sport = :25 )' | grep -q ':25'; then
  echo '检查通过: 25 端口已监听'
else
  echo '警告: 25 端口当前未监听，Postfix 可能尚未启动' >&2
fi

echo "TEMP_MAIL_ROOT=$TEMP_MAIL_ROOT"
echo "TEMP_MAIL_DATA_DIR=$TEMP_MAIL_DATA_DIR"
echo "TEMP_MAIL_DB_PATH=$TEMP_MAIL_DB_PATH"
echo "TEMP_MAIL_DOMAIN=$TEMP_MAIL_DOMAIN"
echo "A_RECORD=${A_RECORD:-<empty>}"
echo "MX_RECORD=${MX_RECORD:-<empty>}"
echo '预检查完成'
