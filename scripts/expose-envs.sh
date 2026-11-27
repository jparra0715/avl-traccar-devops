#!/usr/bin/env bash
set -euo pipefail

get_ip() {
  local env="$1"
  local cid
  cid=$(docker ps --filter "name=traccar-${env}" --format "{{.ID}}" | head -n 1)
  if [ -z "$cid" ]; then
    echo "ERROR: No se encontró contenedor activo para traccar-${env}" >&2
    exit 1
  fi
  docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' "$cid"
}

DEV_IP=$(get_ip dev)
UAT_IP=$(get_ip uat)
PROD_IP=$(get_ip prod)

echo "IPs detectadas -> dev: $DEV_IP | uat: $UAT_IP | prod: $PROD_IP"

cat <<NGINX > /tmp/traccar-proxy.conf
events {}
http {
  server {
    listen 8082;
    location / {
      proxy_pass http://${DEV_IP}:8082;
      proxy_set_header Host \$host;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
    }
  }
  server {
    listen 8083;
    location / {
      proxy_pass http://${UAT_IP}:8082;
      proxy_set_header Host \$host;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
    }
  }
  server {
    listen 8084;
    location / {
      proxy_pass http://${PROD_IP}:8082;
      proxy_set_header Host \$host;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
    }
  }
}
NGINX

docker rm -f traccar-proxy 2>/dev/null || true
docker run -d --name traccar-proxy \
  --network bridge \
  -p 8082:8082 -p 8083:8083 -p 8084:8084 \
  -v /tmp/traccar-proxy.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine

echo "Proxy listo: http://localhost:8082 (dev) | :8083 (uat) | :8084 (prod)"
