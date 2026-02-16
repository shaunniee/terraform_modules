locals {
  certificates_by_domain = {
    for cert in var.certificates : cert.domain_name => cert
  }

  certificate_zone_ids = {
    for domain, cert in local.certificates_by_domain :
    domain => coalesce(
      try(var.certificates_map[domain].zone_id, null),
      try(cert.zone_id, null)
    )
  }

  dns_validation_records = merge([
    for cert_domain, cert in aws_acm_certificate.this : {
      for dvo in cert.domain_validation_options :
      "${cert_domain}/${dvo.domain_name}" => {
        certificate_domain = cert_domain
        zone_id            = local.certificate_zone_ids[cert_domain]
        name               = dvo.resource_record_name
        type               = dvo.resource_record_type
        value              = dvo.resource_record_value
      }
      if cert.validation_method == "DNS" && local.certificate_zone_ids[cert_domain] != null
    }
  ]...)
}

resource "aws_acm_certificate" "this" {
  for_each = local.certificates_by_domain

  domain_name               = each.value.domain_name
  subject_alternative_names = try(each.value.san, [])
  validation_method         = upper(each.value.validation_method)

  lifecycle {
    create_before_destroy = true
  }

  tags = try(each.value.tags, {})
}

resource "aws_route53_record" "dns_validation" {
  for_each = local.dns_validation_records

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  for_each = aws_acm_certificate.this

  certificate_arn = each.value.arn
  validation_record_fqdns = [
    for key, record in aws_route53_record.dns_validation :
    record.fqdn
    if local.dns_validation_records[key].certificate_domain == each.key
  ]
}