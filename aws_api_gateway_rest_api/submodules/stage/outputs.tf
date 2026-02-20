output "deployment_id" {
  value = aws_api_gateway_deployment.this.id
}

output "stage_name" {
  value = aws_api_gateway_stage.this.stage_name
}

output "stage_arn" {
  value = aws_api_gateway_stage.this.arn
}

output "stage_execution_arn" {
  value = aws_api_gateway_stage.this.execution_arn
}

output "invoke_url" {
  value = aws_api_gateway_stage.this.invoke_url
}

output "access_log_group_name" {
  value = var.create_access_log_group ? aws_cloudwatch_log_group.apigw_access[0].name : null
}

output "access_log_group_arn" {
  value = var.create_access_log_group ? aws_cloudwatch_log_group.apigw_access[0].arn : null
}
