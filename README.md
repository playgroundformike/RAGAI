# SecureGenAI Document Assistant

A secure, DoD-aligned GenAI infrastructure project demonstrating a production-ready document Q&A system built on AWS GovCloud patterns. Users upload documents (PDF/text), which are stored encrypted in S3, then ask questions answered by AWS Bedrock (Claude) grounded in the document content.

**This project demonstrates the full DevSecOps lifecycle** — not just the application, but the infrastructure, CI/CD pipeline, security hardening, observability, and compliance documentation required to operate AI workloads in controlled environments.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS Account (IL4/IL5)                        │
│                                                                         │
│  ┌──────────────────────── VPC (10.0.0.0/16) ──────────────────────┐   │
│  │                                                                   │   │
│  │  ┌─── Public Subnets ───┐    ┌──── Private Subnets ────────┐    │   │
│  │  │                       │    │                              │    │   │
│  │  │  ┌─────────────────┐  │    │  ┌────────────────────────┐ │    │   │
│  │  │  │   ALB Ingress   │──│────│─▶│     EKS Cluster        │ │    │   │
│  │  │  └─────────────────┘  │    │  │  ┌──────────────────┐  │ │    │   │
│  │  │  ┌─────────────────┐  │    │  │  │ SecureGenAI Pods │  │ │    │   │
│  │  │  │   NAT Gateway   │  │    │  │  │  ┌────────────┐  │  │ │    │   │
│  │  │  └────────┬────────┘  │    │  │  │  │  FastAPI   │  │  │ │    │   │
│  │  └───────────│───────────┘    │  │  │  │  + Gunicorn │  │  │ │    │   │
│  │              │                │  │  │  └──────┬─────┘  │  │ │    │   │
│  │              │                │  │  │         │        │  │ │    │   │
│  │              ▼                │  │  └─────────│────────┘  │ │    │   │
│  │         Internet              │  │            │           │ │    │   │
│  │         (outbound)            │  └────────────│───────────┘ │    │   │
│  └───────────────────────────────│───────────────│─────────────┘    │   │
│                                  │               │                   │   │
│  ┌───────────────────────────────│───────────────│─────────────────┐ │   │
│  │                     AWS Services              │                 │ │   │
│  │                                               │                 │ │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐   │  ┌───────────┐  │ │   │
│  │  │  S3      │  │   KMS    │  │ DynamoDB │   │  │  Bedrock  │  │ │   │
│  │  │ (SSE-KMS)│  │  (CMK)   │  │(metadata)│◀──┘  │  (Claude) │  │ │   │
│  │  └──────────┘  └──────────┘  └──────────┘      └───────────┘  │ │   │
│  │                                                                 │ │   │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────────────────────┐   │ │   │
│  │  │   ECR    │  │ Secrets  │  │ CloudWatch / Splunk Logs   │   │ │   │
│  │  │ (images) │  │ Manager  │  │ (VPC Flow + App + Audit)   │   │ │   │
│  │  └──────────┘  └──────────┘  └────────────────────────────┘   │ │   │
│  └─────────────────────────────────────────────────────────────────┘ │   │
└─────────────────────────────────────────────────────────────────────────┘

CI/CD Pipeline (Jenkins):
  git push → Checkout → Lint/Test → Build → Trivy Scan → OpenSCAP STIG → Push ECR → Deploy EKS
                                              │               │
                                          GATE: block     GATE: block
                                          CRITICAL/HIGH   if score < 80%
```

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Application | FastAPI + Python 3.12 | REST API for document upload and Q&A |
| AI/ML | AWS Bedrock (Claude) | Document-grounded question answering (RAG) |
| Storage | S3 (SSE-KMS) | Encrypted document storage |
| Metadata | DynamoDB | Document registry and audit trail |
| Encryption | KMS (CMK) | Customer-managed encryption keys |
| Container | Docker (multi-stage) | Non-root, minimal attack surface |
| Orchestration | EKS (Kubernetes) | Pod scheduling, scaling, self-healing |
| IaC | Terraform + Terragrunt | Reproducible infrastructure across environments |
| CI/CD | Jenkins | Gated pipeline with security scanning |
| Vulnerability Scan | Trivy | Container CVE detection |
| STIG Compliance | OpenSCAP | DISA STIG benchmark verification |
| Node Hardening | Ansible | RHEL STIG hardening for EKS workers |
| Observability | Prometheus + Grafana | Metrics, dashboards, alerting |
| Log Aggregation | CloudWatch + Splunk | Centralized audit logging |

## Project Structure

```
├── app/                          # FastAPI application
│   ├── main.py                   # App entrypoint + middleware + health check
│   ├── config.py                 # Centralized config (env vars, no secrets)
│   ├── models.py                 # Pydantic request/response schemas
│   ├── metrics.py                # Prometheus metrics middleware
│   ├── routers/
│   │   ├── upload.py             # POST /api/v1/upload
│   │   └── query.py              # POST /api/v1/query
│   └── services/
│       ├── s3.py                 # S3 operations (KMS-encrypted upload/download)
│       ├── bedrock.py            # Bedrock Converse API (RAG query)
│       └── document.py           # PDF/text extraction
├── tests/                        # Unit tests (16 tests, 0.9s)
├── Dockerfile                    # Multi-stage build, non-root, hardened
├── docker-compose.yml            # Local dev stack (app + LocalStack)
├── Jenkinsfile                   # 7-stage CI/CD with security gates
├── k8s/                          # Kubernetes manifests
│   ├── namespace.yaml            # Pod Security Standards (restricted)
│   ├── serviceaccount.yaml       # IRSA bridge (K8s SA → IAM role)
│   ├── deployment.yaml           # Hardened pod spec (read-only FS, no caps)
│   ├── service.yaml              # ClusterIP service
│   └── networkpolicy.yaml        # Microsegmentation (ingress/egress rules)
├── terraform/                    # Infrastructure as Code
│   ├── modules/                  # Reusable Terraform modules
│   │   ├── vpc/                  # VPC + subnets + NAT + flow logs
│   │   ├── eks/                  # EKS cluster + node groups + OIDC
│   │   ├── s3/                   # Encrypted bucket + versioning + lifecycle
│   │   ├── kms/                  # CMK + key policy + alias
│   │   ├── ecr/                  # Container registry + scanning + lifecycle
│   │   ├── iam/                  # IRSA role + least-privilege policies
│   │   └── dynamodb/             # Document registry + PITR + encryption
│   ├── environments/
│   │   ├── dev/                  # Dev-specific values
│   │   └── prod/                 # Prod-hardened values
│   └── terragrunt.hcl            # Shared config (backend, provider)
├── ansible/                      # Node-level STIG hardening
│   ├── site.yml                  # Main playbook
│   └── roles/stig_hardening/     # 9 task categories (SSH, audit, kernel, etc.)
├── monitoring/                   # Observability stack
│   ├── prometheus/               # Scrape config + 8 alert rules
│   ├── grafana/                  # 10-panel dashboard + datasource
│   └── alertmanager/             # Alert routing (PagerDuty + Slack)
└── docs/rmf/                     # RMF compliance documentation
    ├── system-security-plan.md   # SSP overview
    └── poam.md                   # Plan of Action & Milestones
```

## Quick Start (Local Development)

### Prerequisites
- Docker and docker-compose
- Python 3.12+ (for running tests outside Docker)

### Run the Full Stack Locally

```bash
# Clone the repository
git clone https://github.com/playgroundformike/secure-genai-doc-assistant.git
cd secure-genai-doc-assistant

# Start the app + LocalStack (mock AWS)
docker-compose up --build

# The API is now running at http://localhost:8000
# Swagger UI at http://localhost:8000/docs
```

### Test Document Upload

```bash
# Upload a text file
curl -X POST http://localhost:8000/api/v1/upload \
  -F "file=@sample-document.txt"

# Response includes a document_id for querying
```

### Run Tests

```bash
pip install -r requirements.txt
pip install pytest pytest-asyncio
python -m pytest tests/ -v
```

## Security Controls

Every architectural decision maps to a NIST 800-53 control:

| Control | Implementation |
|---|---|
| SC-28 (Protection at Rest) | S3 SSE-KMS encryption, DynamoDB KMS encryption, EKS secret envelope encryption |
| SC-7 (Boundary Protection) | Private subnets, VPC flow logs, network policies, private EKS endpoint |
| AC-6 (Least Privilege) | IRSA per-pod IAM roles, scoped to specific resources |
| CM-7 (Least Functionality) | Multi-stage Docker build, disabled unnecessary services, minimal base image |
| RA-5 (Vulnerability Scanning) | Trivy CVE scan in CI/CD pipeline (CRITICAL/HIGH gate) |
| CM-6 (Configuration Settings) | OpenSCAP STIG compliance gate in CI/CD (80% threshold) |
| AU-3 (Audit Records) | auditd on nodes, structured app logging, VPC flow logs |
| SI-6 (Security Verification) | AIDE file integrity monitoring, K8s liveness/readiness probes |
| CM-3 (Change Control) | Jenkins gated pipeline — security scans must pass before deployment |
| IA-5 (Authenticator Management) | IRSA temporary credentials, no static keys, key-only SSH |

## Design Decisions

### Why Bedrock instead of direct API calls?
Bedrock runs within the AWS account boundary. Document content never leaves the VPC/account, which is required for IL4/IL5 data classification. Direct API calls to external endpoints would fail the SC-7 boundary protection requirement.

### Why FastAPI + EKS instead of API Gateway + Lambda?
The ECAWS team at Lincoln Lab operates an EKS platform. This project demonstrates container orchestration, CI/CD pipelines, STIG hardening, and Kubernetes security — skills that don't apply in a serverless architecture. The Bedrock query latency (10-30s) also makes long-running container processes more natural than Lambda functions.

### Why Terragrunt?
Multi-environment Terraform without copy-pasting. Dev and prod share the same module code with different input values. The root `terragrunt.hcl` handles remote state and provider config once, eliminating the most common source of Terraform drift between environments.

### Why IRSA instead of instance roles?
Instance roles give every pod on a node the same AWS permissions. IRSA scopes permissions to a specific Kubernetes service account in a specific namespace. Our app pod can access S3 and Bedrock; a monitoring pod on the same node cannot. This is the Kubernetes-native implementation of least privilege.

## RMF Documentation

See [`docs/rmf/`](docs/rmf/) for:
- **System Security Plan (SSP)** — system boundary, control implementations
- **Plan of Action & Milestones (POA&M)** — known gaps and remediation timeline

---

*Built as a portfolio project targeting DevOps Engineer roles in DoD/IC environments. Demonstrates production-grade DevSecOps practices applied to a GenAI workload.*
