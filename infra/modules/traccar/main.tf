# 1. Bucket S3 para respaldos de base de datos
resource "aws_s3_bucket" "backups" {
  bucket        = "avl-traccar-backups-${var.env}"
  force_destroy = true
}

# 2. Grupo de logs centralizado
resource "aws_cloudwatch_log_group" "traccar" {
  name              = "/ecs/traccar-${var.env}"
  retention_in_days = var.log_retention_days
}

# 3. Secreto en Secrets Manager (sin quemar credenciales en el código)
resource "aws_secretsmanager_secret" "db_creds" {
  name                    = "traccar/${var.env}/db-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    dbname   = "traccar_${var.env}"
  })
}

# 4. Base de datos PostgreSQL (RDS emulado en Floci)
resource "aws_db_instance" "postgres" {
  identifier              = "traccar-db-${var.env}"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "traccar_${var.env}"
  username                = var.db_username
  password                = var.db_password
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true
  publicly_accessible     = true
  lifecycle {
    ignore_changes = [auto_minor_version_upgrade, backup_retention_period, publicly_accessible]
  }
}

# Workaround para Floci: obtener IP interna real del contenedor RDS en la red bridge
data "external" "rds_ip" {
  program = [
    "bash", "-c",
    "IP=$(docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' floci-rds-${aws_db_instance.postgres.identifier}); echo \"{\\\"ip\\\": \\\"$IP\\\"}\""
  ]
}

# 5. Clúster ECS
resource "aws_ecs_cluster" "this" {
  name = "traccar-cluster-${var.env}"
}

# 6. Definición de tarea ECS para Traccar conectado a PostgreSQL
resource "aws_ecs_task_definition" "traccar" {
  family                   = "traccar-${var.env}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)

  container_definitions = jsonencode([
    {
      name      = "traccar-${var.env}"
      image     = var.traccar_image
      essential = true
      cpu       = var.cpu
      memory    = var.memory
      portMappings = [
        {
          containerPort = 8082
          hostPort      = var.http_port
          protocol      = "tcp"
        },
        {
          containerPort = 5055
          hostPort      = var.osmand_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "CONFIG_USE_ENVIRONMENT_VARIABLES", value = "true" },
        { name = "LOGGER_CONSOLE", value = "true" },
        { name = "DATABASE_DRIVER", value = "org.postgresql.Driver" },
        { name = "DATABASE_URL", value = "jdbc:postgresql://${data.external.rds_ip.result.ip}:5432/traccar_${var.env}" },
        { name = "DATABASE_USER", value = var.db_username },
        { name = "DATABASE_PASSWORD", value = var.db_password }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.traccar.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "traccar"
        }
      }
    }
  ])
}

# 7. Servicio ECS
resource "aws_ecs_service" "traccar" {
  name            = "traccar-service-${var.env}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.traccar.arn
  desired_count   = 1
}
