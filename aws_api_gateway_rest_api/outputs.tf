output "rest_api_id" {
  description = "REST API ID."
  value       = module.api.id
}

output "execution_role_name" {
  description = "IAM role name created by module (or null when external role used)."
  value       = local.role_name
}

output "execution_role_arn" {
  description = "IAM role ARN used for API Gateway account CloudWatch role association."
  value       = local.role_arn
}

output "rest_api_execution_arn" {
  description = "Execution ARN for IAM permissions."
  value       = module.api.execution_arn
}

output "rest_api_root_resource_id" {
  description = "Root resource ID of the API."
  value       = module.api.root_resource_id
}

output "resource_ids" {
  description = "Map of created resource IDs keyed by resource key."
  value       = module.resources.resource_ids
}

output "authorizer_ids" {
  description = "Map of created authorizer IDs keyed by authorizer key."
  value       = module.authorizers.authorizer_ids
}

output "request_validator_ids" {
  description = "Map of request validator IDs keyed by validator key."
  value       = { for k, v in aws_api_gateway_request_validator.this : k => v.id }
}

output "methods_index" {
  description = "Map of methods with resolved resource IDs and HTTP methods."
  value       = module.methods.methods_index
}

output "integration_ids" {
  description = "Map of integration IDs keyed by integration key."
  value       = module.integrations.integration_ids
}

output "method_response_ids" {
  description = "Map of method response IDs keyed by response key."
  value       = module.responses.method_response_ids
}

output "integration_response_ids" {
  description = "Map of integration response IDs keyed by response key."
  value       = module.responses.integration_response_ids
}

output "deployment_id" {
  description = "Deployment ID."
  value       = module.stage.deployment_id
}

output "stage_name" {
  description = "Stage name."
  value       = module.stage.stage_name
}

output "stage_arn" {
  description = "Stage ARN."
  value       = module.stage.stage_arn
}

output "stage_execution_arn" {
  description = "Stage execution ARN. Useful for scoping Lambda permissions to a specific stage."
  value       = module.stage.stage_execution_arn
}

output "invoke_url" {
  description = "Invoke URL for the deployed stage."
  value       = module.stage.invoke_url
}

output "access_log_group_name" {
  description = "Access log group name when created by module."
  value       = module.stage.access_log_group_name
}

output "access_log_group_arn" {
  description = "Access log group ARN when created by module. Useful for subscription filters and cross-account log delivery."
  value       = module.stage.access_log_group_arn
}

output "cloudwatch_metric_alarm_arns" {
  description = "Map of CloudWatch metric alarm ARNs keyed by alarm key."
  value = {
    for alarm_key, alarm in aws_cloudwatch_metric_alarm.apigw :
    alarm_key => alarm.arn
  }
}

output "cloudwatch_metric_alarm_names" {
  description = "Map of CloudWatch metric alarm names keyed by alarm key."
  value = {
    for alarm_key, alarm in aws_cloudwatch_metric_alarm.apigw :
    alarm_key => alarm.alarm_name
  }
}

output "custom_domain_name" {
  description = "Custom domain name when create_domain_name is true."
  value       = var.create_domain_name ? module.domain[0].domain_name : null
}

output "custom_domain_regional_domain_name" {
  description = "Regional domain target for DNS alias when custom domain is enabled."
  value       = var.create_domain_name ? module.domain[0].regional_domain_name : null
}

output "custom_domain_regional_zone_id" {
  description = "Regional zone ID for DNS alias when custom domain is enabled."
  value       = var.create_domain_name ? module.domain[0].regional_zone_id : null
}

output "dashboard_name" {
  description = "CloudWatch dashboard name (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
}

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
}

output "cloudwatch_metric_anomaly_alarm_arns" {
  description = "Map of CloudWatch anomaly alarm ARNs keyed by metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.apigw_anomaly : k => v.arn }
}

output "cloudwatch_metric_anomaly_alarm_names" {
  description = "Map of CloudWatch anomaly alarm names keyed by metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.apigw_anomaly : k => v.alarm_name }
}
