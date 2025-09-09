#!/usr/bin/env bash
set -euo pipefail

APP_NAME="demo-app"          # docker image name prefix (for display only)
BLUE_PORT=3000
GREEN_PORT=3001
SITE_FILE="/etc/nginx/sites-available/devops-app"

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo "ERROR: This script needs passwordless sudo for nginx/systemctl/tee/sed. See sudoers setup." >&2
    exit 1
  fi
}

ensure_site_exists() {
  if [[ ! -f "$SITE_FILE" ]]; then
    echo "Nginx site missing, creating base file..."
    sudo -n tee "$SITE_FILE" >/dev/null <<'EOF'
set $app_upstream "http://127.0.0.1:3000";
server {
  listen 80 default_server;
  server_name _;
  location / {
    proxy_pass $app_upstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
EOF
    sudo -n ln -sf "$SITE_FILE" /etc/nginx/sites-enabled/devops-app
    sudo -n nginx -t && sudo -n systemctl reload nginx
  fi
}

current_port() {
  # Try to read from the set $app_upstream line; fallback to proxy_pass if needed
  local p=""
  p=$(grep -Eo '127\.0\.0\.1:[0-9]+' "$SITE_FILE" | head -1 | cut -d: -f2 || true)
  echo "${p:-}"
}

stop_container_on_port() {
  local port="$1"
  # Find any container publishing this port and remove it
  local id
  id=$(docker ps --format '{{.ID}} {{.Ports}}' | awk -v p="$port" 'index($0, ":"p+"->")>0 {print $1; exit}')
  if [[ -n "${id:-}" ]]; then
    echo "Stopping existing container on port $port (id=$id)..."
    docker rm -f "$id" || true
  fi
}

switch_nginx_to_port() {
  local port="$1"
  sudo -n sed -i "s|set \$app_upstream \".*\";|set \$app_upstream \"http://127.0.0.1:${port}\";|" "$SITE_FILE"
  sudo -n nginx -t
  sudo -n systemctl reload nginx
}

main() {
  require_sudo
  ensure_site_exists

  # Image to run is passed as first arg: e.g., demo-app:build-42
  local image="${1:?Image tag required, e.g. demo-app:build-42}"

  local cur port color
  cur="$(current_port || true)"
  if [[ "$cur" == "$BLUE_PORT" ]]; then
    color="green"; port="$GREEN_PORT"
  else
    color="blue";  port="$BLUE_PORT"
  fi

  echo "Current live port: ${cur:-none}"
  echo "Deploying target color: $color on $port"

  stop_container_on_port "$port"

  echo "Starting container: $image on port $port ..."
  # Always recreate the color-named container so names are consistent
  docker rm -f "app-$color" >/dev/null 2>&1 || true
  docker run -d --name "app-$color" -p ${port}:3000 "$image"

  echo "Health check http://127.0.0.1:$port ..."
  local healthy=0
  for i in {1..20}; do
    if curl -fsS "http://127.0.0.1:$port" >/dev/null; then
      echo "Health check passed."
      healthy=1; break
    fi
    echo "Waiting for app... ($i/20)"; sleep 2
  done

  if [[ "$healthy" -ne 1 ]]; then
    echo "Health check FAILED. Not switching traffic."
    exit 1
  fi

  switch_nginx_to_port "$port"
  echo "Switched traffic to $color ($port)."
}

main "$@"
