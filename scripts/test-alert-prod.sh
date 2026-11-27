#!/usr/bin/env bash
set -euo pipefail

PROD_CONTAINER=$(docker ps --filter "name=traccar-prod" --format '{{.Names}}' | head -n 1 || true)
if [[ -z "$PROD_CONTAINER" ]]; then
  echo "ERROR: No encuentro contenedor activo de Traccar PROD."
  exit 1
fi

recuperar() {
  echo ""
  echo "[Recuperacion] Iniciando ${PROD_CONTAINER} nuevamente..."
  docker start "$PROD_CONTAINER" >/dev/null 2>&1 || true
  ./scripts/expose-envs.sh >/dev/null
  ./scripts/smoke-test.sh http://localhost:8084 30 3
}
trap recuperar EXIT

echo "[1/4] Verificando estado inicial en Prometheus (prod debe ser 1)..."
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=probe_success{env="prod"}' \
  | jq -r '.data.result[] | "      prod = \(.value[1])"'

echo "[2/4] Simulando caida controlada de PROD (deteniendo ${PROD_CONTAINER})..."
docker stop "$PROD_CONTAINER" >/dev/null

echo "[3/4] Esperando que Prometheus dispare TraccarProdDown (for: 15s, max ~75s)..."
FIRED=0
for i in $(seq 1 15); do
  STATE=$(curl -s 'http://localhost:9090/api/v1/alerts' \
    | jq -r '.data.alerts[] | select(.labels.alertname=="TraccarProdDown") | .state' | head -n 1)
  echo "      Intento ${i}/15 -> estado en Prometheus: ${STATE:-sin alerta aun}"
  if [[ "$STATE" == "firing" ]]; then
    FIRED=1
    break
  fi
  sleep 5
done

if [[ "$FIRED" -ne 1 ]]; then
  echo "ERROR: La alerta TraccarProdDown no llego a estado firing."
  exit 1
fi

echo ""
echo "=== Alerta activa en Prometheus ==="
curl -s 'http://localhost:9090/api/v1/alerts' \
  | jq '.data.alerts[] | select(.labels.alertname=="TraccarProdDown") | {alert: .labels.alertname, severity: .labels.severity, state: .state, summary: .annotations.summary}'

sleep 6
echo "=== Alerta recibida en Alertmanager ==="
curl -s 'http://localhost:9093/api/v2/alerts' \
  | jq '.[] | select(.labels.alertname=="TraccarProdDown") | {alert: .labels.alertname, status: .status.state, summary: .annotations.summary}'

echo "[4/4] Recuperando servicio y verificando cierre de alerta..."
trap - EXIT
recuperar

for i in $(seq 1 12); do
  STATE=$(curl -s 'http://localhost:9090/api/v1/alerts' \
    | jq -r '.data.alerts[] | select(.labels.alertname=="TraccarProdDown") | .state' | head -n 1)
  if [[ -z "$STATE" ]]; then
    echo "OK: Alerta TraccarProdDown resuelta y PROD operando normal."
    exit 0
  fi
  sleep 5
done

echo "Aviso: PROD ya respondio OK; la alerta tardara unos segundos mas en limpiarse de Prometheus."
