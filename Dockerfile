FROM traccar/traccar:6.5-alpine

LABEL org.opencontainers.image.source="https://github.com/jparra0715/avl-traccar-devops"
LABEL org.opencontainers.image.description="Traccar AVL sobre PostgreSQL - Prueba tecnica Finanzauto"

RUN apk update && apk upgrade --no-cache

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8082/api/server || exit 1
