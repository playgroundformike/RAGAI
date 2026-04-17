output "vpc_id" {
  description = "VPC ID — referenced by EKS, security groups, and other modules"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — where EKS worker nodes run"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs — where ALB and NAT Gateway live"
  value       = aws_subnet.public[*].id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}
