# =============================================================================
# IAM
# =============================================================================

output "role_name" {
  description = "The IAM role name created by this module. Null when execution_role_arn is provided."
  value       = local.role_name
}

output "role_arn" {
  description = "The IAM role ARN used by the state machine."
  value       = local.role_arn
}

output "role_id" {
  description = "The IAM role ID created by this module. Useful for attaching additional policies externally. Null when execution_role_arn is provided."
  value       = local.create_role ? aws_iam_role.sfn_role[0].id : null
}

# =============================================================================
# State Machine
# =============================================================================

output "state_machine_id" {
  description = "The ID of the state machine."
  value       = aws_sfn_state_machine.this.id
}

output "state_machine_arn" {
  description = "The ARN of the state machine."
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "The name of the state machine."
  value       = aws_sfn_state_machine.this.name
}

output "state_machine_creation_date" {
  description = "The creation date of the state machine."
  value       = aws_sfn_state_machine.this.creation_date
}

output "state_machine_status" {
  description = "The current status of the state machine."
  value       = aws_sfn_state_machine.this.status
}

output "state_machine_version_arn" {
  description = "The ARN of the state machine version (when publish = true)."
  value       = try(aws_sfn_state_machine.this.state_machine_version_arn, null)
}

output "state_machine_revision_id" {
  description = "The revision ID of the state machine."
  value       = try(aws_sfn_state_machine.this.revision_id, null)
}

# =============================================================================
# Aliases
# =============================================================================

output "alias_arns" {
  description = "Map of Step Functions alias ARNs keyed by alias name."
  value       = { for k, v in aws_sfn_alias.this : k => v.arn }
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name when create_cloudwatch_log_group is true and logging is enabled, else null."
  value       = local.create_log_group ? aws_cloudwatch_log_group.sfn[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN when create_cloudwatch_log_group is true and logging is enabled, else null."
  value       = local.create_log_group ? aws_cloudwatch_log_group.sfn[0].arn : null
}

# =============================================================================
# CloudWatch Metric Alarms
# =============================================================================

output "cloudwatch_metric_alarm_arns" {
  description = "Map of CloudWatch metric alarm ARNs keyed by metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.sfn : k => v.arn }
}

output "cloudwatch_metric_alarm_names" {
  description = "Map of CloudWatch metric alarm names keyed by metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.sfn : k => v.alarm_name }
}

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

output "cloudwatch_metric_anomaly_alarm_arns" {
  description = "Map of CloudWatch anomaly alarm ARNs keyed by metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.sfn_anomaly : k => v.arn }
}

output "cloudwatch_metric_anomaly_alarm_names" {
  description = "Map of CloudWatch anomaly alarm names keyed by metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.sfn_anomaly : k => v.alarm_name }
}

# =============================================================================
# Log Metric Filters
# =============================================================================

output "log_metric_filter_names" {
  description = "Map of log metric filter names keyed by log_metric_filters key."
  value       = { for k, v in aws_cloudwatch_log_metric_filter.this : k => v.name }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

output "dashboard_name" {
  description = "CloudWatch dashboard name (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
}

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
}
