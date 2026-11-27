output "traccar_url" {
  value = "http://localhost:${var.http_port}"
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.traccar.name
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}
