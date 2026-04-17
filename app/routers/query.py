"""
Query Router — document Q&A endpoint.

This router handles the "read" path: user asks a question about
a previously uploaded document. We retrieve it from S3, extract
the text, and send it to Bedrock with the question.

This is the complete RAG flow:
  Retrieve (S3) → Augment (stuff into prompt) → Generate (Bedrock)

DoD/Compliance Rationale:
- Document content never leaves AWS boundary (Bedrock is in-account)
- We log the query metadata (not content) for audit trail
- Pydantic validates all input before processing
- Error responses are generic — no internal state leakage
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.config import Settings, get_settings
from app.models import QueryRequest, QueryResponse
from app.services.s3 import S3Service
from app.services.bedrock import BedrockService
from app.services.document import DocumentService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["queries"])


def get_s3_service(settings: Settings = Depends(get_settings)) -> S3Service:
    return S3Service(settings)


def get_bedrock_service(settings: Settings = Depends(get_settings)) -> BedrockService:
    return BedrockService(settings)


@router.post(
    "/query",
    response_model=QueryResponse,
    summary="Ask a question about an uploaded document",
    description="Submit a question and document ID. The system retrieves the "
    "document from S3, extracts text, and uses Bedrock (Claude) to "
    "generate an answer grounded in the document content.",
)
async def query_document(
    request: QueryRequest,
    settings: Settings = Depends(get_settings),
    s3_service: S3Service = Depends(get_s3_service),
    bedrock_service: BedrockService = Depends(get_bedrock_service),
):
    """
    Document Q&A endpoint — the core RAG flow.

    Flow:
    1. Find the document in S3 by document_id
    2. Download the document
    3. Extract text from the document
    4. Send text + question to Bedrock
    5. Return the model's answer

    In production, you'd also:
    - Authenticate and authorize (does this user own this document?)
    - Cache extracted text (don't re-extract on every query)
    - Use vector search for large documents (not full-text stuffing)
    - Rate limit per user to control Bedrock costs
    """
    # ── Step 1: Find document in S3 ───────────────────────────────
    try:
        s3_keys = await s3_service.list_document_keys(request.document_id)
    except Exception as e:
        logger.error("Failed to list keys for %s: %s", request.document_id, str(e))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to locate document. Please try again.",
        )

    if not s3_keys:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Document '{request.document_id}' not found.",
        )

    # Use the first key (one document = one file)
    s3_key = s3_keys[0]
    # Extract filename from key: uploads/{id}/{filename} → filename
    filename = s3_key.split("/")[-1]

    # ── Step 2: Download document ─────────────────────────────────
    try:
        content = await s3_service.download_document(
            request.document_id, filename
        )
    except Exception as e:
        logger.error("Failed to download %s: %s", request.document_id, str(e))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to retrieve document. Please try again.",
        )

    if content is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Document '{request.document_id}' not found in storage.",
        )

    # ── Step 3: Extract text ──────────────────────────────────────
    # Determine content type from file extension
    content_type = "application/pdf" if filename.endswith(".pdf") else "text/plain"

    try:
        document_text = await DocumentService.extract_text(content, content_type)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Could not extract text from document: {str(e)}",
        )

    if not document_text.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Document contains no extractable text.",
        )

    # ── Step 4: Query Bedrock ─────────────────────────────────────
    try:
        result = await bedrock_service.query_document(
            document_text=document_text,
            question=request.question,
        )
    except Exception as e:
        logger.error("Bedrock query failed for %s: %s", request.document_id, str(e))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="AI model query failed. Please try again.",
        )

    # ── Step 5: Return response ───────────────────────────────────
    return QueryResponse(
        document_id=request.document_id,
        question=request.question,
        answer=result["answer"],
        model_id=result["model_id"],
        usage=result["usage"],
    )
