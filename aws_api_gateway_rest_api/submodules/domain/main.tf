locals {
  is_edge = var.endpoint_type == "EDGE"
}

resource "aws_api_gateway_domain_name" "this" {
  domain_name              = var.domain_name
  regional_certificate_arn = local.is_edge ? null : var.certificate_arn
  certificate_arn          = local.is_edge ? var.certificate_arn : null
  security_policy          = var.security_policy

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = var.tags
}

resource "aws_api_gateway_base_path_mapping" "this" {
  api_id      = var.rest_api_id
  stage_name  = var.stage_name
  domain_name = aws_api_gateway_domain_name.this.domain_name
  base_path   = var.base_path
}

resource "aws_route53_record" "this" {
  count = var.create_route53_record ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = coalesce(var.record_name, var.domain_name)
  type    = "A"

  alias {
    name                   = local.is_edge ? aws_api_gateway_domain_name.this.cloudfront_domain_name : aws_api_gateway_domain_name.this.regional_domain_name
    zone_id                = local.is_edge ? aws_api_gateway_domain_name.this.cloudfront_zone_id : aws_api_gateway_domain_name.this.regional_zone_id
    evaluate_target_health = false
  }
}
