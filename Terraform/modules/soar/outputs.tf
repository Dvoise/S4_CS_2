output "table_name" {
  value = aws_dynamodb_table.events.name
}
output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}