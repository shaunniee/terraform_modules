# =============================================================================
# GraphQL API
# =============================================================================

output "api_id" {
  description = "The unique identifier of the GraphQL API."
  value       = aws_appsync_graphql_api.this.id
}

output "api_arn" {
  description = "The ARN of the GraphQL API."
  value       = aws_appsync_graphql_api.this.arn
}

output "api_uris" {
  description = "Map of URIs for the GraphQL API (GRAPHQL, REALTIME)."
  value       = aws_appsync_graphql_api.this.uris
}

output "api_name" {
  description = "The name of the GraphQL API."
  value       = aws_appsync_graphql_api.this.name
}

# =============================================================================
# IAM Role
# =============================================================================

output "logging_role_arn" {
  description = "The ARN of the IAM role used for CloudWatch logging."
  value       = local.create_logging_role ? aws_iam_role.logging[0].arn : null
}

output "logging_role_name" {
  description = "The name of the IAM role used for CloudWatch logging."
  value       = local.create_logging_role ? aws_iam_role.logging[0].name : null
}

# =============================================================================
# API Keys
# =============================================================================

output "api_key_ids" {
  description = "Map of API key logical names to their IDs."
  value       = { for k, v in aws_appsync_api_key.this : k => v.id }
}

output "api_key_values" {
  description = "Map of API key logical names to their key values."
  value       = { for k, v in aws_appsync_api_key.this : k => v.key }
  sensitive   = true
}

# =============================================================================
# Data Sources
# =============================================================================

output "datasource_arns" {
  description = "Map of data source names to their ARNs."
  value       = { for k, v in aws_appsync_datasource.this : k => v.arn }
}

# =============================================================================
# Functions
# =============================================================================

output "function_ids" {
  description = "Map of function logical names to their function IDs."
  value       = { for k, v in aws_appsync_function.this : k => v.function_id }
}

output "function_arns" {
  description = "Map of function logical names to their ARNs."
  value       = { for k, v in aws_appsync_function.this : k => v.arn }
}

# =============================================================================
# Resolvers
# =============================================================================

output "resolver_arns" {
  description = "Map of resolver logical names to their ARNs."
  value       = { for k, v in aws_appsync_resolver.this : k => v.arn }
}

# =============================================================================
# API Cache
# =============================================================================

output "api_cache_enabled" {
  description = "Whether API caching is enabled."
  value       = var.caching_enabled
}

# =============================================================================
# Custom Domain
# =============================================================================

output "domain_name" {
  description = "The custom domain name (if configured)."
  value       = var.domain_name != null ? aws_appsync_domain_name.this[0].domain_name : null
}

output "domain_hosted_zone_id" {
  description = "The hosted zone ID for the custom domain (for Route53 alias records)."
  value       = var.domain_name != null ? aws_appsync_domain_name.this[0].hosted_zone_id : null
}

output "domain_appsync_domain_name" {
  description = "The AppSync domain name for the custom domain (CloudFront distribution domain)."
  value       = var.domain_name != null ? aws_appsync_domain_name.this[0].appsync_domain_name : null
}

# =============================================================================
# Source API Associations (Merged API)
# =============================================================================

output "source_api_association_ids" {
  description = "Map of source API association logical names to their IDs."
  value       = { for k, v in aws_appsync_source_api_association.this : k => v.id }
}

output "source_api_association_arns" {
  description = "Map of source API association logical names to their ARNs."
  value       = { for k, v in aws_appsync_source_api_association.this : k => v.arn }
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

output "log_group_name" {
  description = "Name of the CloudWatch log group."
  value       = local.create_log_group ? aws_cloudwatch_log_group.appsync[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group."
  value       = local.create_log_group ? aws_cloudwatch_log_group.appsync[0].arn : null
}

# =============================================================================
# Observability
# =============================================================================

output "alarm_arns" {
  description = "Map of metric alarm names to their ARNs."
  value       = { for k, v in aws_cloudwatch_metric_alarm.appsync : k => v.arn }
}

output "alarm_names" {
  description = "Map of metric alarm logical keys to their names."
  value       = { for k, v in aws_cloudwatch_metric_alarm.appsync : k => v.alarm_name }
}

output "anomaly_alarm_arns" {
  description = "Map of anomaly alarm logical keys to their ARNs."
  value       = { for k, v in aws_cloudwatch_metric_alarm.appsync_anomaly : k => v.arn }
}

output "anomaly_alarm_names" {
  description = "Map of anomaly alarm logical keys to their names."
  value       = { for k, v in aws_cloudwatch_metric_alarm.appsync_anomaly : k => v.alarm_name }
}

output "log_metric_filter_names" {
  description = "Map of log metric filter logical keys to their names."
  value       = { for k, v in aws_cloudwatch_log_metric_filter.this : k => v.name }
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = local.dashboard_enabled ? aws_cloudwatch_dashboard.this[0].dashboard_name : null
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard."
  value       = local.dashboard_enabled ? aws_cloudwatch_dashboard.this[0].dashboard_arn : null
}
