output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.this.domain_name
  description = "CloudFront distribution domain name"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.this.id
  description = "CloudFront distribution ID"
}

output "cloudfront_distribution_arn" {
  value       = aws_cloudfront_distribution.this.arn
  description = "CloudFront distribution ARN"
}

output "cloudfront_key_group_id" {
  value       = var.kms_key_arn != null ? aws_cloudfront_key_group.signed_urls[0].id : null
  description = "Key group ID for signed URLs"
}