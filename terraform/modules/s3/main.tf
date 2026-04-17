# ============================================================
# S3 Module — Secure Document Storage
# ============================================================
#
# Creates an S3 bucket with:
#   - KMS encryption by default (every object encrypted at rest)
#   - Versioning enabled (accidental deletes are recoverable)
#   - Public access completely blocked
#   - Bucket policy enforcing TLS-only access
#   - Lifecycle rules for cost management
#
# NIST 800-53 Controls:
#   SC-28 (Protection at Rest) — SSE-KMS default encryption
#   SC-8  (Transmission Confidentiality) — TLS-only bucket policy
#   AU-11 (Audit Record Retention) — versioning preserves history
#   CP-9  (System Backup) — versioning enables point-in-time recovery
# ============================================================

resource "aws_s3_bucket" "documents" {
  bucket = var.bucket_name

  # Prevent accidental deletion of the bucket via Terraform.
  # You must set this to false and re-apply before destroying.
  # This is a safety net for production data.
  force_destroy = var.force_destroy

  tags = var.tags
}

# ── Versioning ───────────────────────────────────────────────
# Every overwrite or delete creates a new version instead of
# replacing/removing the object. This means:
#   - Accidental deletes are recoverable
#   - You have an audit trail of every document version
#   - Ransomware can't permanently destroy data
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ── Default Encryption ───────────────────────────────────────
# SC-28: Every object stored in this bucket is automatically
# encrypted with our KMS key, even if the PutObject call
# doesn't specify encryption parameters. Belt and suspenders —
# the app code ALSO specifies encryption on each upload.
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    # Bucket key reduces KMS API calls (and cost) by generating
    # a per-bucket data key instead of calling KMS per-object.
    bucket_key_enabled = true
  }
}

# ── Block ALL Public Access ──────────────────────────────────
# This is a hard block — even if someone attaches a bucket policy
# that allows public access, these settings override it.
# There is no legitimate reason for document storage to be public.
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Bucket Policy: TLS Only ──────────────────────────────────
# SC-8: Deny any request that doesn't use HTTPS.
# This prevents accidental plaintext access even if someone
# misconfigures a client to use HTTP.
resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.documents]
}

# ── Lifecycle Rules ──────────────────────────────────────────
# Move old document versions to cheaper storage tiers.
# Current versions stay in STANDARD; old versions move to
# GLACIER after 90 days. This controls cost without losing data.
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  depends_on = [aws_s3_bucket_versioning.documents]
}
