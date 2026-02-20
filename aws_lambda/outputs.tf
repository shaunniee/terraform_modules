output "lambda_role_name" {
  description = "The IAM role name created by this module. Null when execution_role_arn is provided."
  value       = local.lambda_role_name
}

output "lambda_role_arn" {
  description = "The IAM role ARN used by the Lambda function."
  value       = local.lambda_role_arn
}

output "lambda_role_id" {
  description = "The IAM role ID created by this module. Useful for attaching additional policies externally. Null when execution_role_arn is provided."
  value       = local.create_role ? aws_iam_role.lambda_role[0].id : null
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.this.invoke_arn
}

output "lambda_version" {
  description = "The version of the Lambda function, used to trigger API Gateway deployments"
  value       = aws_lambda_function.this.version
}

output "lambda_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "lambda_qualified_arn" {
  description = "The qualified ARN (with version) of the Lambda function."
  value       = aws_lambda_function.this.qualified_arn
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name when create_cloudwatch_log_group is true, else null."
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.lambda[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN when create_cloudwatch_log_group is true, else null. Useful for subscription filters and cross-account log delivery."
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.lambda[0].arn : null
}

output "lambda_alias_arns" {
  description = "Map of Lambda alias ARNs keyed by alias name."
  value       = { for k, v in aws_lambda_alias.this : k => v.arn }
}

output "lambda_alias_invoke_arns" {
  description = "Map of Lambda alias invoke ARNs keyed by alias name."
  value       = { for k, v in aws_lambda_alias.this : k => v.invoke_arn }
}

output "cloudwatch_metric_alarm_arns" {
  description = "Map of CloudWatch metric alarm ARNs keyed by metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda : k => v.arn }
}

output "cloudwatch_metric_alarm_names" {
  description = "Map of CloudWatch metric alarm names keyed by metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda : k => v.alarm_name }
}

output "cloudwatch_metric_anomaly_alarm_arns" {
  description = "Map of CloudWatch anomaly alarm ARNs keyed by metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_anomaly : k => v.arn }
}

output "cloudwatch_metric_anomaly_alarm_names" {
  description = "Map of CloudWatch anomaly alarm names keyed by metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_anomaly : k => v.alarm_name }
}

output "dlq_cloudwatch_metric_alarm_arns" {
  description = "Map of DLQ CloudWatch metric alarm ARNs keyed by dlq_cloudwatch_metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dlq : k => v.arn }
}

output "dlq_cloudwatch_metric_alarm_names" {
  description = "Map of DLQ CloudWatch metric alarm names keyed by dlq_cloudwatch_metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dlq : k => v.alarm_name }
}

output "log_metric_filter_names" {
  description = "Map of log metric filter names keyed by log_metric_filters key."
  value       = { for k, v in aws_cloudwatch_log_metric_filter.this : k => v.name }
}

output "dlq_log_metric_filter_names" {
  description = "Map of DLQ log metric filter names keyed by dlq_log_metric_filters key."
  value       = { for k, v in aws_cloudwatch_log_metric_filter.dlq : k => v.name }
}

output "dashboard_name" {
  description = "CloudWatch dashboard name (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
}

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
}
