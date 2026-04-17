"""
Pydantic models for request/response validation.

Why Pydantic models matter for security:
- FastAPI uses these to VALIDATE all input before your code touches it.
  A malformed request gets rejected at the framework level — your business
  logic never sees bad data.
- Response models control what gets returned to the client. Without them,
  you risk leaking internal fields (S3 keys, internal IDs, error details).
- OpenAPI schema auto-generated from these models — auditors can review
  the full API contract without reading implementation code.
"""

from pydantic import BaseModel, Field
from datetime import datetime


# ── Upload Models ─────────────────────────────────────────────────


class UploadResponse(BaseModel):
    """Returned after successful document upload."""

    document_id: str = Field(
        description="Unique identifier for the uploaded document (UUID4)."
    )
    filename: str = Field(description="Original filename as uploaded.")
    s3_key: str = Field(description="S3 object key (not the full ARN — least info needed).")
    content_type: str = Field(description="MIME type of uploaded file.")
    size_bytes: int = Field(description="File size for client-side verification.")
    uploaded_at: datetime = Field(description="Server-side timestamp (UTC).")
    message: str = "Document uploaded successfully."


# ── Query Models ──────────────────────────────────────────────────


class QueryRequest(BaseModel):
    """
    User's question about an uploaded document.

    Note: document_id is validated as non-empty. In production you'd also
    check that the requesting user owns this document (AuthZ check).
    """

    document_id: str = Field(
        ...,
        min_length=1,
        description="ID of the document to query against.",
    )
    question: str = Field(
        ...,
        min_length=1,
        max_length=2000,
        description="User's question. Max 2000 chars prevents prompt injection "
        "via extremely long inputs and controls Bedrock token costs.",
    )


class QueryResponse(BaseModel):
    """Returned after Bedrock processes the query."""

    document_id: str
    question: str
    answer: str = Field(
        description="Bedrock model response grounded in document context."
    )
    model_id: str = Field(
        description="Which model generated this response — important for "
        "audit trail and reproducibility (AU-3).",
    )
    usage: dict = Field(
        default_factory=dict,
        description="Token usage stats for cost tracking.",
    )


# ── Health Check ──────────────────────────────────────────────────


class HealthResponse(BaseModel):
    """
    Health check response. Kubernetes liveness/readiness probes hit this.
    Includes dependency status so you can tell if S3/Bedrock are reachable.
    """

    status: str = "healthy"
    version: str
    environment: str
    checks: dict = Field(
        default_factory=dict,
        description="Dependency health: s3, bedrock, dynamodb.",
    )
