# =============================================================================
# CodeDeploy Outputs
# =============================================================================

output "codedeploy_app_arn" {
  description = "The ARN of the CodeDeploy application."
  value       = aws_codedeploy_app.this.arn
}

output "codedeploy_app_id" {
  description = "The ID of the CodeDeploy application."
  value       = aws_codedeploy_app.this.id
}

output "codedeploy_app_name" {
  description = "The name of the CodeDeploy application."
  value       = aws_codedeploy_app.this.name
}

# =============================================================================
# Deployment Group Outputs
# =============================================================================

output "codedeploy_deployment_group_arns" {
  description = "Map of deployment group name to ARN."
  value       = { for k, v in aws_codedeploy_deployment_group.this : k => v.arn }
}

output "codedeploy_deployment_group_ids" {
  description = "Map of deployment group name to ID."
  value       = { for k, v in aws_codedeploy_deployment_group.this : k => v.deployment_group_id }
}

# =============================================================================
# Custom Deployment Config Outputs
# =============================================================================

output "codedeploy_deployment_config_ids" {
  description = "Map of custom deployment config name to ID."
  value       = { for k, v in aws_codedeploy_deployment_config.this : k => v.deployment_config_id }
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "codedeploy_role_arn" {
  description = "The ARN of the IAM role used by CodeDeploy."
  value       = local.service_role_arn
}

output "codedeploy_role_name" {
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
