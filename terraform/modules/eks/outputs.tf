output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for kubectl config"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster control plane security group ID"
  value       = aws_security_group.cluster.id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — needed for IRSA role trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https:// prefix)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "node_role_arn" {
  description = "Worker node IAM role ARN"
  value       = aws_iam_role.node.arn
}
