variable "db_password" {
    type      = string
    sensitive = true
}

variable "onprem_public_ip" { 
    type = string 
}

variable "onprem_cidr" {
  type    = string
  default = "192.168.121.0/24"
}

variable "vpn_psk" {
  type      = string
  sensitive = true
}