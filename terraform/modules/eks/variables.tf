variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. Pin to a specific version — upgrades need testing."
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for worker nodes"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for envelope encryption of K8s secrets"
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum worker nodes (autoscaling floor)"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum worker nodes (autoscaling ceiling)"
  type        = number
  default     = 4
}

variable "enable_public_endpoint" {
  description = "Enable public API endpoint. False for production (access via VPN only)."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
