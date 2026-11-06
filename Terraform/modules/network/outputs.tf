output "vpc_id" {
  value = aws_vpc.main.id
  description = "ID of the VPC"
}

output "public_subnet_blue_id" {
  value = aws_subnet.public_blue.id
  description = "ID of the public blue subnet"
}

output "public_subnet_green_id" {
  value = aws_subnet.public_green.id
  description = "ID of the public green subnet"
}

output "private_subnet_blue_id" {
  value = aws_subnet.private_blue.id
  description = "ID of the private blue subnet"
}

output "private_subnet_green_id" {
  value = aws_subnet.private_green.id
  description = "ID of the private green subnet"
}

output "nat_gateway_blue_id" {
  value       = aws_nat_gateway.nat_blue.id
  description = "ID of the blue NAT Gateway"
}

output "nat_gateway_green_id" {
  value       = aws_nat_gateway.nat_green.id
  description = "ID of the green NAT Gateway"
}

output "public_route_table_id" {
  value       = aws_route_table.public_rt.id
  description = "ID of the public route table"
}

output "private_route_table_ids" {
  value       = [aws_route_table.private_blue_rt.id, aws_route_table.private_green_rt.id]
  description = "IDs of the private route tables"
}

output "default_nacl_id" {
  value = aws_vpc.main.default_network_acl_id
}
