# ============================================================
# EKS Module — Kubernetes Cluster
# ============================================================
#
# Creates an EKS cluster with:
#   - Managed node group (AWS handles node provisioning/updates)
#   - Private API endpoint (cluster API not exposed to internet)
#   - Envelope encryption for Kubernetes secrets (using KMS)
#   - OIDC provider for IRSA (IAM Roles for Service Accounts)
#
# Why EKS managed node groups instead of self-managed?
#   - AWS handles AMI updates and node draining during upgrades
#   - Automatic security patching via managed AMI
#   - Still allows custom launch templates for STIG hardening
#
# Why private endpoint access?
#   - The Kubernetes API server is only reachable from within the VPC
#   - kubectl access requires VPN or bastion host
#   - Prevents internet-based attacks on the control plane
#
# NIST 800-53 Controls:
#   SC-7  (Boundary Protection) — private API endpoint
#   SC-28 (Protection at Rest) — envelope encryption for K8s secrets
#   AC-2  (Account Management) — RBAC via aws-auth configmap
#   CM-7  (Least Functionality) — minimal node AMI
# ============================================================

# ── EKS Cluster ──────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.private_subnet_ids

    # SC-7: Private endpoint = API server only reachable from VPC.
    # Public endpoint disabled = no kubectl from the internet.
    # In a real environment, you'd access via VPN or bastion.
    endpoint_private_access = true
    endpoint_public_access  = var.enable_public_endpoint

    # Security group for the cluster control plane
    security_group_ids = [aws_security_group.cluster.id]
  }

  # SC-28: Encrypt Kubernetes secrets at rest with our KMS key.
  # Without this, K8s secrets (like DB passwords stored in etcd)
  # are only base64-encoded — not actually encrypted.
  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  # Enable control plane logging for audit trail (AU-3).
  # These logs go to CloudWatch and can be forwarded to Splunk.
  enabled_cluster_log_types = [
    "api",          # API server requests (who did what)
    "audit",        # Kubernetes audit log (all API calls with details)
    "authenticator", # IAM authentication events
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]

  tags = var.tags
}

# ── Managed Node Group ───────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  # Instance sizing — t3.medium is the minimum for EKS.
  # For Bedrock workloads, you might need larger instances
  # if doing heavy document processing.
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_count
    min_size     = var.node_min_count
    max_size     = var.node_max_count
  }

  # Use the latest EKS-optimized AMI.
  # In production, you'd pin to a specific AMI version
  # and use a custom launch template with STIG hardening
  # applied via Ansible (Step 5 in our build plan).
  ami_type = "AL2023_x86_64_STANDARD"

  # Force pods off nodes before terminating during updates
  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "worker"
    env  = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = var.tags
}

# ── OIDC Provider for IRSA ───────────────────────────────────
# IRSA = IAM Roles for Service Accounts.
# This lets Kubernetes pods assume specific IAM roles WITHOUT
# putting AWS credentials in the pod. The pod's service account
# is mapped to an IAM role via the OIDC provider.
#
# Why IRSA instead of instance roles?
#   - Instance roles: every pod on the node shares the same permissions
#   - IRSA: each pod gets exactly the permissions it needs (least privilege)
#   - IRSA credentials are short-lived and auto-rotated
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# ── Cluster Security Group ───────────────────────────────────
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  # Allow worker nodes to communicate with control plane
  ingress {
    description = "Worker node to cluster API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── IAM Roles ────────────────────────────────────────────────

# Cluster role — allows EKS service to manage AWS resources
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# Node role — allows EC2 instances to join the cluster
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}
