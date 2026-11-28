# Informe de Ejecucion - Prueba Tecnica DevOps AVL Traccar

## 1. Tiempo Real Invertido por Bloque
El plan de referencia estimaba 4 horas. Con transparencia, la dedicacion real total fue de aproximadamente 6 horas y 45 minutos, incluyendo la preparacion de la maquina virtual base, depuracion real sobre Floci, endurecimiento de Trivy y migracion de metricas a OpenTelemetry Collector:

| Bloque | Estimado | Real | Observaciones clave |
| :--- | :---: | :---: | :--- |
| 1. Entorno base (VM Ubuntu, Docker, Floci, Traccar + PG16) | 30 min | 50 min | Acondicionamiento del host, red bridge y proxy Nginx dinamico. |
| 2. IaC Terraform (modulo unico Dev/UAT/Prod + estado S3) | 60 min | 1 h 15 min | Estado remoto separado por ambiente y endurecimiento RDS/S3. |
| 3. Pipelines CI/CD (Trivy, GHCR SHA, Environments, Dependabot) | 60 min | 1 h 30 min | Solucion de 21 hallazgos Trivy, contenedor oficial y proteccion main. |
| 4. Operacion Prod (Observabilidad, Backups, Rollback, GPS) | 45 min | 2 h 10 min | Fix DROP DATABASE, stop-task en Floci, migracion cAdvisor -> OTel y OsmAnd API. |
| 5. Documentacion, diagrama SVG y pruebas finales | 45 min | 1 h 00 min | Diagrama propio, bitacora con evidencia real, runbook e informe. |
| Total | 4 h 00 min | 6 h 45 min | 9 requisitos obligatorios + 3 bonus operativos y verificados. |

## 2. Decisiones Tecnicas y Alternativas Descartadas
1. OpenTelemetry Collector (docker_stats) en lugar de cAdvisor: cAdvisor v0.49.1 fallo bajo el snapshotter overlayfs de containerd. OTel Collector lee directo desde /var/run/docker.sock y entrega CPU y RAM reales a Prometheus (traccar-prod ~792 MiB, RDS 37-57 MiB).
2. Contenedor oficial de Trivy en lugar de accion del marketplace: elimino desfases de version y aseguro paridad entre local y CI.
3. Proxy Nginx dinamico (scripts/expose-envs.sh) en lugar de ALB emulado: descubre las IPs bridge de cada contenedor ECS y publica Web/API (8082-8084) y OsmAnd (5055-5057) tras cada despliegue o rollback.
4. Reciclaje limpio de tarea en rollback (desired-count 0 -> 1 + stop-task): reemplazo real del contenedor en Floci con smoke test verificado en 46 segundos (objetivo menor a 5 minutos).
5. Stack Prometheus + Alertmanager + Loki + Grafana en lugar de solo CloudWatch emulado: permite alertas reales evaluadas cada 10s, logs centralizados y tablero aprovisionado como codigo.

## 3. Riesgos y Ajustes Necesarios al Migrar a AWS Real
1. Secretos en ECS: En AWS productivo las credenciales deben residir en AWS Secrets Manager o SSM Parameter Store e inyectarse mediante el campo secrets de la task definition con rol ecsTaskExecutionRole de minimo privilegio y rotacion automatica.
2. Cifrado KMS con CMK en S3 (AVD-AWS-0132): En AWS real se elimina la excepcion de Floci y se habilita SSE-KMS con clave administrada por cliente (CMK), versionamiento, Object Lock y politicas de ciclo de vida hacia Glacier.
3. Perimetro, red privada y TLS (CVE-2026-75595): Ubicar ECS y RDS en subredes privadas sin IP publica, detras de un ALB con certificado ACM (TLS 1.3) y WAF para HTTP/API, mas un NLB dedicado para puertos TCP/UDP de protocolos GPS.
4. Alta disponibilidad de datos: Migrar RDS a despliegue Multi-AZ con Point-In-Time Recovery (PITR), snapshots replicados entre regiones y restauraciones periodicas automatizadas.
5. Bloqueo de estado Terraform y autenticacion OIDC: Habilitar state locking (S3 lockfile o DynamoDB) y sustituir credenciales estaticas en CI/CD por GitHub OIDC asumiendo roles IAM acotados por ambiente.
6. Estrategia de despliegue sin corte: Implementar Blue/Green o Rolling con ECS Deployment Circuit Breaker y CodeDeploy para rollback automatico ante degradacion de healthchecks.
