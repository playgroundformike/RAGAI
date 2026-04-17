# ============================================================
# Prod Environment — Terragrunt Configuration
# ============================================================
#
# Production differences from dev:
#   - Larger EKS nodes, more replicas
#   - Private-only EKS endpoint (no public API access)
#   - S3 force_destroy disabled (protect production data)
#   - DynamoDB deletion protection enabled
#   - Longer log retention
# ============================================================

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_parent_terragrunt_dir()}/environments/prod"
}

inputs = {
  project_name = "securegenai"
  environment  = "prod"
  aws_region   = "us-east-1"

  vpc_cidr = "10.1.0.0/16"  # Different CIDR from dev — no overlap
  az_count = 2

  cluster_name           = "securegenai-prod"
  kubernetes_version     = "1.29"
  node_instance_types    = ["t3.large"]
  node_desired_count     = 3
  node_min_count         = 2
  node_max_count         = 6
  enable_public_endpoint = false  # Production: private only

  s3_bucket_name = "securegenai-documents-prod"
  force_destroy  = false  # NEVER allow destruction of prod data

  ecr_repository_name = "securegenai-app"

  dynamodb_table_name = "securegenai-document-registry-prod"
  deletion_protection = true

  bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"

  tags = {
    Environment = "prod"
    CostCenter  = "operations"
    Compliance  = "IL4"
  }
}
