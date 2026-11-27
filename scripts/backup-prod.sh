#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
BUCKET="${BACKUP_BUCKET:-avl-traccar-backups-prod}"
PG_CONTAINER="${PROD_PG_CONTAINER:-floci-rds-traccar-db-prod}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="traccar-prod-${TIMESTAMP}.sql.gz"
TMP_PATH="/tmp/${BACKUP_FILE}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

if ! docker ps --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  echo "ERROR: No encuentro el contenedor PostgreSQL de Prod ($PG_CONTAINER) corriendo."
  exit 1
fi

DB_USER=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$PG_CONTAINER" | awk -F= '$1=="POSTGRES_USER"{print $2}')
DB_NAME=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$PG_CONTAINER" | awk -F= '$1=="POSTGRES_DB"{print $2}')
DB_USER="${DB_USER:-traccar}"
DB_NAME="${DB_NAME:-traccar_prod}"

echo "[1/3] Generando pg_dump de ${DB_NAME} (contenedor ${PG_CONTAINER})..."
docker exec "$PG_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" --no-owner --no-acl | gzip -c > "$TMP_PATH"

gzip -t "$TMP_PATH"
SIZE=$(du -h "$TMP_PATH" | awk '{print $1}')
echo "      Dump verificado localmente: ${TMP_PATH} (${SIZE})"

echo "[2/3] Subiendo respaldo a s3://${BUCKET}/postgres/${BACKUP_FILE} ..."
aws --endpoint-url="$ENDPOINT" s3 cp "$TMP_PATH" "s3://${BUCKET}/postgres/${BACKUP_FILE}"

echo "[3/3] Confirmando archivos en S3:"
aws --endpoint-url="$ENDPOINT" s3 ls "s3://${BUCKET}/postgres/" --human-readable

rm -f "$TMP_PATH"
echo "OK: Respaldo de Prod completado -> s3://${BUCKET}/postgres/${BACKUP_FILE}"
