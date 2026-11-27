#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
CLUSTER="${ECS_CLUSTER:-traccar-cluster-prod}"
FAMILY="${ECS_FAMILY:-traccar-prod}"
PROD_URL="${PROD_URL:-http://localhost:8084}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

START_TS=$(date +%s)

SERVICE_ARN=$(aws --endpoint-url="$ENDPOINT" ecs list-services --cluster "$CLUSTER" --query 'serviceArns[0]' --output text)
if [[ -z "$SERVICE_ARN" || "$SERVICE_ARN" == "None" ]]; then
  echo "ERROR: No se encontro ningun servicio ECS en el cluster ${CLUSTER}."
  exit 1
fi
SERVICE_NAME="${SERVICE_ARN##*/}"

CURRENT_TD=$(aws --endpoint-url="$ENDPOINT" ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE_NAME" \
  --query 'services[0].taskDefinition' --output text)

echo "Servicio ECS    : ${CLUSTER} / ${SERVICE_NAME}"
echo "Revision actual : ${CURRENT_TD}"

TARGET_TD=""

if [[ "${1:-}" == "--image" ]]; then
  TARGET_IMAGE="${2:-}"
  if [[ -z "$TARGET_IMAGE" ]]; then
    echo "Uso: $0 --image <imagen:tag>"
    exit 1
  fi
  echo "[1/5] Registrando nueva revision en ${FAMILY} con imagen ${TARGET_IMAGE}..."
  TASK_JSON=$(aws --endpoint-url="$ENDPOINT" ecs describe-task-definition --task-definition "$CURRENT_TD")
  NEW_CONTAINERS=$(echo "$TASK_JSON" | jq -c --arg img "$TARGET_IMAGE" '.taskDefinition.containerDefinitions | map(.image = $img)')
  CPU=$(echo "$TASK_JSON" | jq -r '.taskDefinition.cpu // "1024"')
  MEM=$(echo "$TASK_JSON" | jq -r '.taskDefinition.memory // "2048"')

  TARGET_TD=$(aws --endpoint-url="$ENDPOINT" ecs register-task-definition \
    --family "$FAMILY" \
    --cpu "$CPU" \
    --memory "$MEM" \
    --container-definitions "$NEW_CONTAINERS" \
    --query 'taskDefinition.taskDefinitionArn' --output text)
  echo "      Revision registrada: ${TARGET_TD}"
elif [[ -n "${1:-}" ]]; then
  TARGET_TD="$1"
else
  CUR_REV="${CURRENT_TD##*:}"
  if [[ "$CUR_REV" -le 1 ]]; then
    echo "ERROR: Prod esta en la revision 1. Indica una revision explicita o usa --image <imagen:tag>."
    exit 1
  fi
  PREV_REV=$((CUR_REV - 1))
  TARGET_TD="${FAMILY}:${PREV_REV}"
fi

echo "[2/5] Deteniendo tarea actual de Prod para reemplazo limpio..."
aws --endpoint-url="$ENDPOINT" ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE_NAME" \
  --desired-count 0 >/dev/null

RUNNING_TASKS=$(aws --endpoint-url="$ENDPOINT" ecs list-tasks \
  --cluster "$CLUSTER" --service-name "$SERVICE_NAME" \
  --query 'taskArns[]' --output text || true)

for task in $RUNNING_TASKS; do
  [[ "$task" == "None" || -z "$task" ]] && continue
  aws --endpoint-url="$ENDPOINT" ecs stop-task --cluster "$CLUSTER" --task "$task" >/dev/null 2>&1 || true
done

# Garantizar limpieza de contenedores anteriores de Prod en Floci
for c in $(docker ps -a --filter "name=traccar-prod" --format '{{.Names}}'); do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

echo "[3/5] Levantando ${SERVICE_NAME} con ${TARGET_TD} (desired-count=1)..."
aws --endpoint-url="$ENDPOINT" ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE_NAME" \
  --task-definition "$TARGET_TD" \
  --desired-count 1 \
  --force-new-deployment >/dev/null

# Esperar a que aparezca el nuevo contenedor de Traccar Prod
for i in $(seq 1 20); do
  NEW_CONTAINER=$(docker ps --filter "name=traccar-prod" --format '{{.Names}}' | head -n 1 || true)
  if [[ -n "$NEW_CONTAINER" ]]; then
    echo "      Contenedor nuevo activo: ${NEW_CONTAINER}"
    break
  fi
  sleep 2
done

echo "[4/5] Reconfigurando proxy Nginx hacia el nuevo contenedor..."
./scripts/expose-envs.sh >/dev/null

echo "[5/5] Ejecutando prueba de humo en ${PROD_URL}..."
./scripts/smoke-test.sh "$PROD_URL" 35 3

ELAPSED=$(( $(date +%s) - START_TS ))
FINAL_TD=$(aws --endpoint-url="$ENDPOINT" ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE_NAME" \
  --query 'services[0].taskDefinition' --output text)

echo "OK: Cambio/Rollback completado hacia ${FINAL_TD} en ${ELAPSED}s (objetivo < 300s)."
docker ps --filter "name=traccar-prod" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
