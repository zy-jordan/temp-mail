#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

INSTALL_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
DATA_DIR="${TEMP_MAIL_DATA_DIR:-${INSTALL_ROOT}/data}"

apt update
DEBIAN_FRONTEND=noninteractive apt install -y git postfix sqlite3 python3 python3-venv python3-pip swaks dnsutils rsync

mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR"

python3 -m venv "${INSTALL_ROOT}/venv"
"${INSTALL_ROOT}/venv/bin/pip" install --upgrade pip
"${INSTALL_ROOT}/venv/bin/pip" install -e "$INSTALL_ROOT"
"${INSTALL_ROOT}/venv/bin/python" "${INSTALL_ROOT}/scripts/init_db.py"

# 确保 DB 文件对 Postfix 管道用户 (nobody) 可写
chmod 666 "${DATA_DIR}"/*.db 2>/dev/null || true
chmod 666 "${DATA_DIR}"/*.db-wal 2>/dev/null || true
chmod 666 "${DATA_DIR}"/*.db-shm 2>/dev/null || true

echo "基础环境初始化完成"
