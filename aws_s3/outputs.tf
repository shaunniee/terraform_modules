# Bucket Outputs

output "bucket_id" {
  description = "The name of the S3 bucket"
  value       = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.unprotected[0].id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = var.prevent_destroy ? aws_s3_bucket.protected[0].arn : aws_s3_bucket.unprotected[0].arn
}

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = var.prevent_destroy ? aws_s3_bucket.protected[0].bucket_domain_name : aws_s3_bucket.unprotected[0].bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = var.prevent_destroy ? aws_s3_bucket.protected[0].bucket_regional_domain_name : aws_s3_bucket.unprotected[0].bucket_regional_domain_name
}

output "bucket_region" {
  description = "The AWS region where the bucket was created"
  value       = var.prevent_destroy ? aws_s3_bucket.protected[0].region : aws_s3_bucket.unprotected[0].region
}

# Versioning Output

output "versioning_enabled" {
  description = "Whether versioning is enabled for the bucket"
  value       = var.versioning.enabled
}

# Encryption Output

output "encryption_enabled" {
  description = "Whether server-side encryption is enabled"
  value       = var.server_side_encryption.enabled
}

output "encryption_algorithm" {
  description = "The server-side encryption algorithm used"
  value       = var.server_side_encryption.enabled ? var.server_side_encryption.encryption_algorithm : null
}

# Public Access Block Output

output "is_private_bucket" {
  description = "Whether the bucket has public access blocked"
  value       = var.private_bucket
}

# Logging Outputs

output "logging_enabled" {
  description = "Whether logging is enabled for the bucket"
  value       = var.logging.enabled
}

output "logging_bucket_id" {
  description = "The ID of the logging bucket (if managed bucket is enabled)"
  value       = var.logging.enabled && var.logging.managed_bucket ? aws_s3_bucket.this[0].id : null
}

output "logging_bucket_arn" {
  description = "The ARN of the logging bucket (if managed bucket is enabled)"
  value       = var.logging.enabled && var.logging.managed_bucket ? aws_s3_bucket.this[0].arn : null
}

output "logging_target_bucket" {
  description = "The target bucket for logging"
  value       = var.logging.enabled ? (var.logging.target_bucket != "" ? var.logging.target_bucket : (var.logging.managed_bucket ? aws_s3_bucket.this[0].id : "")) : null
}

# Replication Outputs

output "replication_enabled" {
  description = "Whether replication is enabled for the bucket"
  value       = var.replication != null
}

output "replication_role_arn" {
  description = "The ARN of the IAM role used for replication"
  value       = var.replication != null ? (var.replication.role_arn != "" ? var.replication.role_arn : aws_iam_role.replication[0].arn) : null
}

output "replication_role_name" {
  description = "The name of the IAM role created for replication (if auto-created)"
  value       = var.replication != null && var.replication.role_arn == "" ? aws_iam_role.replication[0].name : null
}

output "replication_rules" {
  description = "List of replication rule IDs configured"
  value       = var.replication != null ? [for rule in var.replication.rules : rule.id] : []
}

# Lifecycle Configuration Output

output "lifecycle_rules_count" {
  description = "Number of lifecycle rules configured"
  value       = length(var.lifecycle_rules)
}

# CORS Configuration Output

output "cors_rules_count" {
  description = "Number of CORS rules configured"
  value       = length(var.cors_rules)
}
