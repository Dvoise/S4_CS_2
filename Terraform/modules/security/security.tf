resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Security group for web instances"
  vpc_id      =  var.vpc_id

}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

}

resource "aws_vpc_security_group_egress_rule" "web_all_outbound" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

}

resource "aws_security_group" "db_sg" {
  name        = "db_sg"
  description = "Security group for DB instances"
  vpc_id      = var.vpc_id

}

resource "aws_vpc_security_group_ingress_rule" "db_mysql" {
  security_group_id = aws_security_group.db_sg.id
  referenced_security_group_id = aws_security_group.web_sg.id
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306

}

resource "aws_vpc_security_group_egress_rule" "db_all_outbound" {
  security_group_id = aws_security_group.db_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol = "-1"

}

resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring_sg"
  description = "Security group for monitoring instances"
  vpc_id      = var.vpc_id

}

resource "aws_vpc_security_group_ingress_rule" "grafana_from_me" {
  security_group_id = aws_security_group.monitoring_sg.id
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 3000
  ip_protocol       = "tcp"
  to_port           = 3000

}

resource "aws_vpc_security_group_ingress_rule" "prometheus_from_me" {
  security_group_id = aws_security_group.monitoring_sg.id
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 9090
  ip_protocol       = "tcp"
  to_port           = 9090

}

resource "aws_vpc_security_group_egress_rule" "monitoring_all_out" {
  security_group_id = aws_security_group.monitoring_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

}

resource "aws_vpc_security_group_ingress_rule" "web_node_exporter" {
  security_group_id = aws_security_group.web_sg.id
  referenced_security_group_id = aws_security_group.monitoring_sg.id
  from_port         = 9100
  ip_protocol       = "tcp"
  to_port           = 9100
}

resource "aws_vpc_security_group_ingress_rule" "web_icmp_onprem" {
  security_group_id = aws_security_group.web_sg.id
  cidr_ipv4         = var.onprem_cidr
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_security_group" "lambda_sg" {
  name        = "lambda_sg"
  description = "SOAR Lambda functions"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "lambda_all_out" {
  security_group_id = aws_security_group.lambda_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_lambda" {
  security_group_id            = aws_security_group.db_sg.id
  referenced_security_group_id = aws_security_group.lambda_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "collector_sg" {
  name        = "collector_sg"
  description = "On-prem syslog collector"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "collector_syslog" {
  security_group_id = aws_security_group.collector_sg.id
  cidr_ipv4         = var.onprem_cidr
  from_port         = 514
  to_port           = 514
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "collector_all_out" {
  security_group_id = aws_security_group.collector_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "isolation_sg" {
  name        = "isolation_sg"
  description = "Quarantine: no inbound, no outbound"
  vpc_id      = var.vpc_id
}