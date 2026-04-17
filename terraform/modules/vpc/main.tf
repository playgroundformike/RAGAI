# ============================================================
# VPC Module — Network Foundation
# ============================================================
#
# Creates an isolated VPC with:
#   - Public subnets (load balancers, NAT gateways)
#   - Private subnets (EKS worker nodes, application pods)
#   - NAT Gateway (private subnets reach internet for pulling images)
#   - No Internet Gateway on private subnets (inbound blocked)
#
# Why a dedicated VPC instead of the default VPC?
#   - The default VPC has wide-open security groups and public subnets
#   - DoD/NIST requires network segmentation (SC-7 Boundary Protection)
#   - Dedicated CIDR range prevents IP conflicts with other workloads
#   - VPC Flow Logs enable network traffic audit (AU-3)
#
# Subnet strategy:
#   - 2 AZs minimum (EKS requires multi-AZ for control plane HA)
#   - Private subnets: EKS nodes, pods, RDS (future)
#   - Public subnets: ALB ingress, NAT gateway
#
# NIST 800-53 Controls:
#   SC-7  (Boundary Protection) — private subnets, NACLs, security groups
#   AU-3  (Audit Records) — VPC Flow Logs to CloudWatch
#   AC-4  (Information Flow Enforcement) — subnet isolation
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ──────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Required for EKS — enables DNS hostname resolution for pods
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc"
    # EKS requires this tag to discover the VPC
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ── Public Subnets ───────────────────────────────────────────
# These host the ALB (Application Load Balancer) and NAT Gateway.
# They have a route to the Internet Gateway for inbound/outbound traffic.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Public IPs for ALB — EKS nodes should NOT be in public subnets
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-${data.aws_availability_zones.available.names[count.index]}"
    # EKS uses these tags to know which subnets to place load balancers in
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  })
}

# ── Private Subnets ──────────────────────────────────────────
# These host EKS worker nodes and application pods.
# They have NO direct internet access — outbound goes through NAT.
# Inbound is only possible through the ALB in public subnets.
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.az_count)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # No public IPs — these are private subnets
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # internal-elb tag tells EKS this is for internal load balancers
    "kubernetes.io/role/internal-elb"           = "1"
  })
}

# ── Internet Gateway ─────────────────────────────────────────
# Allows public subnets to reach the internet (and be reached).
# Only attached to the VPC — doesn't automatically give all subnets
# internet access. That's controlled by route tables.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw"
  })
}

# ── NAT Gateway ──────────────────────────────────────────────
# Allows private subnets to reach the internet (outbound only).
# Used for: pulling container images from ECR, AWS API calls,
# OS package updates on worker nodes.
# Inbound traffic from the internet CANNOT reach private subnets
# through NAT — it's one-way only.
#
# Cost note: NAT Gateway costs ~$32/month + data processing.
# For a portfolio project, you might want to destroy this when
# not actively testing. In production, it runs 24/7.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# ── Route Tables ─────────────────────────────────────────────
# Public route table: 0.0.0.0/0 → Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Private route table: 0.0.0.0/0 → NAT Gateway (outbound only)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-rt"
  })
}

# Associate subnets with their route tables
resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── VPC Flow Logs ────────────────────────────────────────────
# AU-3: Log all network traffic for security audit.
# Flow logs capture: source/dest IP, ports, protocol, action (accept/reject).
# In production, these feed into Splunk for SIEM analysis.
resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = var.flow_log_retention_days

  tags = var.tags
}

# IAM role for VPC Flow Logs to write to CloudWatch
resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}
