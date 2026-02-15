output "parameter_arns" {
  description = "Map of parameter ARNs keyed by parameter name."
  value       = { for name, param in aws_ssm_parameter.this : name => param.arn }
}

output "parameter_names" {
  description = "List of created parameter names."
  value       = [for param in aws_ssm_parameter.this : param.name]
}

output "parameter_versions" {
  description = "Map of parameter versions keyed by parameter name."
  value       = { for name, param in aws_ssm_parameter.this : name => param.version }
}
