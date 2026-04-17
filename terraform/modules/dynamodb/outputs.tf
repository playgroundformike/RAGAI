output "table_arn" {
  description = "DynamoDB table ARN — used in IAM policies"
  value       = aws_dynamodb_table.document_registry.arn
}

output "table_name" {
  description = "DynamoDB table name — passed to app config"
  value       = aws_dynamodb_table.document_registry.name
}
