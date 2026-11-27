#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://localhost:8082}"
RETRIES="${2:-25}"
SLEEP_SECS="${3:-3}"

echo "Iniciando prueba de humo contra ${URL}/api/server ..."

for i in $(seq 1 "$RETRIES"); do
  BODY=$(curl -sS --max-time 5 "${URL}/api/server" 2>/dev/null || true)
  VERSION=$(echo "$BODY" | jq -r '.version // empty' 2>/dev/null || true)

  if [[ -n "$VERSION" ]]; then
    echo "OK: Traccar respondio en intento ${i}/${RETRIES} (version: ${VERSION})"
    exit 0
  fi

  echo "Intento ${i}/${RETRIES}: sin respuesta valida aun, esperando ${SLEEP_SECS}s..."
  sleep "$SLEEP_SECS"
done

echo "ERROR: Traccar no respondio en ${URL}/api/server despues de ${RETRIES} intentos."
exit 1
