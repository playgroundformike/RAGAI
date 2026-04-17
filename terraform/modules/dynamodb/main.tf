# ============================================================
# DynamoDB Module — Document Metadata Registry
# ============================================================
#
# Stores metadata about uploaded documents:
#   - document_id (partition key)
#   - filename, upload timestamp, user, file hash, status
#
# Why DynamoDB instead of RDS?
#   - Serverless (no instances to manage/STIG)
#   - Single-digit ms latency for key-value lookups
#   - Scales to zero when not in use (pay-per-request)
#   - Built-in encryption and backup
#
# NIST 800-53 Controls:
#   AU-3  (Audit Records) — tracks document lifecycle
#   SC-28 (Protection at Rest) — KMS encryption
#   CP-9  (System Backup) — point-in-time recovery
# ============================================================

resource "aws_dynamodb_table" "document_registry" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  # Partition key — document_id (UUID string)
  # Each document gets exactly one record.
  hash_key = "document_id"

  attribute {
    name = "document_id"
    type = "S" # String
  }

  # SC-28: Encrypt table data with our KMS key
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  # CP-9: Point-in-time recovery allows restoring the table
  # to any second within the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  # Prevent accidental table deletion via Terraform
  deletion_protection_enabled = var.deletion_protection

  tags = var.tags
}
