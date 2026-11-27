# Runbook Operativo — AVL Traccar

## 1. Verificación rápida de salud

```bash
./scripts/smoke-test.sh http://localhost:8082
./scripts/smoke-test.sh http://localhost:8083
./scripts/smoke-test.sh http://localhost:8084
```

## 2. Respaldo y restauración verificada (S3)

```bash
# Generar pg_dump comprimido de Prod y subirlo a s3://avl-traccar-backups-prod/postgres/
./scripts/backup-prod.sh

# Descargar el último backup de S3 y restaurarlo en base aislada (traccar_restore_test en UAT)
./scripts/restore-backup.sh
```

**Criterio de éxito:** el script confirma 48 tablas restauradas y conteo de `tc_servers`, `tc_users`, `tc_devices` y `tc_positions` en ~5 segundos.

## 3. Rollback de producción (< 5 minutos)

### Opción A: rollback inmediato a la revisión anterior en Floci

```bash
./scripts/rollback-prod.sh
# O hacia una revisión específica:
./scripts/rollback-prod.sh traccar-prod:1
```

### Opción B: rollback hacia una imagen inmutable por SHA en GHCR

```bash
./scripts/rollback-prod.sh --image ghcr.io/jparra0715/avl-traccar-devops:<SHA>
```

### Opción C: rollback auditado desde GitHub Actions

1. Ir a **Actions -> Rollback - Prod Traccar -> Run workflow**.
2. Ingresar `target_image_tag` (SHA estable anterior) y `reason`.
3. Aprobar el despliegue en el environment `prod`.

## 4. Prueba controlada de alerta (`TraccarProdDown`)

```bash
./scripts/test-alert-prod.sh
```

Detiene el contenedor de Prod, espera a que Prometheus cambie `TraccarProdDown` a *firing* y llegue a Alertmanager, reinicia el contenedor, reconfigura Nginx, valida `/api/server` y confirma la resolución de la alerta.

## 5. Simulación de telemetría GPS (OsmAnd)

```bash
./scripts/simulate-gps.sh prod AVL-FINANZAUTO-001 5
```

Registra el vehículo vía API si no existe, envía 5 tramas HTTP OsmAnd al puerto 5057 y valida las filas insertadas en `tc_positions`.
