output "app_role_arn" {
  description = "IAM role ARN for the application — annotate K8s service account with this"
  value       = aws_iam_role.app.arn
}

output "app_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.app.name
}
