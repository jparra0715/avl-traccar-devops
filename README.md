# AVL Traccar DevOps — Prueba Técnica Finanzauto

Despliegue de **Traccar 6.5** con **PostgreSQL 16** en tres ambientes aislados (`dev`, `uat` y `prod`), usando **Terraform** contra **Floci** (emulador local de AWS), imagen Docker propia en **GHCR** y flujos de **GitHub Actions**.

El reto se abordó como un montaje real de infraestructura: aprovisionamiento reproducible, separación estricta de estados por ambiente, red entre contenedores, manejo de credenciales fuera del repositorio, proxy inverso para exposición y depuración directa desde consola.

## Dónde se montó el laboratorio

Todo el aprovisionamiento y las pruebas se ejecutaron sobre una **máquina virtual dedicada con Ubuntu 22.04 LTS**, usando únicamente herramientas de línea de comandos:

* **Docker Engine + Docker Compose**: motor donde corre Floci y los contenedores que el emulador levanta por debajo para RDS (PostgreSQL 16) y ECS (Traccar 6.5), además del proxy inverso Nginx.
* **Terraform (`1.9.x`)**: definición modular de recursos y gestión de estado remoto.
* **AWS CLI v2**: interacción directa contra el endpoint local de Floci (`http://localhost:4566`) para inicializar el bucket de estado, validar archivos `.tfstate` y administrar tareas ECS.
* **jq + curl**: validación automatizada de las respuestas JSON de cada ambiente (`/api/server`).

## Arquitectura del montaje

* **Módulo único (`infra/modules/traccar`)**: los tres ambientes consumen el mismo módulo cambiando únicamente capacidad y retención. Cada ambiente aprovisiona su instancia RDS PostgreSQL 16, clúster y servicio ECS, secreto en Secrets Manager, Log Group en CloudWatch y bucket S3 de backups.
* **Estados remotos aislados**: cada ambiente guarda su propio `terraform.tfstate` dentro del bucket S3 `avl-traccar-tfstate` (`dev/`, `uat/` y `prod/`). Un cambio o fallo en `dev` no afecta a `prod`.
* **Dimensionamiento por ambiente**:
  * `dev`: 256 CPU / 512 MB RAM, logs 3 días, backups 1 día (`http://localhost:8082`)
  * `uat`: 512 CPU / 1024 MB RAM, logs 7 días, backups 3 días (`http://localhost:8083`)
  * `prod`: 1024 CPU / 2048 MB RAM, logs 30 días, backups 7 días (`http://localhost:8084`)
* **CI/CD (`.github/workflows/`)**:
  * `ci.yml`: corre `terraform fmt -check` y `terraform validate` en matriz para los 3 ambientes, construye la imagen con `HEALTHCHECK` y la publica en GHCR etiquetada con el SHA del commit.
  * `cd.yml`: promueve ese mismo artefacto inmutable de `dev -> uat -> prod`, exigiendo aprobación manual antes de entrar a `prod`.

> **Nota sobre `cd.yml` con emulador local:** como Floci corre dentro de la VM en Ubuntu y los runners públicos de GitHub no tienen acceso a `localhost:4566`, `cd.yml` registra y valida el flujo de promoción con el SHA real y la puerta manual de aprobación. En AWS real ese paso se conecta por OIDC (o mediante un self-hosted runner en la VPC) para ejecutar `terraform apply` directamente.

## Montaje paso a paso (comandos ejecutados)

### 1. Levantar Floci y preparar el backend remoto de Terraform

Primero se inicia el emulador AWS en Docker (con acceso al socket para que pueda crear los contenedores de RDS y ECS) y se crea el bucket S3 donde Terraform guarda los estados remotos:

    docker compose up -d
    ./scripts/bootstrap-state.sh

### 2. Aprovisionar los tres ambientes (`dev`, `uat` y `prod`)

La contraseña de base de datos nunca se guarda en archivos del repositorio; se inyecta por variable de entorno (`TF_VAR_db_password`) en tiempo de ejecución. El despliegue se realiza de forma independiente por carpeta:

    export TF_VAR_db_password="XXXXXXXXXXXX"

    # Ambiente DEV
    cd ~/avl-traccar-devops/infra/envs/dev
    terraform init
    terraform apply -auto-approve

    # Ambiente UAT
    cd ~/avl-traccar-devops/infra/envs/uat
    terraform init
    terraform apply -auto-approve

    # Ambiente PROD
    cd ~/avl-traccar-devops/infra/envs/prod
    terraform init
    terraform apply -auto-approve

### 3. Verificar contenedores activos y estados separados en S3

Desde la consola del servidor se valida que existan los 3 servicios de Traccar, las 3 instancias de PostgreSQL 16 y los 3 archivos `terraform.tfstate` independientes:

    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
      aws --endpoint-url=http://localhost:4566 s3 ls s3://avl-traccar-tfstate --recursive

### 4. Exponer los tres ambientes con Nginx y probar la API

Como Floci levanta los contenedores ECS en la red interna `bridge` sin publicar puertos hacia el host, el script `expose-envs.sh` descubre automáticamente las IPs internas de `dev`, `uat` y `prod` y levanta un proxy inverso ligero con `nginx:alpine` mapeando los puertos `8082`, `8083` y `8084`:

    cd ~/avl-traccar-devops
    ./scripts/expose-envs.sh

    for port in 8082 8083 8084; do
      echo -n "Puerto $port -> "
      curl -s "http://localhost:${port}/api/server" | jq -r '.version'
    done

Los tres puertos deben devolver `6.5`, confirmando que tanto el proxy como cada instancia de Traccar conectada a su propio PostgreSQL están operativos.

## Qué cambiaría al pasarlo a AWS real

| Punto | En este lab (Floci en Ubuntu) | En AWS real |
| :--- | :--- | :--- |
| Red y exposición | Red `bridge` de Docker, RDS accesible y proxy Nginx local. | VPC con subredes públicas (ALB + HTTPS/ACM) y privadas (ECS + RDS sin IP pública) controladas por Security Groups. |
| Conexión ECS -> RDS | `data "external"` con `docker inspect` para sacar la IP interna de Postgres. | Endpoint DNS nativo de `aws_db_instance.postgres.address` dentro de la VPC. |
| Bloqueo de estado | S3 sin lock distribuido. | Locking nativo de S3 (`use_lockfile = true`) o tabla DynamoDB para evitar despliegues simultáneos. |
| Secretos y hardening | Credenciales por variables de entorno e imagen base estándar. | Bloque `secrets` en ECS leyendo directo desde Secrets Manager, usuario non-root y escaneo de imagen (Trivy) en CI. |
| Versionado de providers | `.terraform.lock.hcl` ignorado en Git. | Versionado en el repo para asegurar hashes idénticos en cualquier runner. |
| Logs y respaldos | Recursos creados en el módulo sin envío real desde el contenedor. | Driver `awslogs` a CloudWatch con alarmas + RDS Multi-AZ y pruebas periódicas de restauración. |

## Incidentes resueltos en el camino

El detalle de los errores reales que salieron con Floci, Docker y Terraform (permisos del socket, conectividad `bridge`, *drift* en RDS y tareas huérfanas en ECS) está documentado en [docs/troubleshooting.md](docs/troubleshooting.md).
