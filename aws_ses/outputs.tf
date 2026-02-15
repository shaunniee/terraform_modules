output "domain_identity_arns" {
  description = "Map of SES domain identity ARNs keyed by domain."
  value       = { for d, r in aws_ses_domain_identity.domain : d => r.arn }
}

output "domain_verification_tokens" {
  description = "Map of SES domain verification tokens keyed by domain."
  value       = { for d, r in aws_ses_domain_identity.domain : d => r.verification_token }
}

output "domain_dkim_tokens" {
  description = "Map of SES DKIM token lists keyed by domain."
  value       = { for d, r in aws_ses_domain_dkim.domain : d => r.dkim_tokens }
}

output "email_identity_arns" {
  description = "Map of SES email identity ARNs keyed by email."
  value       = { for e, r in aws_ses_email_identity.email : e => r.arn }
}

output "configuration_set_names" {
  description = "List of SES configuration set names created."
  value       = [for _, r in aws_ses_configuration_set.this : r.name]
}

output "template_names" {
  description = "List of SES template names created."
  value       = [for _, r in aws_ses_template.this : r.name]
}
