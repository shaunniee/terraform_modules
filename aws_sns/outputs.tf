# =============================================================================
# Topic
# =============================================================================

output "topic_arn" {
  description = "ARN of the SNS topic."
  value       = aws_sns_topic.this.arn
}

output "topic_id" {
  description = "ID (ARN) of the SNS topic."
  value       = aws_sns_topic.this.id
}

output "topic_name" {
  description = "Name of the SNS topic (includes `.fifo` suffix for FIFO topics)."
  value       = aws_sns_topic.this.name
}

output "topic_owner" {
  description = "AWS account ID of the SNS topic owner."
  value       = aws_sns_topic.this.owner
}

# =============================================================================
# Subscriptions
# =============================================================================

output "subscription_arns" {
  description = "Map of subscription key to subscription ARN."
  value       = { for k, v in aws_sns_topic_subscription.this : k => v.arn }
}

output "subscription_ids" {
  description = "Map of subscription key to subscription ID."
  value       = { for k, v in aws_sns_topic_subscription.this : k => v.id }
}

output "subscription_count" {
  description = "Number of subscriptions created."
  value       = length(aws_sns_topic_subscription.this)
}

# =============================================================================
# Observability
# =============================================================================

output "cloudwatch_alarm_arns" {
  description = "Map of alarm key to CloudWatch alarm ARN."
  value       = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.arn }
}

output "cloudwatch_alarm_names" {
  description = "Map of alarm key to CloudWatch alarm name."
  value       = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.alarm_name }
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard (null if disabled)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (null if disabled)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
}

# =============================================================================
# Delivery Status Logging
# =============================================================================

output "delivery_status_role_arn" {
  description = "ARN of the IAM role used for SNS delivery status logging (null if not created)."
  value       = try(aws_iam_role.delivery_status[0].arn, null)
}

# =============================================================================
# Anomaly Detection Alarms
# =============================================================================

output "cloudwatch_metric_anomaly_alarm_arns" {
  description = "Map of anomaly alarm key to CloudWatch alarm ARN."
  value       = { for k, v in aws_cloudwatch_metric_alarm.anomaly : k => v.arn }
}

output "cloudwatch_metric_anomaly_alarm_names" {
  description = "Map of anomaly alarm key to CloudWatch alarm name."
  value       = { for k, v in aws_cloudwatch_metric_alarm.anomaly : k => v.alarm_name }
}

# =============================================================================
# Summary
# =============================================================================

output "observability_summary" {
  description = "Summary of observability resources created."
  value = {
    enabled              = local.observability_enabled
    alarm_count          = length(aws_cloudwatch_metric_alarm.this)
    alarm_keys           = keys(aws_cloudwatch_metric_alarm.this)
    anomaly_alarm_count  = length(aws_cloudwatch_metric_alarm.anomaly)
    anomaly_alarm_keys   = keys(aws_cloudwatch_metric_alarm.anomaly)
    dashboard_name       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
    delivery_status_logging = local.delivery_status_logging_enabled
  }
}