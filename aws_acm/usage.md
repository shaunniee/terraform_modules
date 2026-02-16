# AWS ACM Terraform Module - Complete Guide

Reusable Terraform module for provisioning and validating ACM certificates with optional Route53 DNS record automation.

It supports:
- Multiple certificates in a single module call
- SAN certificates (multi-domain certs)
- Validation methods: `DNS` and `EMAIL`
- Automatic DNS validation records for all ACM domain validation options (including SANs)
- Flexible zone lookup via `certificates_map` and/or per-certificate `zone_id`
- Useful outputs for downstream integrations

## Table of Contents

1. [Module Design](#1-module-design)
2. [Prerequisites](#2-prerequisites)
3. [Scenario-Based Usage Examples](#3-scenario-based-usage-examples)
4. [Inputs Reference](#4-inputs-reference)
5. [Validation Rules Enforced by Module](#5-validation-rules-enforced-by-module)
6. [Outputs Reference](#6-outputs-reference)
7. [Behavior Details](#7-behavior-details)
8. [Best Practices](#8-best-practices)
9. [Troubleshooting Checklist](#9-troubleshooting-checklist)
10. [Known Limits](#10-known-limits)

---

## 1) Module Design

The module builds the following resources:
- `aws_acm_certificate.this` (one per `domain_name`)
- `aws_route53_record.dns_validation` (for DNS-validated certs when zone ID is available)
- `aws_acm_certificate_validation.this` (one per certificate)

Internal flow:
1. Create ACM certificate(s)
2. Read ACM-generated `domain_validation_options`
3. Create Route53 DNS records for each required validation option (when eligible)
4. Trigger ACM certificate validation

Zone ID resolution priority for each certificate:
1. `certificates_map[domain_name].zone_id`
2. `certificates[].zone_id`

---

## 2) Prerequisites

- Terraform `>= 1.3`
- AWS provider configured
- ACM + Route53 IAM permissions
- Hosted zones available in Route53 when using DNS validation
- For CloudFront certificates, use ACM certificate in `us-east-1` region

---

## 3) Scenario-Based Usage Examples

### Scenario A: Single DNS-Validated Certificate

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "example.com"
      validation_method = "DNS"
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

---

### Scenario B: DNS Certificate with SANs

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "example.com"
      validation_method = "DNS"
      san               = ["www.example.com", "api.example.com"]
    }
  ]

  certificates_map = {
    "example.com" = {
      zone_id = "Z123456789ABCDEFG"
    }
  }
}
```

Notes:
- ACM can return multiple domain validation options for SAN certificates.
- The module creates all required DNS validation records, not only the primary domain record.

---

### Scenario C: Multiple Certificates (Mixed DNS and EMAIL)

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

---

### Scenario D: Use `zone_id` Directly in Certificate Object

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

---

### Scenario E: Prefer `certificates_map` over per-certificate `zone_id`

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "app.example.com"
      validation_method = "DNS"
      zone_id           = "Z_FALLBACK_ZONE"
    }
  ]

  certificates_map = {
    "app.example.com" = {
      zone_id = "Z_PRIMARY_ZONE"
    }
  }
}
```

Behavior:
- Module uses `certificates_map["app.example.com"].zone_id` first (`Z_PRIMARY_ZONE`).

---

### Scenario F: Cross-Account/External DNS Management

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "external.example.com"
      validation_method = "DNS"
    }
  ]
}
```

Notes:
- No `zone_id` provided means module does not create Route53 validation records.
- Use output `certificate_domain_validation_options` to create validation records externally.

---

## 4) Inputs Reference

### Top-Level Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `certificates` | list(object) | `[]` | No | List of ACM certificate definitions |
| `certificates_map` | map(object) | `{}` | No | Domain-keyed map with optional `zone_id` |

### Object Schemas

#### `certificates` item

```hcl
{
  domain_name       = string
  san               = optional(list(string), [])
  validation_method = string
  zone_id           = optional(string)
  tags              = optional(map(string), {})
}
```

Field details:
- `domain_name`: primary certificate domain (used as unique key)
- `san`: additional domains for same certificate
- `validation_method`: `DNS` or `EMAIL`
- `zone_id`: optional hosted zone ID fallback for DNS validation record creation
- `tags`: optional tags applied to certificate resource

#### `certificates_map` item

```hcl
{
  zone_id = optional(string)
}
```

Map key is certificate `domain_name`.

---

## 5) Validation Rules Enforced by Module

The module validates inputs at plan time:
- `certificates[*].domain_name` must be non-empty.
- `certificates[*].domain_name` values must be unique (case-insensitive).
- `certificates[*].validation_method` must be `DNS` or `EMAIL`.
- `certificates[*].san` entries must be non-empty.
- `certificates[*].san` entries must not duplicate the certificate primary domain.
- `certificates[*].zone_id` must be null or non-empty.
- `certificates_map` keys must be non-empty.
- `certificates_map[*].zone_id` must be null or non-empty.

---

## 6) Outputs Reference

| Output | Description |
|--------|-------------|
| `certificate_ids` | Certificate IDs keyed by certificate domain |
| `certificate_arns` | Certificate ARNs keyed by certificate domain |
| `certificate_statuses` | Certificate statuses keyed by certificate domain |
| `certificate_domain_validation_options` | ACM domain validation options keyed by certificate domain |
| `dns_validation_record_fqdns` | Route53 validation record FQDNs keyed by `<certificate_domain>/<validation_domain>` |
| `validated_certificate_arns` | Validated certificate ARNs keyed by certificate domain |

Example output usage:

```hcl
output "api_cert_arn" {
  value = module.acm.certificate_arns["api.example.com"]
}
```

---

## 7) Behavior Details

- Certificates are keyed internally by `domain_name`.
- `validation_method` is normalized to uppercase in resource creation.
- DNS validation records are created only when:
  - certificate validation method is `DNS`, and
  - resolved zone ID is available.
- `aws_acm_certificate_validation` is always created for each certificate.
  - For DNS certificates with created records, it uses those record FQDNs.
  - For EMAIL certificates, issuance still depends on email approval workflow.
- `create_before_destroy = true` is set for certificates to reduce replacement downtime risk.

---

## 8) Best Practices

- Keep `domain_name` keys stable to avoid unnecessary certificate recreation.
- Use SAN certificates to reduce certificate sprawl when lifecycle and ownership align.
- Prefer DNS validation in automated environments.
- Store zone mapping in `certificates_map` for clean separation of cert metadata and DNS routing metadata.
- Tag certificates with environment/service ownership.
- For CloudFront certificates, ensure ACM cert exists in `us-east-1`.

---

## 9) Troubleshooting Checklist

- Certificate remains `PENDING_VALIDATION`:
  - Verify Route53 zone ID is correct and public DNS can resolve validation CNAME.
- No DNS validation records created:
  - Confirm `validation_method = "DNS"` and zone ID is provided via `certificates_map` or `certificates[].zone_id`.
- Duplicate key error:
  - Ensure certificate `domain_name` values are unique in `certificates`.
- EMAIL validation not issuing:
  - Confirm approval links were accepted in domain validation emails.
- Wrong zone selected:
  - Remember `certificates_map` takes precedence over per-certificate `zone_id`.

---

## 10) Known Limits

- Module assumes one hosted zone ID per certificate domain key; complex multi-zone SAN routing may require external DNS management.
- Module does not auto-discover hosted zones; zone IDs must be supplied.
- Region-specific ACM requirements (for example CloudFront requiring `us-east-1`) are deployment concerns outside module logic.
