output "lambda_role_name" {
  description = "The IAM role name created by this module. Null when execution_role_arn is provided."
  value       = local.lambda_role_name
}

output "lambda_role_arn" {
  description = "The IAM role ARN used by the Lambda function."
  value       = local.lambda_role_arn
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

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name when create_cloudwatch_log_group is true, else null."
  value       = var.create_cloudwatch_log_group ? aws_cloudwatch_log_group.lambda[0].name : null
}

output "lambda_alias_arns" {
  description = "Map of Lambda alias ARNs keyed by alias name."
  value       = { for k, v in aws_lambda_alias.this : k => v.arn }
}

output "lambda_alias_invoke_arns" {
  description = "Map of Lambda alias invoke ARNs keyed by alias name."
  value       = { for k, v in aws_lambda_alias.this : k => v.invoke_arn }
}
