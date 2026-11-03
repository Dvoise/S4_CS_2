variable "vpc_id" { 
    type = string 
}

variable "onprem_public_ip" { 
    type = string 
}

variable "onprem_cidr" {
    type = string
}

variable "route_table_ids" {
    type = list(string) 
}

variable "vpn_psk" {
  type      = string
  sensitive = true
}