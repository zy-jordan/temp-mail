#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

INSTALL_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
install -D -m 0644 "${INSTALL_ROOT}/deploy/cron/cleanup-old-mail.cron" /etc/cron.d/temp-mail-cleanup
chmod 0644 /etc/cron.d/temp-mail-cleanup
cat /etc/cron.d/temp-mail-cleanup
