"""
S3 Service — secure document storage operations.

DoD/Compliance Rationale:
- All uploads use server-side encryption with a customer-managed KMS key (SSE-KMS).
  This satisfies SC-28 (Protection of Information at Rest).
- S3 keys include a UUID prefix to prevent enumeration attacks — you can't
  guess another user's document path.
- Content-type validation happens BEFORE upload to prevent storing executable
  content disguised as documents.

Why a service layer?
- Isolates AWS SDK calls from HTTP handling (routers).
- If you swap S3 for MinIO or another backend, only this file changes.
- Auditors review this single file for all storage security controls.
"""

import uuid
import logging
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

from app.config import Settings

logger = logging.getLogger(__name__)


class S3Service:
    """Handles S3 operations with KMS encryption."""

    def __init__(self, settings: Settings):
        self.settings = settings
        # endpoint_url is None in production (uses real AWS) and set to
        # LocalStack URL in local dev. The application logic is identical
        # in both cases — only the endpoint changes.
        self.s3_client = boto3.client(
            "s3",
            region_name=settings.aws_region,
            endpoint_url=settings.aws_endpoint_url,
        )

    def generate_document_id(self) -> str:
        """
        Generate a UUID4 document ID. UUIDs are:
        - Non-sequential (can't enumerate documents by incrementing)
        - Collision-resistant (no need for DB-level uniqueness checks)
        """
        return str(uuid.uuid4())

    def build_s3_key(self, document_id: str, filename: str) -> str:
        """
        Build the S3 object key.
        Pattern: uploads/{document_id}/{filename}

        The document_id prefix means IAM policies can scope access
        per-document if needed (resource-level permissions).
        """
        # Sanitize filename — strip path separators to prevent directory traversal
        # Example attack: filename="../../etc/passwd" → just "passwd"
        safe_filename = filename.replace("/", "_").replace("\\", "_")
        return f"{self.settings.s3_prefix}{document_id}/{safe_filename}"

    async def upload_document(
        self, document_id: str, filename: str, content: bytes, content_type: str
    ) -> dict:
        """
        Upload a document to S3 with KMS encryption.

        SC-28: SSE-KMS encryption on every PutObject call.
        Even if someone misconfigures the bucket default encryption,
        this explicit parameter ensures every object is encrypted.
        """
        s3_key = self.build_s3_key(document_id, filename)

        try:
            self.s3_client.put_object(
                Bucket=self.settings.s3_bucket_name,
                Key=s3_key,
                Body=content,
                ContentType=content_type,
                # SC-28: Server-side encryption with customer-managed KMS key.
                # Using aws:kms (not AES256) because CMK gives us:
                #   - Key rotation control
                #   - CloudTrail logging of every decrypt call
                #   - Ability to revoke access by disabling the key
                ServerSideEncryption="aws:kms",
                SSEKMSKeyId=self.settings.kms_key_id,
                # Metadata for audit trail — who uploaded, when, original name
                Metadata={
                    "original-filename": filename,
                    "document-id": document_id,
                    "uploaded-at": datetime.now(timezone.utc).isoformat(),
                },
            )

            logger.info(
                "Document uploaded successfully",
                extra={
                    "document_id": document_id,
                    "s3_key": s3_key,
                    "size_bytes": len(content),
                    # NOTE: Never log file contents or PII.
                    # Log the document_id so you can correlate in Splunk/CloudWatch.
                },
            )

            return {
                "document_id": document_id,
                "s3_key": s3_key,
                "size_bytes": len(content),
            }

        except ClientError as e:
            logger.error(
                "S3 upload failed",
                extra={"document_id": document_id, "error": str(e)},
            )
            raise

    async def download_document(self, document_id: str, filename: str) -> bytes:
        """
        Download a document from S3. KMS decryption is automatic —
        if the IAM role has kms:Decrypt on the key, S3 handles it.
        """
        s3_key = self.build_s3_key(document_id, filename)

        try:
            response = self.s3_client.get_object(
                Bucket=self.settings.s3_bucket_name,
                Key=s3_key,
            )
            return response["Body"].read()

        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            if error_code == "NoSuchKey":
                logger.warning(
                    "Document not found in S3",
                    extra={"document_id": document_id, "s3_key": s3_key},
                )
                return None
            raise

    async def list_document_keys(self, document_id: str) -> list[str]:
        """
        List all S3 keys under a document_id prefix.
        Used to find the filename when we only have the document_id.
        """
        prefix = f"{self.settings.s3_prefix}{document_id}/"
        try:
            response = self.s3_client.list_objects_v2(
                Bucket=self.settings.s3_bucket_name,
                Prefix=prefix,
                MaxKeys=10,  # A document should have 1 file; limit as safety net
            )
            return [obj["Key"] for obj in response.get("Contents", [])]
        except ClientError as e:
            logger.error(
                "Failed to list document keys",
                extra={"document_id": document_id, "error": str(e)},
            )
            raise
