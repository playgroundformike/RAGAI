"""
Unit Tests — SecureGenAI Document Assistant

These tests run in Jenkins Stage 2 (Lint & Unit Test).
They validate the application logic WITHOUT needing AWS credentials.
Services that call AWS (S3, Bedrock) are mocked.

Test philosophy for CI/CD:
- Fast: all tests complete in < 30 seconds
- Isolated: no network calls, no real AWS, no file system side effects
- Deterministic: same result every run (no randomness, no time dependence)
"""

import pytest
from app.config import Settings
from app.models import QueryRequest, UploadResponse
from app.services.document import DocumentService
from pydantic import ValidationError
from datetime import datetime, timezone


# ── Config Tests ─────────────────────────────────────────────

class TestConfig:
    """Verify configuration loading and defaults."""

    def test_default_settings(self):
        """Settings should load with sensible defaults."""
        settings = Settings()
        assert settings.app_name == "SecureGenAI Document Assistant"
        assert settings.environment == "development"
        assert settings.aws_region == "us-east-1"
        assert settings.bedrock_temperature == 0.1

    def test_max_upload_size_default(self):
        """Default upload limit should be 10MB."""
        settings = Settings()
        assert settings.max_upload_size_mb == 10

    def test_allowed_file_types(self):
        """Only PDF and TXT should be allowed."""
        settings = Settings()
        assert ".pdf" in settings.allowed_file_types
        assert ".txt" in settings.allowed_file_types
        assert ".exe" not in settings.allowed_file_types

    def test_kms_key_is_alias(self):
        """KMS key should reference an alias, not a raw key ID."""
        settings = Settings()
        assert settings.kms_key_id.startswith("alias/")


# ── Model Validation Tests ───────────────────────────────────

class TestModels:
    """Verify Pydantic models reject bad input."""

    def test_query_request_rejects_empty_question(self):
        """Empty questions should be rejected (min_length=1)."""
        with pytest.raises(ValidationError):
            QueryRequest(document_id="abc-123", question="")

    def test_query_request_rejects_empty_document_id(self):
        """Empty document IDs should be rejected."""
        with pytest.raises(ValidationError):
            QueryRequest(document_id="", question="What is this about?")

    def test_query_request_rejects_long_question(self):
        """Questions over 2000 chars should be rejected."""
        with pytest.raises(ValidationError):
            QueryRequest(
                document_id="abc-123",
                question="x" * 2001,
            )

    def test_query_request_accepts_valid_input(self):
        """Valid input should create a model instance."""
        req = QueryRequest(
            document_id="abc-123",
            question="What is the main topic?",
        )
        assert req.document_id == "abc-123"
        assert req.question == "What is the main topic?"

    def test_upload_response_serialization(self):
        """UploadResponse should serialize to JSON correctly."""
        resp = UploadResponse(
            document_id="test-id",
            filename="test.pdf",
            s3_key="uploads/test-id/test.pdf",
            content_type="application/pdf",
            size_bytes=1024,
            uploaded_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
        )
        data = resp.model_dump()
        assert data["document_id"] == "test-id"
        assert data["message"] == "Document uploaded successfully."


# ── Document Service Tests ───────────────────────────────────

class TestDocumentService:
    """Verify document processing logic."""

    def test_validate_pdf_content_type(self):
        """PDF MIME type should be accepted."""
        assert DocumentService.validate_content_type("application/pdf") is True

    def test_validate_text_content_type(self):
        """Plain text MIME type should be accepted."""
        assert DocumentService.validate_content_type("text/plain") is True

    def test_reject_executable_content_type(self):
        """Executable MIME types should be rejected."""
        assert DocumentService.validate_content_type("application/x-executable") is False

    def test_reject_html_content_type(self):
        """HTML should be rejected (not in allowlist)."""
        assert DocumentService.validate_content_type("text/html") is False

    @pytest.mark.asyncio
    async def test_extract_text_from_plain_text(self):
        """Plain text extraction should return the decoded string."""
        content = b"Hello, this is a test document."
        result = await DocumentService.extract_text(content, "text/plain")
        assert result == "Hello, this is a test document."

    @pytest.mark.asyncio
    async def test_extract_text_handles_utf8(self):
        """UTF-8 characters should be handled correctly."""
        content = "Héllo wörld — testing spëcial chars".encode("utf-8")
        result = await DocumentService.extract_text(content, "text/plain")
        assert "Héllo" in result

    @pytest.mark.asyncio
    async def test_extract_text_rejects_unsupported_type(self):
        """Unsupported content types should raise ValueError."""
        with pytest.raises(ValueError, match="Unsupported content type"):
            await DocumentService.extract_text(b"data", "application/zip")
