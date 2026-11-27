module "traccar" {
  source = "../../modules/traccar"

  env                     = "prod"
  traccar_image           = var.traccar_image
  http_port               = 8084
  osmand_port             = 5057
  db_password             = var.db_password
  cpu                     = 1024
  memory                  = 2048
  log_retention_days      = 30
  backup_retention_period = 7
}

output "traccar_url" {
  value = module.traccar.traccar_url
}

output "rds_endpoint" {
  value = module.traccar.rds_endpoint
}
