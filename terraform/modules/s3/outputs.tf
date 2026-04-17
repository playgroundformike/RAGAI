output "bucket_arn" {
  description = "S3 bucket ARN — used in IAM policies"
  value       = aws_s3_bucket.documents.arn
}

output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.documents.id
}

output "bucket_regional_domain" {
  description = "Regional domain for S3 access"
  value       = aws_s3_bucket.documents.bucket_regional_domain_name
}
