variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in subnet tags for EKS discovery"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /16 gives 65,536 IPs — plenty for EKS."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones. Minimum 2 for EKS HA."
  type        = number
  default     = 2
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC flow logs. DoD typically requires 90-365 days."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
