locals {
  certificates_by_domain = {
    for cert in var.certificates : cert.domain_name => cert
  }

  certificate_validation_domains = {
    for cert_domain, cert in local.certificates_by_domain :
    cert_domain => distinct(concat([cert.domain_name], try(cert.san, [])))
  }

  certificate_zone_ids = {
    for domain, cert in local.certificates_by_domain :
    domain => coalesce(
      try(var.certificates_map[domain].zone_id, null),
      try(cert.zone_id, null)
    )
  }

  dns_validation_records = merge([
    for cert_domain, domains in local.certificate_validation_domains : {
      for domain_name in domains :
      "${cert_domain}/${domain_name}" => {
        certificate_domain = cert_domain
        domain_name        = domain_name
        zone_id            = local.certificate_zone_ids[cert_domain]
      }
      if upper(try(local.certificates_by_domain[cert_domain].validation_method, "DNS")) == "DNS"
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
  name = one([
    for dvo in aws_acm_certificate.this[each.value.certificate_domain].domain_validation_options :
    dvo.resource_record_name
    if dvo.domain_name == each.value.domain_name
  ])
  type = one([
    for dvo in aws_acm_certificate.this[each.value.certificate_domain].domain_validation_options :
    dvo.resource_record_type
    if dvo.domain_name == each.value.domain_name
  ])
  records = [one([
    for dvo in aws_acm_certificate.this[each.value.certificate_domain].domain_validation_options :
    dvo.resource_record_value
    if dvo.domain_name == each.value.domain_name
  ])]
  ttl = 60
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