#!/usr/bin/env bash
set -euo pipefail

BLUE_PORT=3000
GREEN_PORT=3001
SITE_FILE="/etc/nginx/sites-available/devops-app"

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo "ERROR: This script needs passwordless sudo for nginx/systemctl/sed. See sudoers setup." >&2
    exit 1
  fi
}

current_port() {
  grep -Eo '127\.0\.0\.1:[0-9]+' "$SITE_FILE" | head -1 | cut -d: -f2
}

switch_nginx_to_port() {
  local port="$1"
  sudo -n sed -i "s|set \$app_upstream \".*\";|set \$app_upstream \"http://127.0.0.1:${port}\";|" "$SITE_FILE"
  sudo -n nginx -t
  sudo -n systemctl reload nginx
}

main() {
  require_sudo
  if [[ ! -f "$SITE_FILE" ]]; then
    echo "ERROR: Nginx site file not found: $SITE_FILE" >&2
    exit 1
  fi

  local cur target
  cur="$(current_port)"
  if [[ "$cur" == "$BLUE_PORT" ]]; then
    target="$GREEN_PORT"
  else
    target="$BLUE_PORT"
  fi

  echo "Rolling back traffic to port $target ..."
  switch_nginx_to_port "$target"
  echo "Rollback complete."
}

main "$@"
