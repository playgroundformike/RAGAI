# ============================================================
# KMS Module — Customer-Managed Encryption Keys
# ============================================================
#
# Creates a KMS CMK (Customer Master Key) for encrypting documents
# in S3 and any other data-at-rest encryption needs.
#
# Why customer-managed (CMK) instead of AWS-managed (aws/s3)?
#   - Key rotation control (we decide the schedule)
#   - CloudTrail logging of every Encrypt/Decrypt call
#   - Ability to revoke access by disabling the key
#   - Cross-account access control via key policy
#   - Required for IL4/IL5 — AWS-managed keys don't give enough control
#
# NIST 800-53 Controls:
#   SC-12 (Cryptographic Key Management)
#   SC-28 (Protection of Information at Rest)
# ============================================================

# ── Data Sources ─────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── KMS Key ──────────────────────────────────────────────────
resource "aws_kms_key" "document_encryption" {
  description             = "${var.project_name} document encryption key"
  deletion_window_in_days = var.deletion_window_days

  # SC-12: Enable automatic annual key rotation.
  # AWS rotates the backing key material every year while keeping
  # the same key ID. Old data can still be decrypted with the
  # previous key material — rotation is transparent to the app.
  enable_key_rotation = true

  # Key policy — defines WHO can use this key.
  # This is separate from IAM policies and takes precedence.
  # Without a key policy, even account root can't use the key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow the account root full key management.
        # This is the "break glass" policy — without it, if you
        # lose access to the key admin role, the key is orphaned.
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Allow the EKS pod role to encrypt/decrypt only.
        # Least privilege: the app can USE the key but can't
        # manage it (no kms:Create*, kms:Delete*, kms:Disable*).
        Sid    = "AllowAppEncryptDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = var.app_role_arn != "" ? var.app_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = var.tags
}

# ── KMS Alias ────────────────────────────────────────────────
# Aliases provide a human-readable name for the key.
# The app config references "alias/securegenai-document-key"
# instead of a raw key ID — the alias stays stable even if
# we need to create a new key and point the alias at it.
resource "aws_kms_alias" "document_encryption" {
  name          = "alias/${var.project_name}-document-key"
  target_key_id = aws_kms_key.document_encryption.key_id
}
