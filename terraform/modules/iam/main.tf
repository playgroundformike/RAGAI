# ============================================================
# IAM Module — IRSA (IAM Roles for Service Accounts)
# ============================================================
#
# Creates an IAM role that a specific Kubernetes pod can assume
# via its service account. This is the mechanism that lets our
# FastAPI app call S3, KMS, Bedrock, and DynamoDB without
# having AWS credentials baked into the container.
#
# How IRSA works:
#   1. EKS has an OIDC provider (created in the EKS module)
#   2. We create an IAM role that trusts that OIDC provider
#   3. We annotate a K8s service account with this role's ARN
#   4. When a pod uses that service account, AWS STS issues
#      temporary credentials scoped to exactly this role
#   5. boto3 in the pod picks up the credentials automatically
#
# Why IRSA instead of instance roles or access keys?
#   - Instance roles: every pod on the node gets the same permissions
#   - Access keys: static, long-lived, must be rotated manually
#   - IRSA: per-pod permissions, temporary credentials, auto-rotated
#
# NIST 800-53 Controls:
#   AC-6  (Least Privilege) — scoped to exactly what the app needs
#   AC-2  (Account Management) — tied to K8s service account
#   IA-5  (Authenticator Management) — temporary, auto-rotated creds
# ============================================================

data "aws_caller_identity" "current" {}

# ── IAM Role with OIDC Trust ─────────────────────────────────
resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-role"

  # This trust policy says: "only the specific K8s service account
  # in the specific namespace can assume this role."
  # Not any pod — EXACTLY this service account in this namespace.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
        }
      }
    }]
  })

  tags = var.tags
}

# ── S3 Policy ────────────────────────────────────────────────
# App can read/write documents in the specific bucket and prefix.
# NOT s3:* — only the operations the app actually performs.
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-s3-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DocumentReadWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/${var.s3_prefix}*",
        ]
      },
    ]
  })
}

# ── KMS Policy ───────────────────────────────────────────────
# App can encrypt/decrypt with the document key.
# Cannot manage the key (no kms:Create*, kms:Delete*, kms:Disable*).
resource "aws_iam_role_policy" "kms_access" {
  name = "${var.project_name}-kms-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DocumentEncryptDecrypt"
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      Resource = [var.kms_key_arn]
    }]
  })
}

# ── Bedrock Policy ───────────────────────────────────────────
# App can invoke the specific model — not manage models,
# not invoke other models. Scoped to the exact model ID.
resource "aws_iam_role_policy" "bedrock_access" {
  name = "${var.project_name}-bedrock-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockInvoke"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      # Scoped to the specific model — not bedrock:* on all models
      Resource = [
        "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}",
      ]
    }]
  })
}

# ── DynamoDB Policy ──────────────────────────────────────────
# App can read/write items in the document registry table.
# Cannot delete the table or modify its schema.
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "${var.project_name}-dynamodb-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DocumentRegistry"
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:UpdateItem",
      ]
      Resource = [var.dynamodb_table_arn]
    }]
  })
}
