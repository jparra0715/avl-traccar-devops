# AVL Traccar DevOps — Prueba Técnica Finanzauto

Despliegue de **Traccar 6.5** con **PostgreSQL 16** en tres ambientes aislados (`dev`, `uat` y `prod`), usando **Terraform** contra **Floci** (emulador local de AWS), imagen Docker propia en **GHCR** y flujos de **GitHub Actions**.

## Cómo está armado

* **Módulo único (`infra/modules/traccar`)**: en vez de repetir código, los tres ambientes llaman el mismo módulo cambiando solo recursos y retención. Cada ambiente crea su RDS PostgreSQL 16, clúster y servicio ECS, secreto en Secrets Manager, Log Group en CloudWatch y bucket S3 de backups.
* **Estados separados**: cada ambiente guarda su propio `terraform.tfstate` en el bucket S3 `avl-traccar-tfstate` (`dev/`, `uat/` y `prod/`). Si algo se rompe en `dev`, no toca `prod`.
* **Recursos por ambiente**:
  * `dev`: 256 CPU / 512 MB RAM, logs 3 días, backups 1 día (`http://localhost:8082`)
  * `uat`: 512 CPU / 1024 MB RAM, logs 7 días, backups 3 días (`http://localhost:8083`)
  * `prod`: 1024 CPU / 2048 MB RAM, logs 30 días, backups 7 días (`http://localhost:8084`)
* **CI/CD (`.github/workflows/`)**:
  * `ci.yml`: corre `terraform fmt -check` y `terraform validate` en matriz para los 3 ambientes, arma la imagen con `HEALTHCHECK` y la sube a GHCR etiquetada con el SHA del commit.
  * `cd.yml`: promueve ese mismo tag inmutable de `dev -> uat -> prod`, frenando antes de producción con aprobación manual en el environment `prod`.

> **Nota sobre `cd.yml` en local:** como Floci corre dentro de mi máquina y los runners en la nube de GitHub no pueden llegar a `localhost:4566`, los pasos de despliegue en `cd.yml` muestran el comando exacto de promoción y verificación. En AWS real solo se conecta el runner por OIDC (o un self-hosted runner dentro de la VPC) y se ejecuta el `terraform apply` directamente.

## Cómo levantarlo en local

**1. Iniciar Floci y crear el bucket de estado remoto**

    docker compose up -d
    ./scripts/bootstrap-state.sh

**2. Desplegar un ambiente (ejemplo `dev`)**

    cd infra/envs/dev
    export TF_VAR_db_password="XXXXXXXXXXX"
    terraform init
    terraform apply -auto-approve

*(Para `uat` y `prod` es exactamente lo mismo desde `infra/envs/uat` y `infra/envs/prod`.)*

**3. Exponer los tres ambientes en `localhost`**

Floci levanta los contenedores ECS en la red `bridge` sin publicar los puertos al host. Este script busca las IPs activas y monta un Nginx liviano frente a los tres:

    cd ~/avl-traccar-devops
    ./scripts/expose-envs.sh

**4. Verificar que los tres respondan**

    for port in 8082 8083 8084; do
      echo -n "Puerto $port -> "
      curl -s "http://localhost:${port}/api/server" | jq -r '.version'
    done

## Qué cambiaría al pasarlo a AWS real

Para no dejar puntos ciegos, estas son las diferencias entre el laboratorio con Floci y un despliegue productivo en AWS:

| Punto | En este lab (Floci local) | En AWS real |
| :--- | :--- | :--- |
| Red y exposición | Red `bridge` de Docker, RDS accesible y proxy Nginx local. | VPC con subredes públicas (ALB + HTTPS/ACM) y privadas (ECS + RDS sin IP pública) controladas por Security Groups. |
| Conexión ECS -> RDS | `data "external"` con `docker inspect` para sacar la IP interna de Postgres. | Endpoint DNS nativo de `aws_db_instance.postgres.address` dentro de la VPC. |
| Bloqueo de estado | S3 sin lock distribuido. | Locking nativo de S3 (`use_lockfile = true`) o tabla DynamoDB para evitar despliegues simultáneos. |
| Secretos y hardening | Credenciales por variables de entorno e imagen base estándar. | Bloque `secrets` en ECS leyendo directo desde Secrets Manager, usuario non-root y escaneo de imagen (Trivy) en CI. |
| Versionado de providers | `.terraform.lock.hcl` ignorado en Git. | Versionado en el repo para asegurar hashes idénticos en cualquier runner. |
| Logs y respaldos | Recursos creados en el módulo sin envío real desde el contenedor. | Driver `awslogs` a CloudWatch con alarmas + RDS Multi-AZ y pruebas periódicas de restauración. |

## Incidentes resueltos en el camino

El detalle de los fallos que salieron con Floci, Docker y Terraform está documentado en [docs/troubleshooting.md](docs/troubleshooting.md).
