#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

apt update
DEBIAN_FRONTEND=noninteractive apt install -y   git   postfix   sqlite3   python3   python3-venv   python3-pip   swaks   dnsutils   rsync

mkdir -p /opt/temp-mail/data

python3 -m venv /opt/temp-mail/venv
/opt/temp-mail/venv/bin/pip install --upgrade pip
/opt/temp-mail/venv/bin/pip install -e /opt/temp-mail
/opt/temp-mail/venv/bin/python /opt/temp-mail/scripts/init_db.py

echo "基础环境初始化完成"
