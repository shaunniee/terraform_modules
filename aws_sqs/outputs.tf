# =============================================================================
# Main Queue
# =============================================================================

output "queue_name" {
  description = "Name of the main SQS queue."
  value       = aws_sqs_queue.this.name
}

output "queue_arn" {
  description = "ARN of the main SQS queue."
  value       = aws_sqs_queue.this.arn
}

output "queue_url" {
  description = "URL of the main SQS queue."
  value       = aws_sqs_queue.this.url
}

output "queue_id" {
  description = "SQS queue ID (same as URL)."
  value       = aws_sqs_queue.this.id
}

# =============================================================================
# Dead-Letter Queue
# =============================================================================

output "dlq_name" {
  description = "Name of the managed DLQ (null if no managed DLQ)."
  value       = var.create_dlq ? aws_sqs_queue.dlq[0].name : null
}

output "dlq_arn" {
  description = "ARN of the DLQ — managed or external (null if no DLQ configured)."
  value       = local.dlq_arn
}

output "dlq_url" {
  description = "URL of the DLQ — managed or external (null if no DLQ configured)."
  value       = local.dlq_url
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs for the main queue, keyed by alarm name."
  value       = { for k, v in aws_cloudwatch_metric_alarm.main : k => v.arn }
}

output "alarm_names" {
  description = "Map of CloudWatch alarm names for the main queue, keyed by alarm key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.main : k => v.alarm_name }
}

output "dlq_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs for the DLQ, keyed by alarm name."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dlq : k => v.arn }
}

output "dlq_alarm_names" {
  description = "Map of CloudWatch alarm names for the DLQ, keyed by alarm key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dlq : k => v.alarm_name }
}

# =============================================================================
# Dashboard
# =============================================================================

output "dashboard_name" {
  description = "CloudWatch dashboard name (null if not created)."
  value       = local.dashboard_enabled ? aws_cloudwatch_dashboard.this[0].dashboard_name : null
}

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN (null if not created)."
  value       = local.dashboard_enabled ? aws_cloudwatch_dashboard.this[0].dashboard_arn : null
}

# =============================================================================
# Anomaly Detection Alarms
# =============================================================================

output "anomaly_alarm_arns" {
  description = "Map of anomaly alarm key to CloudWatch alarm ARN."
  value       = { for k, v in aws_cloudwatch_metric_alarm.anomaly : k => v.arn }
}

output "anomaly_alarm_names" {
  description = "Map of anomaly alarm key to CloudWatch alarm name."
  value       = { for k, v in aws_cloudwatch_metric_alarm.anomaly : k => v.alarm_name }
}

# =============================================================================
# Observability Summary
# =============================================================================

output "observability" {
  description = "Summary of observability configuration."
  value = {
    enabled              = local.observability_enabled
    total_alarms_created = length(aws_cloudwatch_metric_alarm.main) + length(aws_cloudwatch_metric_alarm.dlq)
    anomaly_alarm_count  = length(aws_cloudwatch_metric_alarm.anomaly)
    anomaly_alarm_keys   = keys(aws_cloudwatch_metric_alarm.anomaly)
    dashboard_enabled    = local.dashboard_enabled
    dlq_alarm_enabled    = local.dlq_alarm_enabled
  }
}