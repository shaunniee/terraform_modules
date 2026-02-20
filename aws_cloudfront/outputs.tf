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

output "cloudfront_hosted_zone_id" {
  value       = aws_cloudfront_distribution.this.hosted_zone_id
  description = "Route53 hosted zone ID for the CloudFront distribution (use for alias records)."
}

output "cloudfront_etag" {
  value       = aws_cloudfront_distribution.this.etag
  description = "Current version identifier (ETag) of the distribution. Needed for invalidations and imports."
}

output "cloudfront_status" {
  value       = aws_cloudfront_distribution.this.status
  description = "Deployment status of the distribution (e.g., Deployed, InProgress)."
}

output "cloudfront_key_group_id" {
  value       = var.kms_key_arn != null ? aws_cloudfront_key_group.signed_urls[0].id : null
  description = "Key group ID for signed URLs"
}

output "cloudwatch_metric_alarm_arns" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cloudfront : k => v.arn }
  description = "Map of CloudWatch metric alarm ARNs keyed by alarm key."
}

output "cloudwatch_metric_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cloudfront : k => v.alarm_name }
  description = "Map of CloudWatch metric alarm names keyed by alarm key."
}

output "dashboard_arn" {
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
  description = "ARN of the CloudWatch dashboard (null if disabled)."
}

output "dashboard_name" {
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
  description = "Name of the CloudWatch dashboard (null if disabled)."
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

output "observability_summary" {
  description = "Summary of observability resources created."
  value = {
    enabled              = local.observability_enabled
    alarm_count          = length(aws_cloudwatch_metric_alarm.cloudfront)
    anomaly_alarm_count  = length(aws_cloudwatch_metric_alarm.cloudfront_anomaly)
    alarm_keys           = keys(aws_cloudwatch_metric_alarm.cloudfront)
    anomaly_alarm_keys   = keys(aws_cloudwatch_metric_alarm.cloudfront_anomaly)
    dashboard_name       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
  }
}

output "cloudwatch_metric_anomaly_alarm_arns" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cloudfront_anomaly : k => v.arn }
  description = "Map of CloudWatch anomaly alarm ARNs keyed by alarm key."
}

output "cloudwatch_metric_anomaly_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cloudfront_anomaly : k => v.alarm_name }
  description = "Map of CloudWatch anomaly alarm names keyed by alarm key."
}