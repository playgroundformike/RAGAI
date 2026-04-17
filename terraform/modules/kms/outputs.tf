output "key_arn" {
  description = "KMS key ARN — used in S3 bucket encryption config and IAM policies"
  value       = aws_kms_key.document_encryption.arn
}

output "key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.document_encryption.key_id
}

output "alias_name" {
  description = "KMS alias name — this is what the app config references"
  value       = aws_kms_alias.document_encryption.name
}
