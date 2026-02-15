output "integration_ids" {
  value = { for k, v in aws_api_gateway_integration.this : k => v.id }
}
