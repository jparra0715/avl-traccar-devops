module "traccar" {
  source = "../../modules/traccar"

  env                     = "uat"
  traccar_image           = var.traccar_image
  http_port               = 8083
  osmand_port             = 5056
  db_password             = var.db_password
  cpu                     = 512
  memory                  = 1024
  log_retention_days      = 7
  backup_retention_period = 3
}

output "traccar_url" {
  value = module.traccar.traccar_url
}

output "rds_endpoint" {
  value = module.traccar.rds_endpoint
}
