resource "aws_ses_domain_identity" "domain" {
  for_each = var.domain_identities
  domain   = each.key
}

resource "aws_ses_domain_dkim" "domain" {
  for_each = {
    for domain, cfg in var.domain_identities : domain => cfg
    if cfg.dkim_enabled
  }

  domain = aws_ses_domain_identity.domain[each.key].domain
}

resource "aws_ses_domain_mail_from" "domain" {
  for_each = {
    for domain, cfg in var.domain_identities : domain => cfg
    if try(cfg.mail_from_domain, null) != null
  }

  domain                 = aws_ses_domain_identity.domain[each.key].domain
  mail_from_domain       = each.value.mail_from_domain
  behavior_on_mx_failure = each.value.behavior_on_mx_failure
}

resource "aws_ses_email_identity" "email" {
  for_each = toset(var.email_identities)
  email    = each.value
}

resource "aws_ses_identity_policy" "this" {
  for_each = var.identity_policies

  identity = each.value.identity
  name     = each.key
  policy   = each.value.policy
}

resource "aws_ses_configuration_set" "this" {
  for_each = toset(var.configuration_sets)

  name = each.value
}

resource "aws_ses_event_destination" "this" {
  for_each = var.event_destinations

  name                   = each.key
  configuration_set_name = each.value.configuration_set_name
  enabled                = each.value.enabled
  matching_types         = each.value.matching_types

  sns_destination {
    topic_arn = each.value.sns_topic_arn
  }
}

resource "aws_ses_template" "this" {
  for_each = var.templates

  name    = each.key
  subject = each.value.subject_part
  html    = each.value.html_part
  text    = each.value.text_part
}
