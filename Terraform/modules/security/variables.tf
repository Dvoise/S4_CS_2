variable "vpc_id" {
    description = "The ID of the VPC where the security groups will be created"
    type        = string
}

variable "my_ip_cidr" {
    description = "The CIDR block of the user's IP address for SSH access"
    type        = string
}

variable "onprem_cidr" {
  description = "CIDR of the on-prem LAN allowed to reach the web tier"
  type    = string
  default = "192.168.121.0/24"
}
