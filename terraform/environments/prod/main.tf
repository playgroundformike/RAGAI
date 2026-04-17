# ============================================================
# Dev Environment — Module Composition
# ============================================================
#
# This file wires all infrastructure modules together.
# Think of it as the "main()" function for your infrastructure.
#
# Dependency chain (order matters):
#   KMS → S3 (needs KMS key for encryption)
#   KMS → DynamoDB (needs KMS key for encryption)
#   KMS → ECR (needs KMS key for image encryption)
#   VPC → EKS (needs subnets for worker nodes)
#   EKS → IAM/IRSA (needs OIDC provider for pod roles)
#   S3 + KMS + DynamoDB → IAM (needs ARNs for policy scoping)
#
# Terraform resolves this dependency graph automatically
# based on the variable references between modules.
# ============================================================

# ── Variables (set by Terragrunt inputs) ─────────────────────
variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "vpc_cidr" { type = string }
variable "az_count" { type = number }
variable "cluster_name" { type = string }
variable "kubernetes_version" { type = string }
variable "node_instance_types" { type = list(string) }
variable "node_desired_count" { type = number }
variable "node_min_count" { type = number }
variable "node_max_count" { type = number }
variable "enable_public_endpoint" { type = bool }
variable "s3_bucket_name" { type = string }
variable "force_destroy" { type = bool }
variable "ecr_repository_name" { type = string }
variable "dynamodb_table_name" { type = string }
variable "deletion_protection" { type = bool }
variable "bedrock_model_id" { type = string }
variable "tags" { type = map(string) }

# ── KMS (foundation — other modules depend on this) ──────────
module "kms" {
  source = "../../modules/kms"

  project_name = var.project_name
  tags         = var.tags
}

# ── VPC (network foundation for EKS) ─────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count
  tags         = var.tags
}

# ── S3 (document storage) ────────────────────────────────────
module "s3" {
  source = "../../modules/s3"

  bucket_name   = var.s3_bucket_name
  kms_key_arn   = module.kms.key_arn
  force_destroy = var.force_destroy
  tags          = var.tags
}

# ── ECR (container registry) ─────────────────────────────────
module "ecr" {
  source = "../../modules/ecr"

  repository_name = var.ecr_repository_name
  kms_key_arn     = module.kms.key_arn
  tags            = var.tags
}

# ── DynamoDB (document metadata) ─────────────────────────────
module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name          = var.dynamodb_table_name
  kms_key_arn         = module.kms.key_arn
  deletion_protection = var.deletion_protection
  tags                = var.tags
}

# ── EKS (Kubernetes cluster) ─────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  cluster_name           = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.vpc_cidr_block
  private_subnet_ids     = module.vpc.private_subnet_ids
  kms_key_arn            = module.kms.key_arn
  node_instance_types    = var.node_instance_types
  node_desired_count     = var.node_desired_count
  node_min_count         = var.node_min_count
  node_max_count         = var.node_max_count
  enable_public_endpoint = var.enable_public_endpoint
  environment            = var.environment
  tags                   = var.tags
}

# ── IAM/IRSA (pod-level AWS permissions) ─────────────────────
module "iam" {
  source = "../../modules/iam"

  project_name      = var.project_name
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  s3_bucket_arn     = module.s3.bucket_arn
  kms_key_arn       = module.kms.key_arn
  bedrock_model_id  = var.bedrock_model_id
  dynamodb_table_arn = module.dynamodb.table_arn
  tags              = var.tags
}

# ── Outputs ──────────────────────────────────────────────────
# These are displayed after terraform apply and can be
# referenced by other systems (Jenkins, kubectl config, etc.)
output "cluster_endpoint" {
  description = "EKS cluster endpoint — add to kubeconfig"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_url" {
  description = "ECR URL — used in Jenkins pipeline and K8s manifests"
  value       = module.ecr.repository_url
}

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "app_role_arn" {
  description = "IRSA role ARN — annotate K8s service account with this"
  value       = module.iam.app_role_arn
}

output "kms_key_alias" {
  value = module.kms.alias_name
}
