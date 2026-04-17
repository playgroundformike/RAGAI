# System Security Plan (SSP)
## SecureGenAI Document Assistant

| Field | Value |
|---|---|
| System Name | SecureGenAI Document Assistant |
| System Owner | Platform Engineering Team |
| Information Type | CUI (Controlled Unclassified Information) |
| Impact Level | Moderate (IL4) |
| Authorization Boundary | AWS Account + EKS Cluster |
| Date | 2024-12-01 |
| Status | Draft — Portfolio Demonstration |

---

## 1. System Description

### 1.1 Purpose

SecureGenAI Document Assistant is a secure document question-answering system that allows authorized users to upload documents and ask questions about their content. The system uses a Retrieval-Augmented Generation (RAG) pattern with AWS Bedrock (Claude) to provide answers grounded in uploaded document context.

### 1.2 System Boundary

The authorization boundary encompasses all components within the AWS account:

**In-Boundary Components:**
- FastAPI application running on EKS (pods, service accounts, services)
- EKS cluster (control plane, worker nodes, OIDC provider)
- VPC (subnets, NAT gateway, security groups, NACLs)
- S3 bucket (document storage, encrypted with KMS)
- DynamoDB table (document metadata registry)
- KMS customer-managed key (encryption key for all data at rest)
- ECR repository (container image storage)
- CloudWatch log groups (application and VPC flow logs)
- IAM roles and policies (cluster, node, IRSA)
- Jenkins CI/CD pipeline (build, test, scan, deploy)

**Out-of-Boundary Components (inherited controls):**
- AWS Bedrock service (FedRAMP-authorized, inherits AWS controls)
- AWS KMS service (FIPS 140-2 validated)
- AWS EKS control plane (managed by AWS)
- DNS resolution (Route 53)

### 1.3 Data Flow

```
User → ALB → EKS Pod (FastAPI) → S3 (upload, encrypted)
User → ALB → EKS Pod (FastAPI) → S3 (retrieve) → Bedrock (query) → User (answer)
```

All data flows occur over TLS 1.2+. Document content transits between S3 and Bedrock within the AWS account boundary and never traverses the public internet.

### 1.4 Users and Roles

| Role | Access | Authentication |
|---|---|---|
| End User | Upload documents, query documents | OAuth/JWT (future) |
| Platform Admin | Manage EKS, Terraform, Jenkins | IAM + MFA |
| Auditor | Read-only access to logs and dashboards | IAM (read-only role) |

---

## 2. Control Implementation Summary

### 2.1 Access Control (AC)

| Control | Implementation |
|---|---|
| AC-2 (Account Management) | IAM roles for all access. No shared accounts. IRSA for pod identity. |
| AC-3 (Access Enforcement) | K8s RBAC scoped per namespace. IAM policies scoped per resource ARN. |
| AC-6 (Least Privilege) | IRSA role allows only: S3 PutObject/GetObject on specific bucket, KMS Encrypt/Decrypt on specific key, Bedrock InvokeModel on specific model, DynamoDB read/write on specific table. |
| AC-7 (Unsuccessful Login) | SSH: faillock after 3 failed attempts, 15-minute lockout. |
| AC-8 (System Use Notification) | DoD-standard login banner deployed to /etc/issue, /etc/issue.net, /etc/motd. |
| AC-11 (Session Lock) | SSH ClientAliveInterval=600s, ClientAliveCountMax=0 (10-min idle disconnect). |
| AC-17 (Remote Access) | SSH key-only authentication. FIPS-approved ciphers only. Root login disabled. |

### 2.2 Audit and Accountability (AU)

| Control | Implementation |
|---|---|
| AU-2 (Audit Events) | auditd on worker nodes monitors: login events, privilege escalation, file modifications, time changes, kernel module loading. |
| AU-3 (Content of Audit Records) | Application logs include: timestamp, request method, endpoint, status code, document_id, model_id, token counts. Logs exclude: document content, user questions, model answers (PII risk). |
| AU-6 (Audit Review) | Prometheus metrics + Grafana dashboards for real-time monitoring. Alert rules fire on anomalies. |
| AU-11 (Audit Record Retention) | VPC flow logs: 90-day retention. Application logs: CloudWatch with configurable retention. Audit logs: forwarded to Splunk. |

### 2.3 Configuration Management (CM)

| Control | Implementation |
|---|---|
| CM-3 (Change Control) | Jenkins pipeline gates: code changes must pass lint, test, Trivy scan, and OpenSCAP STIG before deployment. Feature branches cannot deploy to production. |
| CM-6 (Configuration Settings) | OpenSCAP STIG compliance verified on every build. Minimum 80% compliance score required. |
| CM-7 (Least Functionality) | Multi-stage Docker build: runtime image has no build tools, pip, or compilers. Unnecessary OS services disabled via Ansible. Container filesystem is read-only. |

### 2.4 Identification and Authentication (IA)

| Control | Implementation |
|---|---|
| IA-5 (Authenticator Management) | IRSA: temporary credentials, auto-rotated by STS. SSH: key-only authentication. Passwords: 15-char minimum, 4 character classes, 60-day rotation. No static AWS access keys in application code or configuration. |

### 2.5 Risk Assessment (RA)

| Control | Implementation |
|---|---|
| RA-5 (Vulnerability Scanning) | Trivy scans every container image before ECR push. ECR native scanning on push. Pipeline fails on CRITICAL or HIGH CVEs. Scan reports archived as Jenkins artifacts for audit. |

### 2.6 System and Communications Protection (SC)

| Control | Implementation |
|---|---|
| SC-7 (Boundary Protection) | VPC with private subnets for EKS. No direct internet access to worker nodes. Network policies restrict pod-to-pod traffic. EKS API endpoint is private (production). VPC flow logs capture all network traffic. |
| SC-8 (Transmission Confidentiality) | All external traffic over TLS 1.2+. S3 bucket policy denies non-HTTPS access. SSH uses FIPS-approved ciphers. |
| SC-12 (Cryptographic Key Management) | Customer-managed KMS key with annual auto-rotation. Key policy restricts usage to specific IAM roles. CloudTrail logs all key usage. |
| SC-28 (Protection at Rest) | S3: SSE-KMS (per-object encryption enforced at both bucket default and application level). DynamoDB: KMS encryption. EKS: envelope encryption for Kubernetes secrets. ECR: KMS encryption for stored images. |

### 2.7 System and Information Integrity (SI)

| Control | Implementation |
|---|---|
| SI-2 (Flaw Remediation) | dnf-automatic configured for security-only updates on worker nodes. Container base images updated in CI/CD pipeline. |
| SI-4 (System Monitoring) | Prometheus scrapes application and node metrics every 15s. 8 alert rules cover error rates, latency, pod health, and resource usage. Grafana dashboards provide real-time visibility. |
| SI-6 (Security Verification) | AIDE file integrity monitoring on worker nodes (daily cron check). K8s liveness and readiness probes verify application health continuously. |
| SI-10 (Information Input Validation) | Pydantic models validate all API input. File type allowlist (PDF, TXT only). File size limit (10MB). Question length limit (2000 chars). Filename sanitization prevents directory traversal. |

---

## 3. Continuous Monitoring Strategy

| Activity | Frequency | Tool |
|---|---|---|
| Container vulnerability scan | Every build | Trivy (Jenkins) |
| STIG compliance check | Every build | OpenSCAP (Jenkins) |
| Application metrics collection | Every 15 seconds | Prometheus |
| Alert evaluation | Every 15 seconds | Prometheus + Alertmanager |
| Dashboard review | Daily (operations) | Grafana |
| VPC flow log analysis | Continuous | CloudWatch → Splunk |
| Node file integrity check | Daily at 05:00 | AIDE (cron) |
| OS security patches | Daily (automatic) | dnf-automatic |
| Audit log review | Weekly | Splunk SIEM |
| Full STIG reassessment | Quarterly | OpenSCAP (manual) |
