output "certificate_ids" {
	description = "Certificate IDs keyed by certificate domain_name."
	value       = { for domain, cert in aws_acm_certificate.this : domain => cert.id }
}

output "certificate_arns" {
	description = "Certificate ARNs keyed by certificate domain_name."
	value       = { for domain, cert in aws_acm_certificate.this : domain => cert.arn }
}

output "certificate_statuses" {
	description = "Certificate statuses keyed by certificate domain_name."
	value       = { for domain, cert in aws_acm_certificate.this : domain => cert.status }
}

output "certificate_domain_validation_options" {
	description = "Domain validation options returned by ACM, keyed by certificate domain_name."
	value       = { for domain, cert in aws_acm_certificate.this : domain => cert.domain_validation_options }
}

output "dns_validation_record_fqdns" {
	description = "Route53 DNS validation record FQDNs keyed by '<certificate_domain>/<validation_domain>' for DNS-validated certificates with zone IDs."
	value       = { for key, record in aws_route53_record.dns_validation : key => record.fqdn }
}

output "validated_certificate_arns" {
	description = "Certificate validation resource ARNs keyed by certificate domain_name."
	value       = { for domain, validation in aws_acm_certificate_validation.this : domain => validation.certificate_arn }
}
