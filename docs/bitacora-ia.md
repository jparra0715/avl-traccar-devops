# Bitacora de Uso de IA - Prueba Tecnica DevOps AVL Traccar

## 1. Herramientas Utilizadas
- Gemini como copiloto tecnico para planeacion por bloques, borradores de Terraform, workflows, scripts y analisis de errores de consola.
- Verificacion empirica directa en Ubuntu Linux (docker, psql, curl, aws CLI contra Floci, Trivy local y GitHub Actions).

## 2. Prompts Clave Utilizados
1. Planeacion inicial: "Disena un plan por bloques para desplegar Traccar con PostgreSQL 16 en Dev, UAT y Prod sobre Floci usando un solo modulo de Terraform, CI/CD con GitHub Actions, observabilidad, backups a S3 y rollback en menos de 5 minutos."
2. Modularizacion IaC: "Crea un modulo reutilizable de Terraform en infra/modules/traccar que despliegue ECS, RDS PostgreSQL 16 y bucket S3 con estado remoto separado por ambiente."
3. Endurecimiento de seguridad: "Trivy reporto 21 hallazgos HIGH en Terraform y 1 CRITICAL en traccar:6.5-alpine. Corrige en el modulo todo lo aplicable a Floci y justifica tecnicamente solo las excepciones inevitables en .trivyignore."
4. Promocion inmutable CI/CD: "Configura ci.yml para validar IaC, escanear con Trivy y publicar imagen en GHCR etiquetada con GITHUB_SHA, y cd.yml para promover la misma imagen a Dev, UAT y Prod con aprobacion manual."
5. Operacion Prod y DR: "Implementa backup-prod.sh, restore-backup.sh sobre base aislada y rollback-prod.sh capaz de devolver Prod a una revision o SHA anterior en menos de 5 minutos verificando /api/server."
6. Diagnostico de metricas en overlayfs: "cAdvisor v0.49.1 falla con 'open /rootfs/var/lib/docker/image/overlayfs/layerdb/mounts/.../mount-id: no such file or directory' y deja vacios CPU/RAM en Prometheus. Reemplazalo por OpenTelemetry Collector con docker_stats."
7. Telemetria GPS OsmAnd: "El envio OsmAnd al puerto 5057 respondio HTTP 400. Ajusta simulate-gps.sh para aprovisionar usuario y dispositivo via API REST antes de enviar posiciones y validar la persistencia en tc_positions."

## 3. Casos Donde la IA Se Equivoco o Propuso Algo Inseguro/Incorrecto

### Caso 1: Modulo Terraform inicial con 21 hallazgos de severidad HIGH
- Error detectado: El primer borrador omitio aws_s3_bucket_public_access_block, dejo RDS sin publicly_accessible = false y sin storage_encrypted = true.
- Como se detecto: Al ejecutar Trivy IaC en local y en el Pull Request de CI.
- Accion tomada: Se corrigieron 18 hallazgos en infra/modules/traccar/main.tf sin desactivar el escaner; solo quedaron en .trivyignore AVD-AWS-0132 (limitacion de KMS CMK en Floci) y CVE-2026-75595 (mitigado por terminacion TLS en proxy).

### Caso 2: Accion de Trivy desfasada en GitHub Actions
- Error detectado: La accion del marketplace sugerida inicialmente fallo en el runner por incompatibilidad de version.
- Como se detecto: Fallo directo en el job de seguridad del CI.
- Accion tomada: Se reemplazo por el contenedor oficial ghcr.io/aquasecurity/trivy:latest con --ignorefile /src/.trivyignore, logrando paridad entre pruebas locales y CI.

### Caso 3: DROP DATABASE dentro de bloque transaccional en restore-backup.sh
- Error detectado: El script agrupaba DROP DATABASE y CREATE DATABASE en una sola invocacion psql -c, lo cual PostgreSQL rechaza dentro de una transaccion.
- Como se detecto: Error al ejecutar ./scripts/restore-backup.sh contra floci-rds-traccar-db-uat.
- Accion tomada: Se separaron en llamadas psql -c independientes, logrando restauracion completa de 48 tablas en 5 segundos.

### Caso 4: cAdvisor incompatible con overlayfs y sintaxis obsoleta en OTel Collector
- Error detectado: Primero propuso cAdvisor v0.49.1 (incompatible con snapshotter overlayfs de containerd) y luego configuro otelcol-contrib con resource_to_telemetry_conversion y add_metric_suffixes, ya deshabilitados en v0.166.0.
- Como se detecto: Inspeccionando docker logs obs-cadvisor, docker logs obs-otel-collector y el target down (connection refused) en Prometheus.
- Accion tomada: Se actualizo a translation_strategy: UnderscoreEscapingWithoutSuffixes y resource_constant_labels, verificando metricas reales en :8889 y :9090.

### Caso 5: Rollback en Floci sin reemplazo de contenedor y OsmAnd HTTP 400
- Error detectado: Asumio que ecs update-service --force-new-deployment reemplazaba el contenedor en Floci y que OsmAnd aceptaba tramas sin registrar el dispositivo.
- Como se detecto: docker ps mostraba el mismo contenedor tras el rollback y simulate-gps.sh recibia HTTP 400.
- Accion tomada: Se agrego ciclo desired-count 0 -> 1 con stop-task en rollback-prod.sh (46 segundos verificados) y alta automatica via API REST en simulate-gps.sh.

## 4. Que Se Verifico a Mano
- Aprovisionamiento de la maquina virtual Ubuntu (recursos, Docker Engine, Terraform, AWS CLI y red).
- Estado de contenedores (docker ps), logs (docker logs) e IPs bridge de cada servicio ECS y RDS en Floci.
- Consultas SQL directas con psql confirmando 48 tablas restauradas desde S3 y las 5 posiciones de AVL-FINANZAUTO-001 en tc_positions.
- Endpoints /api/server, targets up en Prometheus (:9090), alerta firing/resolved en Alertmanager (:9093), dashboards/logs en Grafana (:3000), rama main protegida y gate manual de prod en GitHub Actions.
