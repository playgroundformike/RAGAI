variable "table_name" {
  description = "DynamoDB table name"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for table encryption"
  type        = string
}

variable "deletion_protection" {
  description = "Prevent accidental table deletion. True in production."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
