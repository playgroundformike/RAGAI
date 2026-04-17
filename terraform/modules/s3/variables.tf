variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for default bucket encryption"
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to destroy bucket with objects. False in prod."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
