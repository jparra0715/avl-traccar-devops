module "traccar" {
  source = "../../modules/traccar"

  env                     = "dev"
  traccar_image           = var.traccar_image
  http_port               = 8082
  osmand_port             = 5055
  db_password             = var.db_password
  cpu                     = 256
  memory                  = 512
  log_retention_days      = 3
  backup_retention_period = 1
}

output "traccar_url" {
  value = module.traccar.traccar_url
}

output "rds_endpoint" {
  value = module.traccar.rds_endpoint
}
