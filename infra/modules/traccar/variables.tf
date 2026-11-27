variable "env" {
  description = "Nombre del ambiente (dev, uat, prod)"
  type        = string
}

variable "traccar_image" {
  description = "Imagen Docker de Traccar con tag inmutable"
  type        = string
  default     = "traccar/traccar:6.5-alpine"
}

variable "http_port" {
  description = "Puerto HTTP expuesto en el host para la interfaz web y API"
  type        = number
}

variable "osmand_port" {
  description = "Puerto expuesto para protocolo GPS OsmAnd"
  type        = number
}

variable "db_username" {
  description = "Usuario de PostgreSQL"
  type        = string
  default     = "traccar"
}

variable "db_password" {
  description = "Contraseña de PostgreSQL (inyectada por variable de entorno, nunca en código)"
  type        = string
  sensitive   = true
}

variable "cpu" {
  description = "Unidades de CPU para la tarea ECS"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memoria en MB para la tarea ECS"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 7
}

variable "backup_retention_period" {
  description = "Días de retención de backups automáticos en RDS"
  type        = number
  default     = 1
}
