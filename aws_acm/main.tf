resource "aws_acm_certificate" "this" {
  for_each = { for cert in var.certificates : cert.domain_name => cert }

  domain_name       = each.value.domain_name
  subject_alternative_names = lookup(each.value, "san", [])
  validation_method = each.value.validation_method

  lifecycle {
    create_before_destroy = true
  }

  tags = lookup(each.value, "tags", {})
}

# Optional DNS validation
resource "aws_route53_record" "dns_validation" {
  for_each = {
    for cert_key, cert in aws_acm_certificate.this : cert_key => cert
    if cert.validation_method == "DNS" && lookup(certificates_map[cert_key], "zone_id", null) != null
  }

  zone_id = lookup(certificates_map[each.key], "zone_id")
  name    = aws_acm_certificate.this[each.key].domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.this[each.key].domain_validation_options[0].resource_record_type
  records = [aws_acm_certificate.this[each.key].domain_validation_options[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  for_each = { for k, cert in aws_acm_certificate.this : k => cert }

  certificate_arn         = each.value.arn
  validation_record_fqdns = lookup(var.certificates_map, each.key, {}).zone_id != null ? [aws_route53_record.dns_validation[each.key].fqdn] : []
}