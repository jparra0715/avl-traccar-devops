# Arquitectura y Decisiones Técnicas (ADR)

## 1. Arquitectura General

La plataforma separa completamente cómputo, persistencia, respaldos y observabilidad en tres ambientes independientes (`dev`, `uat`, `prod`) gestionados mediante un único módulo Terraform (`infra/modules/traccar`).

- **Cómputo (ECS en Floci):** cada ambiente corre su propio clúster (`traccar-cluster-{env}`), servicio y definición de tarea versionada (`traccar-{env}:N`).
- **Base de datos (RDS PostgreSQL 16):** instancia aislada por ambiente (`traccar-db-{env}`), privada (`publicly_accessible = false`) y con cifrado de almacenamiento habilitado (`storage_encrypted = true`).
- **Respaldos (S3):** bucket dedicado por ambiente (`avl-traccar-backups-{env}`) con bloqueo total de acceso público (`aws_s3_bucket_public_access_block`).
- **Enrutamiento local:** `traccar-proxy` (Nginx) descubre dinámicamente la IP bridge de cada contenedor ECS y publica tanto la interfaz/API (8082-8084) como la ingesta GPS OsmAnd (5055-5057).

## 2. Flujo CI/CD y Gobierno de Rama

- **`main` protegida:** exige Pull Request y los 5 checks del CI en verde (Terraform fmt y validate en dev/uat/prod, Escaneo seguridad IaC (Trivy) y Construir y escanear imagen Docker), sin bypass para administradores.
- **CI (`.github/workflows/ci.yml`):** valida formato, sintaxis, seguridad IaC e imagen Docker. Al hacer merge a `main`, publica la imagen inmutable etiquetada por `GITHUB_SHA` en GHCR.
- **CD (`.github/workflows/cd.yml`):** se dispara tras CI exitoso, ejecuta despliegue y `smoke-test.sh` contra PostgreSQL 16 en dev -> uat, y solicita aprobación manual antes de promover a prod.
- **Dependabot:** monitorea semanalmente Dockerfile, módulos/ambientes de Terraform y GitHub Actions.

## 3. Observabilidad (Métricas, Logs y Alertas)

- **Disponibilidad y latencia:** Blackbox Exporter sondea `/api/server` en dev, uat y prod cada 10s.
- **Métricas de contenedores:** OpenTelemetry Collector (`docker_stats`) recolecta CPU y RAM desde `/var/run/docker.sock` y las expone en `:8889` para Prometheus.
- **Logs centralizados:** Promtail descubre contenedores vía `docker.sock` y envía logs a Loki.
- **Alertas y visualización:** Prometheus evalúa 4 reglas (`TraccarProdDown`, `TraccarNonProdDown`, `TraccarProdHighLatency`, `ContainerHighMemory`) y las enruta a Alertmanager. Grafana aprovisiona datasources y el tablero *AVL Traccar - Observabilidad Operativa* como código.

## 4. Registro de Decisiones de Arquitectura (ADR)

### ADR-01: Reemplazo de cAdvisor por OpenTelemetry Collector (`docker_stats`)

- **Contexto:** al desplegar cAdvisor v0.49.1 en el host Ubuntu, el colector falló al registrar los contenedores con el error `open /rootfs/var/lib/docker/image/overlayfs/layerdb/mounts/<id>/mount-id: no such file or directory`.
- **Causa raíz:** Docker utiliza el snapshotter overlayfs de containerd, donde la ruta heredada `layerdb/mounts` ya no existe; cAdvisor aborta la creación del contenedor en memoria incluso deshabilitando `--disable_metrics=disk`.
- **Decisión:** sustituir cAdvisor por `otel/opentelemetry-collector-contrib` con el receptor `docker_stats` y exportador `prometheus` (`translation_strategy: UnderscoreEscapingWithoutSuffixes` y `resource_constant_labels`).
- **Resultado:** métricas reales de CPU y RAM para todos los contenedores Traccar, RDS y Nginx sin depender del storage driver del host.

### ADR-02: Endurecimiento IaC y excepciones documentadas en `.trivyignore`

- **Decisión:** se corrigieron en código 18 de los 21 hallazgos HIGH iniciales de Trivy (bloqueo público S3, RDS privado y `storage_encrypted = true`). Solo se documentaron dos excepciones justificadas en `.trivyignore`:
  - **AVD-AWS-0132** (SSE-KMS con CMK en S3): limitación del emulador local Floci; en AWS productivo se activa una CMK dedicada.
  - **CVE-2026-75595** (`netty-handler-4.1.113.Final.jar` en `traccar/traccar:6.5-alpine`): vulnerabilidad de SNI bypass en TLS directo; mitigada arquitectónicamente porque Traccar no termina TLS directamente (la terminación TLS ocurre en el proxy/ALB).

### ADR-03: Reemplazo limpio de contenedor en rollback sobre Floci

- **Contexto:** `aws ecs update-service --force-new-deployment` actualiza la revisión en Floci, pero mantiene corriendo el contenedor anterior si no se detiene la tarea.
- **Decisión:** `scripts/rollback-prod.sh` baja `desired-count` a 0, detiene la tarea activa (`stop-task`), sube nuevamente a 1 con la revisión/imagen destino, reconfigura Nginx y valida `/api/server` con `smoke-test.sh`.
- **Resultado:** tiempo medido de rollback completo: 46 segundos (objetivo < 300s).
