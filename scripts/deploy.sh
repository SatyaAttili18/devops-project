#!/usr/bin/env bash
set -euo pipefail

APP_NAME="demo-app"          # docker image name prefix
BLUE_PORT=3000
GREEN_PORT=3001

# Decide which color to deploy (look at current upstream set in the site file)
CURRENT_PORT=$(grep -o '127\.0\.0\.1:[0-9]\+' /etc/nginx/sites-available/devops-app \
  | head -1 | cut -d: -f2 || true)

if [[ "$CURRENT_PORT" == "$BLUE_PORT" ]]; then
  TARGET_COLOR="green"
  TARGET_PORT=$GREEN_PORT
else
  TARGET_COLOR="blue"
  TARGET_PORT=$BLUE_PORT
fi

echo "Current live port: ${CURRENT_PORT:-none}"
echo "Deploying target color: $TARGET_COLOR on $TARGET_PORT"

# Clean any container already bound to target port
EXISTING_ID=$(docker ps --filter "publish=$TARGET_PORT" --format '{{.ID}}' || true)
if [[ -n "$EXISTING_ID" ]]; then
  echo "Stopping existing $TARGET_COLOR container on $TARGET_PORT..."
  docker rm -f "$EXISTING_ID" || true
fi

# Image to run is passed as first arg: e.g., demo-app:build-7
IMAGE="${1:?Image tag required, e.g. demo-app:build-42}"
echo "Starting container: $IMAGE on port $TARGET_PORT ..."
docker run -d --name "app-$TARGET_COLOR" -p ${TARGET_PORT}:3000 "$IMAGE"

# Health check the new color
echo "Health check http://127.0.0.1:$TARGET_PORT ..."
for i in {1..20}; do
  if curl -fsS "http://127.0.0.1:$TARGET_PORT" >/dev/null; then
    echo "Health check passed."
    HEALTHY=1
    break
  fi
  echo "Waiting for app... ($i/20)"; sleep 2
done

if [[ "${HEALTHY:-0}" -ne 1 ]]; then
  echo "Health check FAILED. Not switching traffic."
  exit 1
fi

# Flip Nginx to point to the healthy target (we keep the 'set $app_upstream' inside the site file)
sudo sed -i "s|set \$app_upstream \".*\";|set \$app_upstream \"http://127.0.0.1:${TARGET_PORT}\";|" \
  /etc/nginx/sites-available/devops-app
sudo nginx -t && sudo systemctl reload nginx
echo "Switched traffic to $TARGET_COLOR ($TARGET_PORT)."
