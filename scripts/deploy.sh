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

TARGET_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
mkdir -p "$TARGET_ROOT"
mkdir -p "${TEMP_MAIL_DATA_DIR:-${TARGET_ROOT}/data}"

if [[ "$PROJECT_ROOT" != "$TARGET_ROOT" ]]; then
  if ! command -v rsync >/dev/null 2>&1; then
    echo "当前仓库不在 ${TARGET_ROOT}，且系统缺少 rsync；请先安装 rsync 或直接把仓库放到 ${TARGET_ROOT}" >&2
    exit 1
  fi
  rsync -a --delete     --exclude '.git'     --exclude '.venv'     --exclude '__pycache__'     "$PROJECT_ROOT/" "$TARGET_ROOT/"
fi

cd "$TARGET_ROOT"
report() {
  echo
  ./scripts/post_deploy_report.sh || true
}
trap report EXIT

./scripts/bootstrap_ubuntu.sh
./scripts/preflight.sh
./scripts/apply_postfix_config.sh
./scripts/install_service.sh
./scripts/setup_cron.sh
./scripts/test_end_to_end.sh

echo '部署完成'
