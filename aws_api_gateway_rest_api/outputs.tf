output "rest_api_id" {
  description = "REST API ID."
  value       = module.api.id
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

output "stage_name" {
  description = "Stage name."
  value       = module.stage.stage_name
}

output "stage_arn" {
  description = "Stage ARN."
  value       = module.stage.stage_arn
}

output "invoke_url" {
  description = "Invoke URL for the deployed stage."
  value       = module.stage.invoke_url
}

output "access_log_group_name" {
  description = "Access log group name when created by module."
  value       = module.stage.access_log_group_name
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
