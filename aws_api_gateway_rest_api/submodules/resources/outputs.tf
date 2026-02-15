output "resource_ids" {
  value = { for k, v in aws_api_gateway_resource.this : k => v.id }
}
