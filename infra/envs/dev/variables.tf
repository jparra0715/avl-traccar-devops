variable "db_password" {
  type      = string
  sensitive = true
}

variable "traccar_image" {
  type    = string
  default = "traccar/traccar:6.5-alpine"
}
