variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA trust relationship"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (without https://)"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace where the app runs"
  type        = string
  default     = "securegenai"
}

variable "k8s_service_account_name" {
  description = "Kubernetes service account name annotated with this role"
  type        = string
  default     = "securegenai-app"
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for document storage access"
  type        = string
}

variable "s3_prefix" {
  description = "S3 key prefix the app is allowed to access"
  type        = string
  default     = "uploads/"
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypt/decrypt permissions"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID (e.g., anthropic.claude-3-sonnet-20240229-v1:0)"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN for document registry access"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
