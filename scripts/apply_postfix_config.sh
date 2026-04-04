#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

TEMP_MAIL_DOMAIN="${TEMP_MAIL_DOMAIN:?请设置 TEMP_MAIL_DOMAIN，例如 temp-mail.example.com}"
TEMP_MAIL_ROOT="${TEMP_MAIL_ROOT:-/opt/temp-mail}"
PIPE_TARGET="/bin/bash -c 'set -a; source ${TEMP_MAIL_ROOT}/.env; set +a; ${TEMP_MAIL_ROOT}/venv/bin/python ${TEMP_MAIL_ROOT}/app/mail_ingest.py'"
ESCAPED_DOMAIN="${TEMP_MAIL_DOMAIN//./\\.}"
ALIAS_LINE="tempmail: \"|${PIPE_TARGET}\""
SED_ALIAS_LINE="$(printf '%s' "$ALIAS_LINE" | sed 's/[\\/&]/\\&/g')"

postconf -e "myhostname = ${TEMP_MAIL_DOMAIN}"
postconf -e "virtual_alias_domains = ${TEMP_MAIL_DOMAIN}"
postconf -e 'virtual_alias_maps = regexp:/etc/postfix/virtual_alias_regexp'
postconf -e 'myorigin = /etc/mailname'

cat > /etc/postfix/virtual_alias_regexp <<POSTFIXEOF
/^.+@${ESCAPED_DOMAIN}$/ tempmail
POSTFIXEOF

if grep -q '^tempmail:' /etc/aliases; then
  sed -i.bak -E "s#^tempmail:.*#${SED_ALIAS_LINE}#" /etc/aliases
else
  printf '\n%s\n' "$ALIAS_LINE" >> /etc/aliases
fi

printf '%s\n' "$TEMP_MAIL_DOMAIN" > /etc/mailname
newaliases
systemctl restart postfix
systemctl status postfix --no-pager
