
# AWS ACM Terraform Module

Reusable module for creating one or more ACM certificates with optional DNS validation records in Route 53.

This module supports:
- Multiple certificates in one module call
- Subject Alternative Names (SANs)
- Validation methods: DNS or EMAIL
- Optional Route 53 DNS validation record creation

## Basic Usage (Single Certificate)

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "example.com"
      san               = ["www.example.com"]
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

## Advanced Usage (Multiple Certificates)

```hcl
module "acm" {
  source = "./aws_acm"

  certificates = [
    {
      domain_name       = "api.example.com"
      san               = ["internal-api.example.com"]
      validation_method = "DNS"
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

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| certificates | list(object) | [] | No | List of certificate definitions |
| certificates[].domain_name | string | - | Yes (per item) | Primary domain name for the certificate |
| certificates[].san | list(string) | [] | No | Subject Alternative Names |
| certificates[].validation_method | string | - | Yes (per item) | Validation method, typically DNS or EMAIL |
| certificates[].zone_id | string | null | No | Hosted zone ID (declared in schema, not used directly by resources) |
| certificates[].tags | map(string) | {} | No | Tags applied to that certificate |
| certificates_map | map(any) | {} | No | Map keyed by domain name used for lookup during DNS validation |

## DNS Validation Behavior

- DNS validation records are created only when:
  - certificate validation_method is DNS, and
  - matching domain key exists in certificates_map with zone_id.
- For a certificate with domain_name example.com, certificates_map should include:

```hcl
certificates_map = {
  "example.com" = {
    zone_id = "Z123456789ABCDEFG"
  }
}
```

## Outputs

This module currently does not define outputs in outputs.tf.

## Notes

- Certificates are indexed by domain_name internally, so domain names in certificates should be unique.
- create_before_destroy is enabled for aws_acm_certificate to reduce replacement downtime risk.
- For EMAIL validation, Route 53 validation records are not created.


