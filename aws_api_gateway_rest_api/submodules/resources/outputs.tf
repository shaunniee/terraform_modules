output "resource_ids" {
  value = merge(
    { for k, r in aws_api_gateway_resource.level_1 : k => r.id },
    { for k, r in aws_api_gateway_resource.level_2 : k => r.id },
    { for k, r in aws_api_gateway_resource.level_3 : k => r.id },
    { for k, r in aws_api_gateway_resource.level_4 : k => r.id },
    { for k, r in aws_api_gateway_resource.level_5 : k => r.id },
  )
}