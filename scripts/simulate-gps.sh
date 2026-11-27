#!/usr/bin/env bash
set -euo pipefail

ENV_TARGET="${1:-prod}"
DEVICE_ID="${2:-AVL-FINANZAUTO-001}"
POINTS="${3:-5}"

ADMIN_EMAIL="${TRACCAR_ADMIN_EMAIL:-admin@avl.local}"
ADMIN_PASS="${TRACCAR_ADMIN_PASS:-Admin123!}"

case "$ENV_TARGET" in
  dev)  HTTP_PORT=8082; OSMAND_PORT=5055; PG_CONTAINER="floci-rds-traccar-db-dev";  DB_NAME="traccar_dev" ;;
  uat)  HTTP_PORT=8083; OSMAND_PORT=5056; PG_CONTAINER="floci-rds-traccar-db-uat";  DB_NAME="traccar_uat" ;;
  prod) HTTP_PORT=8084; OSMAND_PORT=5057; PG_CONTAINER="floci-rds-traccar-db-prod"; DB_NAME="traccar_prod" ;;
  *)
    echo "Uso: $0 [dev|uat|prod] [device_id] [puntos]"
    exit 1
    ;;
esac

API_URL="http://localhost:${HTTP_PORT}/api"
OSMAND_URL="http://localhost:${OSMAND_PORT}"

echo "[1/3] Asegurando usuario admin y dispositivo ${DEVICE_ID} en Traccar (${ENV_TARGET})..."
# Crea el primer usuario (admin) si la base esta vacia; ignora error si ya existe
curl -s -o /dev/null -X POST "${API_URL}/users" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Admin AVL\",\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" || true

# Verifica si el dispositivo ya esta registrado
EXISTS=$(curl -s -u "${ADMIN_EMAIL}:${ADMIN_PASS}" "${API_URL}/devices" \
  | jq -r --arg id "$DEVICE_ID" '.[] | select(.uniqueId == $id) | .id' | head -n 1 || true)

if [[ -z "$EXISTS" ]]; then
  CREATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/devices" \
    -u "${ADMIN_EMAIL}:${ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Vehiculo ${DEVICE_ID}\",\"uniqueId\":\"${DEVICE_ID}\"}")
  echo "      Dispositivo registrado via API (HTTP ${CREATE_CODE})"
else
  echo "      Dispositivo ya registrado (id=${EXISTS})"
fi

echo "[2/3] Enviando ${POINTS} posiciones GPS (OsmAnd) hacia ${OSMAND_URL}..."
LAT=6.1719
LON=-75.5863

for i in $(seq 1 "$POINTS"); do
  TS=$(date +%s)
  CUR_LAT=$(awk -v lat="$LAT" -v step="$i" 'BEGIN { printf "%.6f", lat + (step * 0.0012) }')
  CUR_LON=$(awk -v lon="$LON" -v step="$i" 'BEGIN { printf "%.6f", lon + (step * 0.0008) }')
  SPEED=$((20 + i * 5))

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${OSMAND_URL}/?id=${DEVICE_ID}&lat=${CUR_LAT}&lon=${CUR_LON}&timestamp=${TS}&speed=${SPEED}&batt=92")

  echo "      [${i}/${POINTS}] lat=${CUR_LAT} lon=${CUR_LON} speed=${SPEED}kn -> HTTP ${HTTP_CODE}"
  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: Traccar respondio HTTP ${HTTP_CODE} en puerto ${OSMAND_PORT}."
    exit 1
  fi
  sleep 1
done

echo "[3/3] Verificando persistencia en PostgreSQL (${PG_CONTAINER}/${DB_NAME})..."
DB_USER=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$PG_CONTAINER" | awk -F= '$1=="POSTGRES_USER"{print $2}')
DB_USER="${DB_USER:-traccar}"

docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT d.uniqueid, p.latitude, p.longitude, p.speed, p.fixtime
FROM tc_positions p
JOIN tc_devices d ON d.id = p.deviceid
WHERE d.uniqueid = '${DEVICE_ID}'
ORDER BY p.id DESC
LIMIT 5;
"

echo "OK: ${POINTS} tramas OsmAnd recibidas y persistidas en ${ENV_TARGET}."
