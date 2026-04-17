"""
Upload Router — document ingestion endpoint.

This router handles the "write" path: user uploads a file,
we validate it, store it in S3 with encryption, and return a document ID.

DoD/Compliance Rationale:
- File type validation at both extension AND content-type level
- File size enforcement to prevent resource exhaustion (DoS)
- UUID-based document IDs prevent enumeration
- All responses use Pydantic models — no raw dicts that might leak fields

Security layers (defense in depth):
  1. FastAPI validates request shape (Pydantic)
  2. Router validates file extension + size
  3. Service validates MIME type
  4. S3 encrypts with KMS on write
  5. Bucket policy enforces TLS-only access
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, status

from app.config import Settings, get_settings
from app.models import UploadResponse
from app.services.s3 import S3Service
from app.services.document import DocumentService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["documents"])


def get_s3_service(settings: Settings = Depends(get_settings)) -> S3Service:
    """
    Dependency injection for S3Service.
    FastAPI's Depends() system means:
    - Services are created per-request (no shared mutable state)
    - Easy to swap with mocks in tests
    - Config flows down automatically from get_settings
    """
    return S3Service(settings)


@router.post(
    "/upload",
    response_model=UploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a document for analysis",
    description="Upload a PDF or text file. The document is encrypted with KMS "
    "and stored in S3. Returns a document_id for subsequent queries.",
)
async def upload_document(
    file: UploadFile = File(
        ...,
        description="PDF or text file to upload.",
    ),
    settings: Settings = Depends(get_settings),
    s3_service: S3Service = Depends(get_s3_service),
):
    """
    Document upload endpoint.

    Flow:
    1. Validate file extension against allowlist
    2. Validate file size against max limit
    3. Validate content type
    4. Read file content
    5. Upload to S3 with KMS encryption
    6. Return document metadata

    In production, you'd also:
    - Authenticate the request (JWT/OAuth)
    - Write metadata to DynamoDB
    - Trigger an async processing pipeline (Step Functions)
    - Scan the file for malware (ClamAV or similar)
    """
    # ── Step 1: Validate file extension ───────────────────────────
    # Check against allowlist, not blocklist. Allowlists are safer because
    # you only permit known-good values instead of trying to anticipate
    # every possible bad value.
    file_extension = _get_file_extension(file.filename)
    if file_extension not in settings.allowed_file_types:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"File type '{file_extension}' not allowed. "
            f"Supported: {settings.allowed_file_types}",
        )

    # ── Step 2: Read and validate size ────────────────────────────
    content = await file.read()
    max_bytes = settings.max_upload_size_mb * 1024 * 1024

    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File exceeds {settings.max_upload_size_mb}MB limit.",
        )

    if len(content) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty file uploaded.",
        )

    # ── Step 3: Validate content type ─────────────────────────────
    content_type = file.content_type or "application/octet-stream"
    if not DocumentService.validate_content_type(content_type):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Content type '{content_type}' not supported.",
        )

    # ── Step 4: Upload to S3 ──────────────────────────────────────
    document_id = s3_service.generate_document_id()

    try:
        result = await s3_service.upload_document(
            document_id=document_id,
            filename=file.filename,
            content=content,
            content_type=content_type,
        )
    except Exception as e:
        logger.error("Upload failed for document %s: %s", document_id, str(e))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            # Generic error message — never expose internal error details
            # to the client. Details go to the logs (Splunk/CloudWatch).
            detail="Failed to store document. Please try again.",
        )

    # ── Step 5: Return response ───────────────────────────────────
    return UploadResponse(
        document_id=document_id,
        filename=file.filename,
        s3_key=result["s3_key"],
        content_type=content_type,
        size_bytes=result["size_bytes"],
        uploaded_at=datetime.now(timezone.utc),
    )


def _get_file_extension(filename: str | None) -> str:
    """Extract lowercase file extension from filename."""
    if not filename or "." not in filename:
        return ""
    return "." + filename.rsplit(".", 1)[-1].lower()
