# ============================================================
# Root Terragrunt Configuration
# ============================================================
#
# Terragrunt is a thin wrapper around Terraform that solves
# two problems Terraform alone doesn't handle well:
#
# 1. DRY (Don't Repeat Yourself) configuration:
#    Without Terragrunt, you'd copy-paste the same provider
#    config, backend config, and variable values across
#    dev/staging/prod. With Terragrunt, shared config lives
#    HERE and environments only specify what's different.
#
# 2. Remote state management:
#    Terraform state files track what infrastructure exists.
#    They MUST be stored remotely (S3) with locking (DynamoDB)
#    so two people don't modify infrastructure simultaneously.
#    Terragrunt auto-creates and configures this.
#
# How it works:
#    environments/dev/terragrunt.hcl  ──includes──▶  this file
#    environments/prod/terragrunt.hcl ──includes──▶  this file
#    Both inherit the provider config and backend config below.
# ============================================================

# ── Remote State Configuration ───────────────────────────────
# Terraform state is stored in S3 with DynamoDB locking.
# This prevents two engineers (or two CI runs) from modifying
# the same infrastructure at the same time.
remote_state {
  backend = "s3"
  config = {
    bucket         = "securegenai-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "securegenai-terraform-locks"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ── Provider Configuration ───────────────────────────────────
# Shared AWS provider config. The region and default tags
# are inherited by every environment.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<EOF
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SecureGenAI"
      ManagedBy   = "Terraform"
      Repository  = "playgroundformike/secure-genai-doc-assistant"
    }
  }
}
EOF
}
