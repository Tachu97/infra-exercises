data "aws_caller_identity" "current" {}

# ── KMS Key for backup encryption ────────────────────────────────────────────
# Using a customer-managed key gives full audit trail via CloudTrail and
# allows key rotation & revocation independent of S3.
resource "aws_kms_key" "backup" {
  description             = "KMS key for ${var.bucket_name} backup encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Allow the cross-account backup uploader to use this key for encryption.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowBackupUploaderToEncrypt"
        Effect = "Allow"
        Principal = {
          AWS = var.backup_uploader_role_arn
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.backup.key_id
}

# ── Access-log bucket ─────────────────────────────────────────────────────────
# Server access logs are stored separately so they don't inflate the main
# bucket's lifecycle counters or cost.
resource "aws_s3_bucket" "logs" {
  bucket        = var.log_bucket_name
  force_destroy = false

  tags = merge(var.tags, { Name = var.log_bucket_name, Purpose = "s3-access-logs" })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

# ── Main backup bucket ────────────────────────────────────────────────────────
resource "aws_s3_bucket" "backup" {
  bucket        = var.bucket_name
  force_destroy = false # Prevent accidental deletion of backups via terraform destroy

  tags = merge(var.tags, { Name = var.bucket_name })
}

# Block all public access — backups must never be publicly readable.
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning: lets us recover from accidental overwrites or partial uploads.
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enforce server-side encryption with the customer-managed KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
    bucket_key_enabled = true # Reduces KMS API call costs significantly
  }
}

# Redirect server access logs to the dedicated log bucket.
resource "aws_s3_bucket_logging" "backup" {
  bucket        = aws_s3_bucket.backup.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/${var.bucket_name}/"
}

# ── Lifecycle Policy ──────────────────────────────────────────────────────────
# Policy goal: keep backups for exactly 180 days, optimising cost along the way.
#
#  Day  0 → 30   STANDARD           (fast retrieval, full price)
#  Day 30 → 90   STANDARD_IA        (~40 % cheaper; min 30-day duration met)
#  Day 90 → 180  GLACIER            (~80 % cheaper; min 90-day duration met)
#  Day 180        Expire             (hard deletion — complies with 180-day policy)
#
# Non-current versions (from versioning) are kept for 7 days then deleted.
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  # Depend on versioning being active before configuring lifecycle rules.
  depends_on = [aws_s3_bucket_versioning.backup]

  rule {
    id     = "backup-retention-180-days"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 180
    }

    # Clean up incomplete multipart uploads to avoid accumulating storage charges.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "purge-noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ── Bucket Policy ─────────────────────────────────────────────────────────────
# 1. Allow the cross-account backup_uploader role to write objects.
# 2. Deny any unencrypted uploads (enforces KMS encryption at upload time).
# 3. Deny all HTTP (non-TLS) access to prevent data interception in transit.
resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id

  # The public-access block must be in place before attaching a policy.
  depends_on = [aws_s3_bucket_public_access_block.backup]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── Allow cross-account backup uploads ──────────────────────────────────
      {
        Sid    = "AllowCrossAccountBackupUpload"
        Effect = "Allow"
        Principal = {
          AWS = var.backup_uploader_role_arn
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
        # Require the uploader to use our KMS key — prevents plain-text uploads.
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption"               = "aws:kms"
            "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.backup.arn
          }
        }
      },
      # ── Deny unencrypted PutObject ──────────────────────────────────────────
      {
        Sid    = "DenyUnencryptedUploads"
        Effect = "Deny"
        Principal = { AWS = "*" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.backup.arn}/*"
        Condition = {
          StringNotEqualsIfExists = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      # ── Deny non-TLS requests ───────────────────────────────────────────────
      {
        Sid    = "DenyNonTLSRequests"
        Effect = "Deny"
        Principal = { AWS = "*" }
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
