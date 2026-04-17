# ============================================================
# Dev Environment — Terragrunt Configuration
# ============================================================
#
# This file:
#   1. Includes the root terragrunt.hcl (inherits provider + backend)
#   2. Points to the main.tf that wires all modules together
#   3. Sets dev-specific variable values
#
# Dev environment differences from prod:
#   - Smaller/fewer EKS nodes (cost savings)
#   - Public EKS endpoint enabled (easier kubectl access)
#   - S3 force_destroy enabled (easy cleanup)
#   - DynamoDB deletion protection disabled
# ============================================================

# Include root config (provider, backend, shared settings)
include "root" {
  path = find_in_parent_folders()
}

# Point to the Terraform code that wires modules together
terraform {
  source = "${get_parent_terragrunt_dir()}/environments/dev"
}

# Dev-specific input variables
inputs = {
  # ── General ────────────────────────────────────────────────
  project_name = "securegenai"
  environment  = "dev"
  aws_region   = "us-east-1"

  # ── VPC ────────────────────────────────────────────────────
  vpc_cidr = "10.0.0.0/16"
  az_count = 2

  # ── EKS ────────────────────────────────────────────────────
  cluster_name           = "securegenai-dev"
  kubernetes_version     = "1.29"
  node_instance_types    = ["t3.medium"]
  node_desired_count     = 2
  node_min_count         = 1
  node_max_count         = 3
  # Public endpoint ON in dev for easier kubectl access
  enable_public_endpoint = true

  # ── S3 ─────────────────────────────────────────────────────
  s3_bucket_name = "securegenai-documents-dev"
  # Allow Terraform to destroy bucket in dev (easy cleanup)
  force_destroy  = true

  # ── ECR ────────────────────────────────────────────────────
  ecr_repository_name = "securegenai-app"

  # ── DynamoDB ───────────────────────────────────────────────
  dynamodb_table_name     = "securegenai-document-registry-dev"
  deletion_protection     = false

  # ── Bedrock ────────────────────────────────────────────────
  bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"

  # ── Tags ───────────────────────────────────────────────────
  tags = {
    Environment = "dev"
    CostCenter  = "engineering"
  }
}
