# AVL Traccar — Plataforma DevOps Multi-Ambiente (IaC + CI/CD + Observabilidad)

Plataforma operativa para **Traccar AVL** desplegada con **Terraform** sobre un emulador local de AWS (**Floci**), con ambientes aislados (`dev`, `uat`, `prod`), pipelines **CI/CD** en GitHub Actions con escaneo de seguridad (**Trivy** + **Dependabot**), respaldos verificados a **S3**, rollback controlado de producción en menos de 5 minutos, observabilidad completa (**Prometheus + Grafana + Loki + OpenTelemetry Collector**) y simulación de telemetría GPS por protocolo **OsmAnd**.

## Puertos y Accesos Locales

| Servicio | Ambiente / Rol | URL / Puerto | Credenciales / Notas |
| :--- | :--- | :--- | :--- |
| Traccar Web & API | `dev` | `http://localhost:8082` | Proxy Nginx -> ECS `traccar-dev` |
| Traccar Web & API | `uat` | `http://localhost:8083` | Proxy Nginx -> ECS `traccar-uat` |
| Traccar Web & API | `prod` | `http://localhost:8084` | `admin@avl.local` / `Admin123!` |
| OsmAnd GPS | `dev` / `uat` / `prod` | `5055` / `5056` / `5057` | Ingesta HTTP de tramas AVL |
| Floci (AWS local) | Emulador AWS | `http://localhost:4566` | ECS, RDS PostgreSQL 16, S3, CloudWatch |
| Grafana | Dashboards y Logs | `http://localhost:3000` | `admin` / `admin123` |
| Prometheus | Métricas y Alertas | `http://localhost:9090` | Reglas en `observability/prometheus/alerts.yml` |
| Alertmanager | Gestión de Alertas | `http://localhost:9093` | Receptor `ops-default` |

## Estructura del Repositorio

```text
.
├── .github/
│   ├── dependabot.yml            # Actualizaciones automáticas (Docker, Terraform, Actions)
│   └── workflows/
│       ├── ci.yml                # fmt, validate, Trivy IaC + Imagen, build/push GHCR
│       ├── cd.yml                # Promoción dev -> uat -> prod (aprobación manual en prod)
│       └── rollback.yml          # Rollback manual controlado por SHA inmutable
├── infra/
│   ├── modules/traccar/          # Módulo reutilizable (ECS, RDS, S3, Public Access Block)
│   └── envs/{dev,uat,prod}/      # Configuración aislada por ambiente
├── observability/                # Prometheus, Alertmanager, Blackbox, OTel Collector, Loki, Promtail, Grafana
├── scripts/
│   ├── expose-envs.sh            # Proxy Nginx dinámico hacia contenedores ECS (HTTP + OsmAnd)
│   ├── smoke-test.sh             # Validación automática contra /api/server
│   ├── backup-prod.sh            # pg_dump comprimido de Prod hacia S3
│   ├── restore-backup.sh         # Descarga desde S3 y restauración probada en base aislada
│   ├── rollback-prod.sh          # Rollback real de tarea ECS en Prod (< 60s)
│   ├── test-alert-prod.sh        # Caída controlada de Prod para validar alerta firing/resolved
│   └── simulate-gps.sh           # Registro de vehículo + envío de tramas OsmAnd + verificación SQL
└── docs/
    ├── ARQUITECTURA.md           # Diseño, flujo CI/CD y decisiones técnicas (ADR)
    ├── RUNBOOK.md                # Procedimientos operativos de despliegue, backup y rollback
    └── BITACORA_IA.md            # Registro de diagnóstico, errores reales y criterios aplicados
```

## Inicio Rápido Operativo

```bash
# 1. Levantar Floci y exponer ambientes
docker compose up -d
./scripts/expose-envs.sh

# 2. Levantar stack de observabilidad
docker compose -f observability/docker-compose.obs.yml up -d

# 3. Ejecutar pruebas operativas end-to-end
./scripts/smoke-test.sh http://localhost:8084
./scripts/simulate-gps.sh prod AVL-FINANZAUTO-001 5
./scripts/backup-prod.sh
./scripts/restore-backup.sh
./scripts/test-alert-prod.sh
```

## Documentación Detallada

- [Arquitectura y Decisiones Técnicas (ADR)](docs/ARQUITECTURA.md)
- [Runbook Operativo](docs/RUNBOOK.md)
- [Bitácora de Ingeniería e IA](docs/BITACORA_IA.md)
