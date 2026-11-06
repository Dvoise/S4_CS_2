variable "alert_email" {
  type = string
}
variable "private_subnet_ids" { 
  type = list(string) 
}
variable "lambda_sg_id" { 
  type = string 
}
variable "db_host" { 
  type = string 
}
variable "db_name" {
  type    = string
  default = "soar"
}
variable "db_user" {
  type    = string
  default = "soar"
}
variable "db_password" {
  type      = string
  sensitive = true
}

variable "nacl_id" { type = string }
variable "isolation_sg_id" { type = string }
variable "allowlist_ips" {
  type    = list(string)
  default = []
}