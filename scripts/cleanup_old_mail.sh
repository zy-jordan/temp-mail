#!/usr/bin/env bash
set -euo pipefail

TEMP_MAIL_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
ENV_FILE="${TEMP_MAIL_ROOT}/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

TEMP_MAIL_DB_PATH="${TEMP_MAIL_DB_PATH:-${TEMP_MAIL_ROOT}/data/temp_mail.db}"
TEMP_MAIL_RETENTION_HOURS="${TEMP_MAIL_RETENTION_HOURS:-1}"
TEMP_MAIL_CLEANUP_ADDRESSES="${TEMP_MAIL_CLEANUP_ADDRESSES:-true}"

sqlite3 "$TEMP_MAIL_DB_PATH" <<SQL
DELETE FROM mails
WHERE datetime(created_at) < datetime('now', '-${TEMP_MAIL_RETENTION_HOURS} hour');
SQL

if [[ "${TEMP_MAIL_CLEANUP_ADDRESSES,,}" == "true" ]]; then
  sqlite3 "$TEMP_MAIL_DB_PATH" <<SQL
DELETE FROM addresses
WHERE datetime(created_at) < datetime('now', '-${TEMP_MAIL_RETENTION_HOURS} hour')
  AND address NOT IN (SELECT DISTINCT address FROM mails);
SQL
fi
