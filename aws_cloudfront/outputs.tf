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

output "cloudwatch_metric_alarm_arns" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cloudfront : k => v.arn }
  description = "Map of CloudWatch metric alarm ARNs keyed by cloudwatch_metric_alarms key."
}

output "cloudwatch_metric_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cloudfront : k => v.alarm_name }
  description = "Map of CloudWatch metric alarm names keyed by cloudwatch_metric_alarms key."
}

output "realtime_log_config_arn" {
  value       = try(aws_cloudfront_realtime_log_config.this[0].arn, null)
  description = "CloudFront real-time log configuration ARN when realtime_log_config is set, else null."
}

output "realtime_log_config_name" {
  value       = try(aws_cloudfront_realtime_log_config.this[0].name, null)
  description = "CloudFront real-time log configuration name when realtime_log_config is set, else null."
}

output "realtime_metrics_subscription_enabled" {
  value       = length(aws_cloudfront_monitoring_subscription.this) > 0
  description = "Whether CloudFront real-time metrics subscription is enabled."
}