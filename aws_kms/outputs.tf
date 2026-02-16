output "kms_key_ids" {
  description = "KMS Key IDs"
  value       = { for k, v in aws_kms_key.this : k => v.id }
}

output "kms_key_arns" {
  description = "KMS Key ARNs"
  value       = { for k, v in aws_kms_key.this : k => v.arn }
}