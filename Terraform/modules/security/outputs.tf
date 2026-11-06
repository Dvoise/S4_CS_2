output "web_sg_id" {
  description = "The ID of the web security group"
  value = aws_security_group.web_sg.id

}

output "db_sg_id" {
  description = "The ID of the database security group"
  value = aws_security_group.db_sg.id

}

output "monitoring_sg_id" {
  description = "The ID of the monitoring security group"
  value = aws_security_group.monitoring_sg.id

}

output "lambda_sg_id" {
  value = aws_security_group.lambda_sg.id
  
}

output "collector_sg_id" {
  value = aws_security_group.collector_sg.id

}

output "isolation_sg_id" {
  value = aws_security_group.isolation_sg.id
  
}