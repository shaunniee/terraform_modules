# =============================================================================
# CodePipeline Outputs
# =============================================================================

output "codepipeline_arn" {
  description = "The ARN of the CodePipeline."
  value       = aws_codepipeline.this.arn
}

output "codepipeline_id" {
  description = "The ID of the CodePipeline."
  value       = aws_codepipeline.this.id
}

output "codepipeline_name" {
  description = "The name of the CodePipeline."
  value       = aws_codepipeline.this.name
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "codepipeline_role_arn" {
  description = "The ARN of the IAM role used by CodePipeline."
  value       = local.service_role_arn
}

output "codepipeline_role_name" {
  description = "The name of the auto-created IAM role (null if external role was provided)."
  value       = try(aws_iam_role.this[0].name, null)
}

# =============================================================================
# Observability Outputs
# =============================================================================

output "cloudwatch_alarm_arns" {
  description = "Map of alarm key to CloudWatch alarm ARN."
  value       = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.arn }
}

output "cloudwatch_alarm_names" {
  description = "Map of alarm key to CloudWatch alarm name."
  value       = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.alarm_name }
}

output "cloudwatch_dashboard_arn" {
  description = "The ARN of the CloudWatch dashboard (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
}

output "event_rule_arn" {
  description = "The ARN of the EventBridge rule for pipeline notifications (null if not created)."
  value       = try(aws_cloudwatch_event_rule.pipeline_notifications[0].arn, null)
}
