#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

INSTALL_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
SERVICE_TEMPLATE="${INSTALL_ROOT}/deploy/systemd/temp-mail.service"
SERVICE_PATH="/etc/systemd/system/temp-mail.service"

if [[ ! -f "$SERVICE_TEMPLATE" ]]; then
  echo "缺少 service 模板: $SERVICE_TEMPLATE" >&2
  exit 1
fi

cp "$SERVICE_TEMPLATE" "$SERVICE_PATH"
systemctl daemon-reload
systemctl enable --now temp-mail
systemctl status temp-mail --no-pager
