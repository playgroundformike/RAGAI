"""
Document Processing Service — text extraction from uploaded files.

This is the "R" in RAG (Retrieval-Augmented Generation).
Before we can ask Bedrock a question about a document, we need the
document as plain text. This service handles the conversion.

Why a separate service?
- Text extraction logic will grow (OCR, table extraction, chunking).
- Keeps the router thin — it just orchestrates, doesn't process.
- Easy to unit test with fixture files.
"""

import io
import logging

import pypdf

logger = logging.getLogger(__name__)


class DocumentService:
    """Extracts text content from supported file formats."""

    # Allowed MIME types — validated here as defense-in-depth
    # (router also validates, but never trust a single layer)
    ALLOWED_TYPES = {
        "application/pdf": ".pdf",
        "text/plain": ".txt",
    }

    @staticmethod
    def validate_content_type(content_type: str) -> bool:
        """
        Validate file type against allowlist.
        Defense-in-depth: even if the router checks file extension,
        we also check MIME type here. Belt AND suspenders.
        """
        return content_type in DocumentService.ALLOWED_TYPES

    @staticmethod
    async def extract_text(content: bytes, content_type: str) -> str:
        """
        Extract plain text from document bytes.

        For a production system, you'd add:
        - OCR fallback for scanned PDFs (Textract in AWS)
        - Chunking for large documents (Bedrock has context limits)
        - Language detection
        """
        if content_type == "text/plain":
            return content.decode("utf-8", errors="replace")

        elif content_type == "application/pdf":
            return DocumentService._extract_pdf_text(content)

        else:
            raise ValueError(f"Unsupported content type: {content_type}")

    @staticmethod
    def _extract_pdf_text(content: bytes) -> str:
        """
        Extract text from PDF using pypdf.

        Note: pypdf handles text-based PDFs. Scanned PDFs (images)
        would need OCR — in AWS, that's Amazon Textract. We'd add
        that as a future enhancement.
        """
        try:
            reader = pypdf.PdfReader(io.BytesIO(content))
            text_parts = []

            for page_num, page in enumerate(reader.pages):
                page_text = page.extract_text()
                if page_text:
                    text_parts.append(page_text)
                else:
                    logger.warning(
                        "No text extracted from page %d — may be scanned/image",
                        page_num,
                    )

            full_text = "\n".join(text_parts)

            if not full_text.strip():
                logger.warning("PDF produced no extractable text")
                return "[No extractable text — document may be scanned/image-based]"

            logger.info(
                "PDF text extracted",
                extra={
                    "pages": len(reader.pages),
                    "text_length": len(full_text),
                },
            )
            return full_text

        except Exception as e:
            logger.error("PDF extraction failed: %s", str(e))
            raise ValueError(f"Failed to extract text from PDF: {str(e)}")
