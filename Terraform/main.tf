terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

module "my_deployment" {
  source              = "./modules/deployment"
  asg_name             = module.my_compute.asg_name
  target_group_name    = module.my_compute.target_group_name
}

module "my_network" {
  source = "./modules/network"
}

module "my_security"{
    source = "./modules/security"
    vpc_id = module.my_network.vpc_id
    my_ip_cidr = "${chomp(data.http.my_ip.response_body)}/32"
    onprem_cidr = var.onprem_cidr
}

module "my_compute" {
  source = "./modules/compute"
  vpc_id = module.my_network.vpc_id
  web_sg_id = module.my_security.web_sg_id
  private_subnet_blue_id = module.my_network.private_subnet_blue_id
  private_subnet_green_id = module.my_network.private_subnet_green_id
  public_subnet_blue_id = module.my_network.public_subnet_blue_id
  public_subnet_green_id = module.my_network.public_subnet_green_id
  depends_on = [module.my_network]
}

module "my_database" {
  source = "./modules/database"

  private_subnet_blue_id  = module.my_network.private_subnet_blue_id
  db_sg_id                 = module.my_security.db_sg_id
  db_password              = var.db_password
  depends_on = [module.my_network]
}

module "my_monitoring" {
  source = "./modules/monitoring"
  public_subnet_id = module.my_network.public_subnet_blue_id
  monitoring_sg_id = module.my_security.monitoring_sg_id
}

module "my_vpn" {
  source           = "./modules/vpn"
  vpc_id           = module.my_network.vpc_id
  onprem_public_ip = var.onprem_public_ip
  onprem_cidr      = var.onprem_cidr
  vpn_psk          = var.vpn_psk
  route_table_ids  = concat([module.my_network.public_route_table_id], module.my_network.private_route_table_ids)
}

module "my_soar" {
  source      = "./modules/soar"
  alert_email = var.alert_email
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "tonkata-tf-bucket-123-test"
}