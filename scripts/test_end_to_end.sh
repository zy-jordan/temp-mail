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

TEMP_MAIL_PORT="${TEMP_MAIL_PORT:-8000}"
TEMP_MAIL_TEST_LOCAL_PART="${TEMP_MAIL_TEST_LOCAL_PART:-deploycheck}"
TEMP_MAIL_DOMAIN="${TEMP_MAIL_DOMAIN:?缺少 TEMP_MAIL_DOMAIN}"
TEMP_MAIL_ADMIN_PASSWORD="${TEMP_MAIL_ADMIN_PASSWORD:?缺少 TEMP_MAIL_ADMIN_PASSWORD}"
BASE_URL="http://127.0.0.1:${TEMP_MAIL_PORT}"
TEST_ADDRESS="${TEMP_MAIL_TEST_LOCAL_PART}@${TEMP_MAIL_DOMAIN}"
TEST_SUBJECT="temp-mail-e2e-$(date +%s)"
PAYLOAD_JSON="$(python3 -c 'import json,sys; print(json.dumps({"enablePrefix": True, "name": sys.argv[1], "domain": sys.argv[2]}))' "$TEMP_MAIL_TEST_LOCAL_PART" "$TEMP_MAIL_DOMAIN")"

curl -fsS "$BASE_URL/health" >/dev/null

curl -fsS -X POST "$BASE_URL/admin/new_address"   -H 'Content-Type: application/json'   -H "x-admin-auth: ${TEMP_MAIL_ADMIN_PASSWORD}"   --data "$PAYLOAD_JSON" >/dev/null

swaks --to "$TEST_ADDRESS" --from hello@test.com --server 127.0.0.1 --header "Subject: ${TEST_SUBJECT}" --body "temp mail e2e check" >/dev/null
sleep 2
PAYLOAD="$(curl -fsS "$BASE_URL/admin/mails?address=${TEST_ADDRESS}&limit=20&offset=0" -H "x-admin-auth: ${TEMP_MAIL_ADMIN_PASSWORD}")"

if ! printf '%s' "$PAYLOAD" | grep -Fq "$TEST_SUBJECT"; then
  printf '%s
' "$PAYLOAD" >&2
  echo "端到端测试失败：未查到测试邮件" >&2
  exit 1
fi

echo "端到端测试通过: ${TEST_ADDRESS}"
