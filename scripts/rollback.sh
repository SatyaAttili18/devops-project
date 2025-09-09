#!/usr/bin/env bash
set -euo pipefail

BLUE_PORT=3000
GREEN_PORT=3001

CUR_PORT=$(grep -o '127\.0\.0\.1:[0-9]\+' /etc/nginx/sites-available/devops-app \
  | head -1 | cut -d: -f2)

if [[ "$CUR_PORT" == "$BLUE_PORT" ]]; then
  TARGET_PORT=$GREEN_PORT
else
  TARGET_PORT=$BLUE_PORT
fi

echo "Rolling back traffic to port $TARGET_PORT ..."
sudo sed -i "s|set \$app_upstream \".*\";|set \$app_upstream \"http://127.0.0.1:${TARGET_PORT}\";|" \
  /etc/nginx/sites-available/devops-app
sudo nginx -t && sudo systemctl reload nginx
echo "Rollback complete."
