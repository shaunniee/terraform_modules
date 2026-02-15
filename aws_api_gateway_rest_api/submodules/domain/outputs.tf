output "domain_name" {
  value = aws_api_gateway_domain_name.this.domain_name
}

output "regional_domain_name" {
  value = aws_api_gateway_domain_name.this.regional_domain_name
}

output "regional_zone_id" {
  value = aws_api_gateway_domain_name.this.regional_zone_id
}
