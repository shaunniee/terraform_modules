output "domain_name" {
  value = aws_api_gateway_domain_name.this.domain_name
}

output "regional_domain_name" {
  value = local.is_edge ? null : aws_api_gateway_domain_name.this.regional_domain_name
}

output "regional_zone_id" {
  value = local.is_edge ? null : aws_api_gateway_domain_name.this.regional_zone_id
}

output "cloudfront_domain_name" {
  value = local.is_edge ? aws_api_gateway_domain_name.this.cloudfront_domain_name : null
}

output "cloudfront_zone_id" {
  value = local.is_edge ? aws_api_gateway_domain_name.this.cloudfront_zone_id : null
}
