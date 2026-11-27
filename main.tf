terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Project     = var.org_prefix
      Environment = "governance-prod"
      ManagedBy   = "Terraform"
      Owner       = "Sivagnanam-Kokilan"
    }
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = var.org_prefix
      Environment = "disaster-recovery"
      ManagedBy   = "Terraform"
      Owner       = "Sivagnanam-Kokilan"
    }
  }
}

# 1. Preventive Service Control Policy (SCP) Guardrail for Landing Zone OUs
resource "aws_organizations_policy" "guardrail_deny_unencrypted_s3" {
  name        = "${var.org_prefix}-deny-unencrypted-s3"
  description = "Control Tower guardrail enforcing KMS/AES256 encryption on all S3 uploads"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyIncorrectEncryptionHeader"
        Effect    = "Deny"
        Action    = "s3:PutObject"
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = ["aws:kms", "AES256"]
          }
        }
      }
    ]
  })
}

# 2. Primary & DR KMS Keys for Cross-Region Encrypted Replication
resource "aws_kms_key" "primary_dr_key" {
  description             = "Primary region KMS key for S3 and AWS Backup encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_key" "secondary_dr_key" {
  provider                = aws.dr
  description             = "DR region KMS key for replicated S3 objects and Backup vault"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

# 3. Primary Production Backup Bucket (UAE) with Versioning & KMS Encryption
resource "aws_s3_bucket" "primary_archive" {
  bucket = "${var.org_prefix}-primary-erp-backups"
}

resource "aws_s3_bucket_versioning" "primary_versioning" {
  bucket = aws_s3_bucket.primary_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary_sse" {
  bucket = aws_s3_bucket.primary_archive.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.primary_dr_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# 4. Secondary Disaster Recovery Bucket (Mumbai) with FinOps Glacier Lifecycle
resource "aws_s3_bucket" "dr_replica" {
  provider = aws.dr
  bucket   = "${var.org_prefix}-dr-replica-mumbai"
}

resource "aws_s3_bucket_versioning" "dr_versioning" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "dr_finops_tiering" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_replica.id

  rule {
    id     = "dr-glacier-cost-optimization"
    status = "Enabled"

    transition {
      days          = var.dr_glacier_transition_days
      storage_class = "GLACIER_IR"
    }
  }
}

# 5. IAM Role & Cross-Region Replication (CRR) Rule
resource "aws_iam_role" "s3_replication_role" {
  name = "${var.org_prefix}-s3-crr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "://amazonaws.com"
      }
    }]
  })
}

resource "aws_s3_bucket_replication_configuration" "cross_region_dr" {
  depends_on = [aws_s3_bucket_versioning.primary_versioning, aws_s3_bucket_versioning.dr_versioning]
  role       = aws_iam_role.s3_replication_role.arn
  bucket     = aws_s3_bucket.primary_archive.id

  rule {
    id     = "replicate-erp-backups-to-mumbai"
    status = "Enabled"

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.dr_replica.arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.secondary_dr_key.arn
      }
    }
  }
}

# 6. Immutable AWS Backup Vault for Ransomware & Compliance Protection
resource "aws_backup_vault" "primary_vault" {
  name        = "${var.org_prefix}-primary-vault"
  kms_key_arn = aws_kms_key.primary_dr_key.arn
}
