# Bitácora Técnica y Resolución de Incidentes

Durante el montaje en Ubuntu 22.04 con Floci salieron varios fallos propios del emulador y de red entre contenedores. Dejo el registro de cómo se diagnosticó y resolvió cada uno.

## 1. RDS colgado más de 17 minutos (`BindException: Permission denied`)
* **Qué pasó:** al correr `terraform apply` en `dev`, la creación de `aws_db_instance.postgres` nunca terminaba.
* **Cómo se encontró:** mirando `docker logs floci` salió `java.net.BindException: Permission denied` contra `/var/run/docker.sock`.
* **Cómo se arregló:** se agregó `user: "0:0"` y el volumen persistente `floci_data:/app/data` en `docker-compose.yml`. Al recrear Floci, PostgreSQL levantó en menos de dos minutos.

## 2. Traccar moría al arrancar sin mostrar logs (`Connection refused`)
* **Qué pasó:** el contenedor ECS de Traccar arrancaba y salía con `ExitCode=1`, pero `docker logs` salía vacío.
* **Cómo se encontró:** se copió `/opt/traccar/logs/tracker-server.log` desde el contenedor detenido con `docker cp`. Ahí apareció `ConnectException: Connection refused`: Floci reportaba el endpoint de RDS como `localhost:7001`, pero desde otro contenedor `localhost` apunta al propio Traccar, no al host ni a Postgres.
* **Cómo se arregló:** se metió un `data "external"` en `infra/modules/traccar/main.tf` para consultar la IP real del contenedor `floci-rds-traccar-db-<env>` en la red `bridge` (puerto `5432`) y se activó `LOGGER_CONSOLE=true` para no volver a quedar ciegos en `docker logs`.

## 3. Respuestas vacías de RDS, drift y tareas huérfanas en Floci
* **Qué pasó:** al desplegar `uat` y `prod`, Floci respondió vacío un par de veces al `DescribeDBInstances` (`empty result`), dejando la base de datos marcada como `tainted` en Terraform. Además, al intentar modificar atributos que Floci no guarda o reemplazar un servicio ECS por ARN (`404 ServiceNotFoundException`), Terraform se quedaba pegado.
* **Cómo se arregló:**
  * Se verificó primero con `docker ps` y logs que PostgreSQL estaba arriba y aceptando conexiones, y se recuperó con `terraform untaint` en lugar de destruir la instancia.
  * Se agregó `lifecycle { ignore_changes }` en el módulo sobre `auto_minor_version_upgrade`, `backup_retention_period` y `publicly_accessible` para frenar el falso drift del emulador.
  * Cuando un contenedor viejo se borró a mano y Floci seguía viendo la tarea activa, se limpió la tarea zombi con `aws ecs stop-task` contra `http://localhost:4566` para que el servicio levantara la revisión nueva.

## 4. Puertos no publicados hacia `localhost`
* **Qué pasó:** los contenedores ECS levantaban en `bridge` con `8082/tcp` interno pero sin mapear puerto al host.
* **Cómo se arregló:** se armó `scripts/expose-envs.sh`, que detecta la IP de cada contenedor activo (`dev`, `uat`, `prod`) y levanta un contenedor `nginx:alpine` publicando `:8082`, `:8083` y `:8084` en local.
