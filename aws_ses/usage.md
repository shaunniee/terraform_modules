# AWS SES Terraform Module

Reusable and dynamic SES module for:
- Domain and email identities
- DKIM and custom MAIL FROM configuration
- Identity policies
- Configuration sets and SNS event destinations
- SES templates

## Basic Usage

```hcl
module "ses" {
  source = "./aws_ses"

  domain_identities = {
    "example.com" = {
      dkim_enabled = true
    }
  }

  email_identities = [
    "noreply@example.com"
  ]
}
```

## Advanced Usage

```hcl
module "ses" {
  source = "./aws_ses"

  domain_identities = {
    "example.com" = {
      dkim_enabled           = true
      mail_from_domain       = "mail.example.com"
      behavior_on_mx_failure = "UseDefaultValue"
    }
    "example.org" = {
      dkim_enabled = false
    }
  }

  email_identities = [
    "support@example.com",
    "alerts@example.org"
  ]

  identity_policies = {
    allow_send_from_app = {
      identity = "example.com"
      policy   = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid    = "AllowAppRole"
            Effect = "Allow"
            Principal = {
              AWS = "arn:aws:iam::123456789012:role/app-mailer-role"
            }
            Action   = ["ses:SendEmail", "ses:SendRawEmail"]
            Resource = "*"
          }
        ]
      })
    }
  }

  configuration_sets = ["default", "marketing"]

  event_destinations = {
    default_delivery = {
      configuration_set_name = "default"
      matching_types         = ["send", "delivery", "bounce", "complaint"]
      sns_topic_arn          = "arn:aws:sns:us-east-1:123456789012:ses-events"
    }
  }

  templates = {
    welcome_email = {
      subject_part = "Welcome to Example"
      html_part    = "<h1>Welcome {{name}}</h1><p>Thanks for joining.</p>"
      text_part    = "Welcome {{name}}. Thanks for joining."
    }
  }
}
```

## Input Summary

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `domain_identities` | `map(object)` | `{}` | Domain identities keyed by domain |
| `email_identities` | `list(string)` | `[]` | Email identities |
| `identity_policies` | `map(object)` | `{}` | SES identity policies |
| `configuration_sets` | `list(string)` | `[]` | SES configuration set names |
| `event_destinations` | `map(object)` | `{}` | SNS-based event destinations |
| `templates` | `map(object)` | `{}` | SES templates keyed by template name |

## Outputs

| Output | Description |
|--------|-------------|
| `domain_identity_arns` | Domain identity ARNs |
| `domain_verification_tokens` | Domain verification tokens for DNS TXT records |
| `domain_dkim_tokens` | DKIM CNAME tokens |
| `email_identity_arns` | Email identity ARNs |
| `configuration_set_names` | Created configuration sets |
| `template_names` | Created templates |

## Notes

- Domain verification requires creating DNS records using output tokens.
- DKIM tokens must be added as CNAME records in DNS.
- This module currently supports SNS event destinations for configuration sets.
