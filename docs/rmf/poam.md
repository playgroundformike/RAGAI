# Plan of Action & Milestones (POA&M)
## SecureGenAI Document Assistant

| Field | Value |
|---|---|
| System Name | SecureGenAI Document Assistant |
| Date Prepared | 2024-12-01 |
| Prepared By | Platform Engineering |
| Status | Draft — Portfolio Demonstration |

---

## Purpose

This POA&M documents known security gaps, their risk level, and the planned remediation timeline. Items are tracked from identification through resolution. This is a living document updated as items are addressed or new findings are identified.

---

## Open Items

### POAM-001: Authentication and Authorization Not Implemented

| Field | Detail |
|---|---|
| Control | AC-2, AC-3, IA-2, IA-8 |
| Finding | API endpoints do not enforce user authentication or authorization. Any network-reachable client can upload documents and query the system. |
| Risk | **High** — Unauthorized access to document upload and query functionality. |
| Mitigation | Application is deployed behind ALB with VPC-only access. No public-facing endpoint in current architecture. |
| Remediation Plan | Implement OAuth 2.0 / OIDC authentication via AWS Cognito or Keycloak. Add JWT validation middleware to FastAPI. Implement per-user document ownership checks. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

### POAM-002: DynamoDB Document Registry Not Integrated

| Field | Detail |
|---|---|
| Control | AU-3, AC-6 |
| Finding | DynamoDB table is provisioned by Terraform and created in LocalStack, but the application does not write document metadata to it. Upload events are not tracked in a queryable registry. |
| Risk | **Medium** — Reduced audit trail. Document lifecycle events (upload, query, deletion) are only captured in application logs, not in a structured, queryable store. |
| Mitigation | Application logs capture upload events with document_id, timestamp, and file metadata. Logs are forwarded to CloudWatch/Splunk. |
| Remediation Plan | Add DynamoDB writes to the upload router. Record: document_id, filename, upload_timestamp, file_hash (SHA-256), content_type, size_bytes, upload_source_ip. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

### POAM-003: Bedrock Not Testable Locally

| Field | Detail |
|---|---|
| Control | SA-11 |
| Finding | LocalStack does not support AWS Bedrock. The /api/v1/query endpoint cannot be tested end-to-end in the local development environment. |
| Risk | **Low** — Application logic is tested via unit tests with mocked services. Integration testing requires AWS credentials. |
| Mitigation | Unit tests validate all non-AWS logic (input validation, text extraction, config loading). Bedrock service is isolated behind a service interface that can be mocked. |
| Remediation Plan | Create a mock Bedrock service that returns static responses for local testing. Add integration test suite that runs against real AWS in a CI/CD staging environment. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

### POAM-004: HTTPS/TLS Not Enforced at Application Level

| Field | Detail |
|---|---|
| Control | SC-8 |
| Finding | FastAPI application serves HTTP on port 8000. TLS termination is expected at the ALB/Ingress layer, but this is not configured in the current K8s manifests. |
| Risk | **Medium** — Traffic between ALB and pod is unencrypted within the VPC. While VPC traffic is isolated, this does not meet SC-8 for end-to-end encryption. |
| Mitigation | VPC network isolation + K8s network policies restrict traffic to authorized sources. In-VPC traffic interception requires node-level compromise. |
| Remediation Plan | Option A: Configure Ingress with TLS termination at ALB (most common). Option B: Add TLS certificates to gunicorn for end-to-end encryption. Option C: Implement service mesh (Istio) for mutual TLS between all pods. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

### POAM-005: Container Base Image is Debian, Not RHEL

| Field | Detail |
|---|---|
| Control | CM-6 |
| Finding | The Dockerfile uses python:3.12-slim (Debian-based). DISA STIGs are written for RHEL. The OpenSCAP STIG check in the Jenkins pipeline uses RHEL benchmarks against a Debian container, which produces inaccurate compliance scores. |
| Risk | **Medium** — STIG compliance score is not representative of actual security posture for the container image. Node-level STIG (Ansible) is accurate for RHEL worker nodes. |
| Mitigation | The container is hardened at the K8s level: non-root user, read-only filesystem, all capabilities dropped, seccomp profile, resource limits. These controls achieve the intent of STIG requirements regardless of OS. |
| Remediation Plan | Migrate to a RHEL UBI (Universal Base Image) base: `registry.access.redhat.com/ubi9/python-312`. This aligns the container OS with the STIG benchmark and enables accurate OpenSCAP scoring. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

### POAM-006: Secrets Management Not Fully Automated

| Field | Detail |
|---|---|
| Control | SC-12, IA-5 |
| Finding | The architecture references AWS Secrets Manager and K8s Secrets for sensitive configuration, but the sync mechanism (Secrets Store CSI Driver or External Secrets Operator) is not implemented. |
| Risk | **Low** — No secrets are currently hardcoded. IRSA provides credentials without static keys. Non-sensitive config is in environment variables. |
| Mitigation | All AWS credentials are managed via IRSA (temporary, auto-rotated). Application config values (bucket names, model IDs) are not sensitive. |
| Remediation Plan | Deploy External Secrets Operator to sync AWS Secrets Manager secrets to K8s Secrets. Configure K8s Secrets as environment variables in the deployment manifest. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

### POAM-007: No Rate Limiting on API Endpoints

| Field | Detail |
|---|---|
| Control | SC-5 |
| Finding | API endpoints do not enforce rate limits. A malicious or misconfigured client could overwhelm the application with requests, causing denial of service and excessive Bedrock costs. |
| Risk | **Medium** — Resource exhaustion risk for compute (pod CPU/memory) and cost (Bedrock is billed per token). |
| Mitigation | K8s resource limits cap per-pod CPU and memory. EKS horizontal pod autoscaler would add pods under load (not yet configured). |
| Remediation Plan | Add rate limiting middleware to FastAPI (slowapi or custom). Implement per-user and per-IP rate limits. Configure AWS WAF on ALB for additional protection. |
| Target Date | Phase 2 — Q1 2025 |
| Status | Open |

---

## Closed Items

*No items have been closed yet. This section will track remediated findings with closure dates and evidence.*

---

## Summary

| Severity | Open | Closed |
|---|---|---|
| High | 1 | 0 |
| Medium | 4 | 0 |
| Low | 2 | 0 |
| **Total** | **7** | **0** |

The high-severity finding (POAM-001: missing authentication) is the highest priority item. It is partially mitigated by network-level access controls but must be addressed before the system processes real CUI data.

All open items are planned for Phase 2. The current Phase 1 deliverable demonstrates the infrastructure, pipeline, and security hardening patterns. Phase 2 adds the application-layer security controls needed for production deployment.
