data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_kms_key" "main" {
  description             = "KMS key for PhotoShare"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccountIAMPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowAWSLogDeliveryServices"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudtrail.amazonaws.com",
            "config.amazonaws.com",
            "delivery.logs.amazonaws.com",
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowS3ServiceUse"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "photoshare-kms"
  }

}

resource "aws_kms_alias" "main" {
  name          = "alias/photoshare"
  target_key_id = aws_kms_key.main.key_id
}

#checkov:skip=CKV_AWS_18:Primary photo access is audited through CloudTrail S3 data events.
#checkov:skip=CKV_AWS_144:Cross-region replication is disabled for this single-region portfolio deployment.
resource "aws_s3_bucket" "photos" {
  bucket = var.bucket_name

  tags = {
    Name = "photoshare-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "photos" {

  bucket                  = aws_s3_bucket.photos.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "photos" {
  bucket = aws_s3_bucket.photos.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "photos" {
  bucket = aws_s3_bucket.photos.id
  versioning_configuration {
    status = "Enabled"
  }

}

resource "aws_s3_bucket_server_side_encryption_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_policy" "photos" {
  bucket = aws_s3_bucket.photos.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.photos.arn,
          "${aws_s3_bucket.photos.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyIncorrectEncryptionHeader"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.photos.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid       = "DenyUnencryptedObjectUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.photos.arn}/*"
        Condition = {
          Null = {
            "s3:x-amz-server-side-encryption" = "true"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "photos" {
  bucket      = aws_s3_bucket.photos.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id

  rule {
    id     = "retain-current-and-expire-old-versions"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

#checkov:skip=CKV_AWS_18:Quarantine access is audited through CloudTrail and does not require another logging bucket.
#checkov:skip=CKV_AWS_144:Cross-region replication is disabled for this single-region portfolio deployment.
#checkov:skip=CKV2_AWS_62:Quarantine is a controlled destination bucket, not an application event source.
resource "aws_s3_bucket" "quarantine" {
  bucket = var.quarantine_bucket_name

  tags = {
    Name = "photoshare-quarantine-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket                  = aws_s3_bucket.quarantine.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "expire-quarantined-objects"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.quarantine.arn,
          "${aws_s3_bucket.quarantine.arn}/*"
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

resource "aws_db_subnet_group" "main" {
  name       = "photoshare-db-subnets"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "photoshare-db-subnets"
  }
}

resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "flask_session" {
  length  = 64
  special = false
}

resource "aws_db_instance" "mysql" {
  # These four controls are intentionally disabled for the free-tier demo.
  # Enable them for production: backups, Multi-AZ, enhanced monitoring, and IAM DB auth.
  #checkov:skip=CKV_AWS_133:Free-tier demo uses zero-day automated backup retention; production variable should be set to 7 or more.
  #checkov:skip=CKV_AWS_157:Multi-AZ is disabled for the free-tier demo; production should enable it.
  #checkov:skip=CKV_AWS_118:Enhanced monitoring is disabled for the free-tier demo to avoid additional monitoring charges.
  #checkov:skip=CKV_AWS_161:IAM database authentication is disabled because the application uses Secrets Manager credentials.
  identifier           = "photoshare-db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp3"
  db_name              = var.db_name
  username             = var.db_username
  password             = random_password.db.result
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [
    var.db_security_group_id
  ]
  publicly_accessible     = false
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.main.arn
  backup_retention_period = var.db_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot   = true
  enabled_cloudwatch_logs_exports = [
    "error",
    "general",
    "slowquery"
  ]
  auto_minor_version_upgrade = true
  multi_az                   = var.db_multi_az
  skip_final_snapshot        = false
  final_snapshot_identifier  = "photoshare-db-final-snapshot"
  deletion_protection        = var.db_deletion_protection
  delete_automated_backups   = false
  apply_immediately          = false
}

#checkov:skip=CKV2_AWS_57:Rotation requires a rotation Lambda and coordinated application credential refresh; this portfolio uses Secrets Manager retrieval with controlled deployment rotation.
resource "aws_secretsmanager_secret" "db" {
  name                    = "photoshare-db-password"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0
}

#checkov:skip=CKV2_AWS_57:Automatic rotation would invalidate active sessions; rotation is intentionally controlled through deployment.
resource "aws_secretsmanager_secret" "flask_session" {
  name                    = "photoshare-flask-session-secret"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "flask_session" {
  secret_id     = aws_secretsmanager_secret.flask_session.id
  secret_string = random_password.flask_session.result
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.mysql.address
    dbname   = var.db_name
  })
}
