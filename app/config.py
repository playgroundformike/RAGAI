"""
Centralized application configuration.

DoD/Compliance Rationale:
- All configuration lives in ONE file — auditors can grep this single file
  to verify no secrets are hardcoded.
- Pydantic BaseSettings loads values from environment variables, which in
  production are injected via Kubernetes Secrets (backed by AWS Secrets Manager)
  or SSM Parameter Store.
- Secret values are typed as SecretStr — Pydantic will mask them in logs/repr,
  preventing accidental exposure in debug output or stack traces.

NIST 800-53 Controls:
  SC-12 (Cryptographic Key Management) — KMS key ID externalized
  SC-28 (Protection of Information at Rest) — encryption config centralized
  AC-3  (Access Enforcement) — IAM/IRSA config externalized, not hardcoded
"""

from pydantic_settings import BaseSettings
from pydantic import Field
from functools import lru_cache


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.
    In production on EKS, these come from:
      - ConfigMaps (non-sensitive settings)
      - Kubernetes Secrets synced from AWS Secrets Manager (sensitive values)
    """

    # ── App Settings ──────────────────────────────────────────────
    app_name: str = "SecureGenAI Document Assistant"
    app_version: str = "0.1.0"
    environment: str = Field(
        default="development",
        description="development | staging | production — controls debug output, "
        "log verbosity, and CORS policy. NEVER run debug=True in production.",
    )
    log_level: str = Field(
        default="INFO",
        description="Log level. Set to DEBUG only in dev. "
        "In DoD environments, INFO/WARN ensures audit trail without leaking data.",
    )
    max_upload_size_mb: int = Field(
        default=10,
        description="Max file upload size in MB. Limits resource exhaustion attacks.",
    )
    allowed_file_types: list[str] = [".pdf", ".txt"]

    # ── AWS General ───────────────────────────────────────────────
    aws_region: str = Field(
        default="us-east-1",
        description="AWS region. In GovCloud this would be us-gov-west-1.",
    )
    aws_endpoint_url: str | None = Field(
        default=None,
        description="Override AWS endpoint URL. Set to LocalStack URL for local dev "
        "(http://localstack:4566). None = use real AWS endpoints. "
        "This is read from AWS_ENDPOINT_URL env var (no SECUREGENAI_ prefix) "
        "so it works with standard AWS SDK configuration.",
    )

    # ── S3 Settings ───────────────────────────────────────────────
    s3_bucket_name: str = Field(
        default="securegenai-documents",
        description="S3 bucket for document storage. In production, created by "
        "Terraform with versioning, encryption, and bucket policy enforcing "
        "ssl-only access (s3:SecureTransport).",
    )
    s3_prefix: str = Field(
        default="uploads/",
        description="S3 key prefix. Enables IAM policies scoped to this prefix.",
    )

    # ── KMS Settings ──────────────────────────────────────────────
    kms_key_id: str = Field(
        default="alias/securegenai-document-key",
        description="KMS key alias or ARN for server-side encryption. "
        "SC-12: All data at rest encrypted with customer-managed CMK, "
        "not the default aws/s3 key — gives us key rotation control.",
    )

    # ── Bedrock Settings ──────────────────────────────────────────
    bedrock_model_id: str = Field(
        default="anthropic.claude-3-sonnet-20240229-v1:0",
        description="Bedrock model identifier. Pinned to a specific version — "
        "never use 'latest' in production. Model changes need change board approval.",
    )
    bedrock_max_tokens: int = Field(
        default=2048,
        description="Max response tokens. Controls cost and response length.",
    )
    bedrock_temperature: float = Field(
        default=0.1,
        description="Low temperature = more deterministic responses. "
        "For document Q&A, we want precision over creativity.",
    )

    # ── DynamoDB Settings ─────────────────────────────────────────
    dynamodb_table_name: str = Field(
        default="securegenai-document-registry",
        description="DynamoDB table for document metadata tracking. "
        "AU-3 (Audit Events): tracks who uploaded what, when, file hash.",
    )

    model_config = {
        "env_prefix": "SECUREGENAI_",
        "env_file": ".env",
        "case_sensitive": False,
    }


@lru_cache()
def get_settings() -> Settings:
    """
    Cached settings singleton. lru_cache ensures we only parse env vars once.
    In FastAPI, this is injected via Depends(get_settings) — making it
    testable (you can override it in tests with mock config).
    """
    return Settings()
