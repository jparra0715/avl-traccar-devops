#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
BUCKET="${BACKUP_BUCKET:-avl-traccar-backups-prod}"
TARGET_CONTAINER="${RESTORE_PG_CONTAINER:-floci-rds-traccar-db-uat}"
TARGET_DB="${RESTORE_TARGET_DB:-traccar_restore_test}"
BACKUP_KEY="${1:-}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

if [[ -z "$BACKUP_KEY" ]]; then
  LATEST_FILE=$(aws --endpoint-url="$ENDPOINT" s3 ls "s3://${BUCKET}/postgres/" | awk '{print $4}' | grep '\.sql\.gz$' | sort | tail -n 1)
  if [[ -z "$LATEST_FILE" ]]; then
    echo "ERROR: No hay respaldos .sql.gz en s3://${BUCKET}/postgres/"
    exit 1
  fi
  BACKUP_KEY="postgres/${LATEST_FILE}"
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$TARGET_CONTAINER"; then
  echo "Aviso: ${TARGET_CONTAINER} no esta activo; usando floci-rds-traccar-db-prod con base aislada ${TARGET_DB}."
  TARGET_CONTAINER="floci-rds-traccar-db-prod"
fi

DB_USER=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$TARGET_CONTAINER" | awk -F= '$1=="POSTGRES_USER"{print $2}')
DB_USER="${DB_USER:-traccar}"
TMP_FILE="/tmp/restore-$(basename "$BACKUP_KEY")"

START_TS=$(date +%s)

echo "[1/4] Descargando s3://${BUCKET}/${BACKUP_KEY} ..."
aws --endpoint-url="$ENDPOINT" s3 cp "s3://${BUCKET}/${BACKUP_KEY}" "$TMP_FILE"
gzip -t "$TMP_FILE"

echo "[2/4] Recreando base limpia ${TARGET_DB} en ${TARGET_CONTAINER}..."
docker exec "$TARGET_CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${TARGET_DB}' AND pid <> pg_backend_pid();" >/dev/null
docker exec "$TARGET_CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS ${TARGET_DB};"
docker exec "$TARGET_CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE ${TARGET_DB};"

echo "[3/4] Restaurando dump SQL en ${TARGET_DB}..."
gunzip -c "$TMP_FILE" | docker exec -i "$TARGET_CONTAINER" psql -U "$DB_USER" -d "$TARGET_DB" -v ON_ERROR_STOP=1 >/dev/null

echo "[4/4] Verificando tablas y registros restaurados:"
docker exec "$TARGET_CONTAINER" psql -U "$DB_USER" -d "$TARGET_DB" -c "
SELECT
  (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') AS total_tablas,
  (SELECT count(*) FROM tc_servers) AS servidores,
  (SELECT count(*) FROM tc_users) AS usuarios,
  (SELECT count(*) FROM tc_devices) AS dispositivos,
  (SELECT count(*) FROM tc_positions) AS posiciones;
"

ELAPSED=$(( $(date +%s) - START_TS ))
rm -f "$TMP_FILE"
echo "OK: Restauracion verificada en ${TARGET_CONTAINER}/${TARGET_DB} en ${ELAPSED}s."
