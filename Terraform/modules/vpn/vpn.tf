resource "aws_vpn_gateway" "main" {
  vpc_id = var.vpc_id
  tags   = { Name = "main-vgw" }
}

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = 65000
  ip_address = var.onprem_public_ip
  type       = "ipsec.1"
  tags       = { Name = "onprem-pfsense" }
}

resource "aws_vpn_connection" "onprem" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = true

  tunnel1_preshared_key = var.vpn_psk
  tunnel2_preshared_key = var.vpn_psk

  tags = { Name = "onprem-vpn" }
}

resource "aws_vpn_connection_route" "onprem" {
  vpn_connection_id      = aws_vpn_connection.onprem.id
  destination_cidr_block = var.onprem_cidr
}

resource "aws_vpn_gateway_route_propagation" "this" {
  count          = length(var.route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = var.route_table_ids[count.index]
}