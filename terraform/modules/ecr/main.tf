# ============================================================
# ECR Module — Container Image Registry
# ============================================================
#
# Creates a private ECR repository for the application container image.
# Jenkins pushes images here; EKS pulls images from here.
#
# Security features:
#   - Image scanning on push (Trivy equivalent built into ECR)
#   - Immutable tags prevent overwriting existing image versions
#   - KMS encryption for images at rest
#   - Lifecycle policy prevents unbounded image storage
#
# NIST 800-53 Controls:
#   SI-7  (Software Integrity) — image scanning, immutable tags
#   SC-28 (Protection at Rest) — KMS encryption
#   CM-7  (Least Functionality) — lifecycle cleans old images
# ============================================================

resource "aws_ecr_repository" "app" {
  name = var.repository_name

  # SI-7: Immutable tags mean once you push v1.0.0, no one can
  # overwrite it with different code. This ensures the image
  # running in production is exactly what was scanned and approved.
  image_tag_mutability = "IMMUTABLE"

  # Built-in vulnerability scanning on every push.
  # This catches known CVEs before images reach EKS.
  # In our Jenkins pipeline, Trivy does deeper scanning,
  # but this provides defense-in-depth.
  image_scanning_configuration {
    scan_on_push = true
  }

  # SC-28: Encrypt stored images with KMS
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = var.tags
}

# ── Lifecycle Policy ─────────────────────────────────────────
# Keep the last 30 tagged images, expire untagged images after 7 days.
# Without this, every Jenkins build pushes a new image and storage
# grows unbounded. At ~200MB per image, 1000 builds = 200GB.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v"]
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
