# Define bucket 
// Create with prevent destroy 

resource "aws_s3_bucket" "protected" {
  count         = var.prevent_destroy ? 1 : 0
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  lifecycle {
    prevent_destroy = true
  }
}

// Create without prevent destroy

resource "aws_s3_bucket" "unprotected" {
  count         = var.prevent_destroy ? 0 : 1
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  lifecycle {
    prevent_destroy = false
  }
}

# Define private access

resource "aws_s3_bucket_public_access_block" "this" {
  count                   = var.private_bucket ? 1 : 0
  bucket                  = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id
  block_public_acls       = var.private_bucket
  block_public_policy     = var.private_bucket
  ignore_public_acls      = var.private_bucket
  restrict_public_buckets = var.private_bucket
}

# Define versioning

resource "aws_s3_bucket_versioning" "this" {
  bucket = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id
  versioning_configuration {
    status = var.versioning.enabled ? "Enabled" : "Suspended"
  }
}

# Define encryption

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = var.server_side_encryption.enabled ? 1 : 0
  bucket = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.server_side_encryption.encryption_algorithm
      kms_master_key_id = var.server_side_encryption.kms_master_key_id
    }
  }
}

# Define Lifecycle configuration

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = lookup(rule.value, "status", "Enabled")

      dynamic "filter" {
        for_each = rule.value.filter != null ? [rule.value.filter] : []
        content {
          prefix = try(filter.value.prefix, null)

          dynamic "tag" {
            for_each = filter.value.tag != null ? [filter.value.tag] : []
            content {
              key   = tag.value.key
              value = tag.value.value
            }
          }
        }
      }

      # Transition block
      dynamic "transition" {
        for_each = lookup(rule.value, "transition", [])
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = lookup(rule.value, "noncurrent_version_transition", [])
        content {
          noncurrent_days = noncurrent_version_transition.value.noncurrent_days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      # Expiration block
      dynamic "expiration" {
        for_each = rule.value.expiration != null ? [rule.value.expiration] : []
        content {
          days                         = lookup(expiration.value, "days", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker", null)
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lookup(rule.value, "noncurrent_version_expiration", [])
        content {
          noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
        }
      }
    }
  }
}

# Define Logging

resource "aws_s3_bucket" "this" {
  count  = var.logging.enabled && var.logging.managed_bucket ? 1 : 0
  bucket = "${var.bucket_name}-logs"

}

resource "aws_s3_bucket_logging" "this" {
  count         = var.logging.enabled ? 1 : 0
  bucket        = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id
  target_bucket = var.logging.target_bucket != "" ? var.logging.target_bucket : (var.logging.managed_bucket ? aws_s3_bucket.this[0].id : "")
  target_prefix = var.logging.target_prefix ? var.logging.target_prefix : (var.logging.managed_bucket ? "logs/" : "")
}

# Define Replica

# IAM Role for S3 Replication
resource "aws_iam_role" "replication" {
  count = var.replication != null && var.replication.role_arn == "" ? 1 : 0
  name  = "${var.bucket_name}-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for S3 Replication
resource "aws_iam_role_policy" "replication" {
  count = var.replication != null && var.replication.role_arn == "" ? 1 : 0
  name  = "${var.bucket_name}-replication-policy"
  role  = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          var.prevent_destroy ? aws_s3_bucket.protected[0].arn : aws_s3_bucket.unprotected[0].arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${var.prevent_destroy ? aws_s3_bucket.protected[0].arn : aws_s3_bucket.unprotected[0].arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          for rule in var.replication.rules : "${rule.destination_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count  = var.replication != null ? 1 : 0
  bucket = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id
  role   = var.replication.role_arn != "" ? var.replication.role_arn : aws_iam_role.replication[0].arn

  dynamic "rule" {
    for_each = var.replication.rules
    content {
      id     = rule.value.id
      status = rule.value.status

      dynamic "filter" {
        for_each = rule.value.prefix != "" ? [1] : []
        content {
          prefix = rule.value.prefix
        }
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.storage_class
      }
    }
  }

  depends_on = [aws_iam_role_policy.replication]
}

# Define CORS

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", [])
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", 3000)
    }
  }
}


