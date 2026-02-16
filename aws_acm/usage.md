
# AWS ACM Terraform Module

Reusable module for creating one or more ACM certificates with optional Route53 DNS validation records.

This module supports:
- Multiple certificates in one module call
- SAN certificates (multi-domain certs)
- Validation methods: `DNS` and `EMAIL`
- Automatic Route53 DNS validation records for all required validation domains (including SANs)
- Certificate validation resources per certificate

## How Validation Works

For each certificate:
- ACM creates one or more domain validation options.
- If validation method is `DNS` and a Route53 `zone_id` is available, the module creates DNS validation records for all required domains.
- The module then runs certificate validation using those DNS records.
- If validation method is `EMAIL`, no Route53 records are created.

`zone_id` lookup priority:
1. `certificates_map[domain_name].zone_id`
2. `certificates[].zone_id`

## Basic Usage (Single DNS Certificate)

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "example.com"
      validation_method = "DNS"
      san               = ["www.example.com"]
      tags = {
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
  ]

  certificates_map = {
    "example.com" = {
      zone_id = "Z123456789ABCDEFG"
    }
  }
}
```

## Scenario: Multiple Certificates (DNS + EMAIL)

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "api.example.com"
      validation_method = "DNS"
      san               = ["internal-api.example.com"]
      tags = {
        Environment = "prod"
        Service     = "api"
      }
    },
    {
      domain_name       = "notifications.example.com"
      validation_method = "EMAIL"
      tags = {
        Environment = "prod"
        Service     = "notifications"
      }
    }
  ]

  certificates_map = {
    "api.example.com" = {
      zone_id = "Z123456789ABCDEFG"
    }
  }
}
```

## Scenario: Use `zone_id` Directly in Certificate Object

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "service.example.com"
      validation_method = "DNS"
      zone_id           = "Z123456789ABCDEFG"
    }
  ]
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `certificates` | list(object) | `[]` | No | List of certificate definitions |
| `certificates[].domain_name` | string | - | Yes (per item) | Primary domain name (must be unique across list) |
| `certificates[].san` | list(string) | `[]` | No | Subject Alternative Names |
| `certificates[].validation_method` | string | - | Yes (per item) | `DNS` or `EMAIL` |
| `certificates[].zone_id` | string | `null` | No | Optional Route53 zone ID fallback for DNS validation |
| `certificates[].tags` | map(string) | `{}` | No | Tags for certificate |
| `certificates_map` | map(object) | `{}` | No | Optional domain-keyed map with `zone_id` used for DNS record creation |
| `certificates_map[domain].zone_id` | string | `null` | No | Route53 zone ID for that certificate domain |

## Validation Rules

- `certificates[].domain_name` must be non-empty and unique.
- `certificates[].validation_method` must be `DNS` or `EMAIL`.
- `certificates[].san` entries must be non-empty and must not duplicate the primary domain.
- `certificates[].zone_id` and `certificates_map[*].zone_id` must be non-empty when provided.

## Outputs

| Output | Description |
|--------|-------------|
| `certificate_ids` | Certificate IDs keyed by certificate domain |
| `certificate_arns` | Certificate ARNs keyed by certificate domain |
| `certificate_statuses` | Certificate statuses keyed by certificate domain |
| `certificate_domain_validation_options` | ACM domain validation options keyed by certificate domain |
| `dns_validation_record_fqdns` | Created DNS validation record FQDNs keyed by `<certificate_domain>/<validation_domain>` |
| `validated_certificate_arns` | Validated certificate ARNs keyed by certificate domain |

## Notes

- Certificates are internally keyed by `domain_name`; duplicate domains are not allowed.
- For SAN certificates, DNS validation may require multiple records and the module creates all required records when zone ID is available.
- `create_before_destroy` is enabled on `aws_acm_certificate` to reduce replacement downtime risk.
- For `EMAIL` validation, certificate issuance still requires manual email approval in domain inboxes.


