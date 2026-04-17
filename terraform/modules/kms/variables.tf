variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "deletion_window_days" {
  description = "Days before KMS key is permanently deleted after scheduling deletion. Min 7, max 30. Higher = more recovery time if deleted accidentally."
  type        = number
  default     = 30
}

variable "app_role_arn" {
  description = "IAM role ARN for the application (IRSA). Granted encrypt/decrypt. Empty string = allow root account only."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags for cost tracking and compliance"
  type        = map(string)
  default     = {}
}
