# AWS CloudFront Terraform Module - Complete Guide

Reusable Terraform module for provisioning CloudFront distributions with support for S3 and custom origins, path-based behaviors, signed URLs, SPA fallback, custom domains, WAF, and logging.

## Table of Contents

1. [What This Module Creates](#1-what-this-module-creates)
2. [Prerequisites](#2-prerequisites)
3. [Scenario-Based Usage Examples](#3-scenario-based-usage-examples)
4. [Inputs Reference](#4-inputs-reference)
5. [Validation Rules Enforced by Module](#5-validation-rules-enforced-by-module)
6. [Outputs Reference](#6-outputs-reference)
7. [Behavior Notes](#7-behavior-notes)
8. [Best Practices](#8-best-practices)
9. [Troubleshooting Checklist](#9-troubleshooting-checklist)

---

## 1) What This Module Creates

- `aws_cloudfront_distribution.this`
- `aws_cloudfront_origin_access_control.this` (for private S3 origins)
- `aws_cloudfront_public_key.signed_urls` (optional, when `kms_key_arn` set)
- `aws_cloudfront_key_group.signed_urls` (optional, when `kms_key_arn` set)
- Supporting data lookups for managed cache/origin request policies

---

## 2) Prerequisites

- Terraform `>= 1.3`
- AWS provider configured
- IAM permissions for CloudFront, KMS (optional), and WAF (optional)
- For aliases/custom domain:
  - ACM certificate must exist in `us-east-1`

---

## 3) Scenario-Based Usage Examples

### Scenario A: Basic S3 Website Distribution

```hcl
module "cloudfront" {
  source = "./aws_cloudfront"

  distribution_name = "my-app-cdn"

  origins = {
    app = {
      domain_name       = "my-app-bucket.s3.us-east-1.amazonaws.com"
      origin_id         = "app-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "app-origin"
  }
}
```

---

### Scenario B: Multi-Origin Distribution (S3 + Custom API Origin)

```hcl
module "cloudfront_multi" {
  source = "./aws_cloudfront"

  distribution_name = "frontend-api-cdn"

  origins = {
    static = {
      domain_name       = "frontend-assets.s3.us-east-1.amazonaws.com"
      origin_id         = "static-origin"
      is_private_origin = true
      origin_type       = "s3"
    }

    api = {
      domain_name       = "api.internal.example.com"
      origin_id         = "api-origin"
      is_private_origin = false
      origin_type       = "custom"
      custom_origin_config = {
        origin_protocol_policy  = "https-only"
        origin_ssl_protocols    = ["TLSv1.2"]
        https_port              = 443
        http_port               = 80
        origin_read_timeout     = 30
        origin_keepalive_timeout = 5
      }
    }
  }

  default_cache_behavior = {
    target_origin_id = "static-origin"
  }

  ordered_cache_behavior = {
    api_paths = {
      path_pattern           = "/api/*"
      target_origin_id       = "api-origin"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]
      cache_disabled         = true
      requires_signed_url    = false
    }
  }
}
```

---

### Scenario C: Signed URL Protected Path

```hcl
module "cloudfront_signed" {
  source = "./aws_cloudfront"

  distribution_name = "private-content-cdn"
  kms_key_arn       = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

  origins = {
    media = {
      domain_name       = "private-media.s3.us-east-1.amazonaws.com"
      origin_id         = "media-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "media-origin"
  }

  ordered_cache_behavior = {
    protected_media = {
      path_pattern        = "/protected/*"
      target_origin_id    = "media-origin"
      allowed_methods     = ["GET", "HEAD", "OPTIONS"]
      cached_methods      = ["GET", "HEAD"]
      cache_disabled      = false
      requires_signed_url = true
    }
  }
}
```

---

### Scenario D: SPA Fallback

```hcl
module "cloudfront_spa" {
  source = "./aws_cloudfront"

  distribution_name   = "spa-cdn"
  default_root_object = "index.html"
  spa_fallback        = true

  spa_fallback_status_codes = [403, 404]

  origins = {
    app = {
      domain_name       = "spa-bucket.s3.us-east-1.amazonaws.com"
      origin_id         = "spa-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "spa-origin"
  }
}
```

---

### Scenario E: Custom Domain + WAF + Logging + Tags

```hcl
module "cloudfront_prod" {
  source = "./aws_cloudfront"

  distribution_name = "frontend-prod-cdn"
  comment           = "Production frontend CDN"
  price_class       = "PriceClass_200"

  aliases             = ["cdn.example.com", "static.example.com"]
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  ssl_support_method  = "sni-only"

  web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/frontend-prod/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  logging = {
    bucket          = "my-cloudfront-logs.s3.amazonaws.com"
    include_cookies = false
    prefix          = "frontend-prod/"
  }

  origins = {
    web = {
      domain_name       = "frontend-assets.s3.us-east-1.amazonaws.com"
      origin_id         = "web-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "web-origin"
  }

  tags = {
    Environment = "production"
    Service     = "frontend"
    ManagedBy   = "terraform"
  }
}
```

---

### Scenario F: Custom Cache/Origin Request Policy IDs

```hcl
module "cloudfront_policy_override" {
  source = "./aws_cloudfront"

  distribution_name = "policy-override-cdn"

  origins = {
    app = {
      domain_name       = "api.example.com"
      origin_id         = "app-origin"
      is_private_origin = false
      origin_type       = "custom"
      custom_origin_config = {
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id          = "app-origin"
    cache_policy_id           = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id  = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
    allowed_methods           = ["GET", "HEAD", "OPTIONS"]
    cached_methods            = ["GET", "HEAD"]
  }
}
```

---

## 4) Inputs Reference

### Core Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `distribution_name` | string | - | Yes | Name prefix used by distribution-related resources |
| `comment` | string | `null` | No | Distribution comment (falls back to `distribution_name`) |
| `tags` | map(string) | `{}` | No | Tags for supported resources |
| `default_root_object` | string | `index.html` | No | Default object served at root |
| `price_class` | string | `PriceClass_100` | No | `PriceClass_100`, `PriceClass_200`, or `PriceClass_All` |
| `web_acl_id` | string | `null` | No | Optional WAF web ACL ARN |

### TLS / Domain Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `aliases` | list(string) | `[]` | No | Alternate domain names (CNAMEs) |
| `acm_certificate_arn` | string | `null` | Conditional | Required when aliases are set; must be `us-east-1` cert for CloudFront aliases |
| `ssl_support_method` | string | `sni-only` | No | `sni-only`, `vip`, or `static-ip` |
| `minimum_protocol_version` | string | `TLSv1.2_2021` | No | Viewer TLS policy |

### Logging Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `logging` | object | `null` | No | Access logging config `{ bucket, include_cookies, prefix }` |

### Origin Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `origins` | map(object) | - | Yes | Origin definitions (at least one) |

`origins` object schema:

```hcl
origins = {
  key = {
    domain_name       = string
    origin_id         = string
    is_private_origin = bool
    origin_type       = optional(string, "s3")
    origin_path       = optional(string)
    custom_origin_config = optional(object({
      http_port                = optional(number, 80)
      https_port               = optional(number, 443)
      origin_protocol_policy   = optional(string, "https-only")
      origin_ssl_protocols     = optional(list(string), ["TLSv1.2"])
      origin_read_timeout      = optional(number, 30)
      origin_keepalive_timeout = optional(number, 5)
    }))
  }
}
```

Notes:
- `origin_type = "s3"` works with S3 origins (public or private).
- `is_private_origin = true` is supported only for S3 origins.
- `origin_type = "custom"` requires `custom_origin_config`.

### Cache Behavior Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `default_cache_behavior` | object | `null` | Conditional | Preferred variable for default behavior |
| `default_cache_behaviour` | object | `null` | Conditional | Deprecated spelling (supported for compatibility) |
| `ordered_cache_behavior` | map(object) | `null` | No | Preferred variable for path-based ordered behaviors |
| `ordered_cache_behaviour` | map(object) | `null` | No | Deprecated spelling (supported for compatibility) |

Set only one spelling for each family:
- only one of `default_cache_behavior` / `default_cache_behaviour`
- only one of `ordered_cache_behavior` / `ordered_cache_behaviour`

`default_cache_behavior` / `default_cache_behaviour` schema:

```hcl
{
  target_origin_id         = string
  viewer_protocol_policy   = optional(string, "redirect-to-https")
  allowed_methods          = optional(list(string), ["GET", "HEAD", "OPTIONS"])
  cached_methods           = optional(list(string), ["GET", "HEAD"])
  cache_policy_id          = optional(string)
  origin_request_policy_id = optional(string)
}
```

`ordered_cache_behavior` / `ordered_cache_behaviour` item schema:

```hcl
{
  path_pattern             = string
  target_origin_id         = string
  allowed_methods          = list(string)
  cached_methods           = list(string)
  viewer_protocol_policy   = optional(string, "redirect-to-https")
  cache_policy_id          = optional(string)
  origin_request_policy_id = optional(string)
  cache_disabled           = bool
  requires_signed_url      = bool
}
```

Behavior precedence for policy IDs:
- If `cache_policy_id` is set in behavior input, it is used.
- Otherwise:
  - `cache_disabled = true` => managed `CachingDisabled`
  - `cache_disabled = false` => managed `CachingOptimized`
- If `origin_request_policy_id` is not set, managed `CORS-S3Origin` is used.

### SPA / Signed URL Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `spa_fallback` | bool | `false` | No | Enables SPA fallback error responses |
| `spa_fallback_status_codes` | list(number) | `[404]` | No | Error codes converted to `200` with default root object |
| `kms_key_arn` | string | `null` | Conditional | Required when any ordered behavior sets `requires_signed_url = true` |

---

## 5) Validation Rules Enforced by Module

- `distribution_name` must match allowed format/length.
- `default_root_object` must be non-empty and not start with `/`.
- `price_class` must be valid CloudFront class.
- `aliases` cannot contain empty values.
- `acm_certificate_arn` must be valid ARN when set.
- When aliases are configured, `acm_certificate_arn` must be provided and in `us-east-1`.
- `origins` must contain at least one origin.
- Every origin must have non-empty `domain_name` and `origin_id`.
- `origin_id` values must be unique.
- `origins[*].origin_type` must be `s3` or `custom`.
- `custom_origin_config` is required for `origin_type = "custom"`.
- `is_private_origin = true` is allowed only for `origin_type = "s3"`.
- Custom origin protocol/SSL/timeout/port values are validated.
- Exactly one spelling variant can be used for each behavior family.
- One default behavior is required (preferred or deprecated spelling).
- All behavior `target_origin_id` values must match an origin.
- `ordered_cache_behavior.path_pattern` must start with `/` and be unique.
- Allowed/cached methods are validated and cached methods must be subset of allowed.
- If any ordered behavior sets `requires_signed_url = true`, `kms_key_arn` is required.
- SPA fallback status codes must be in `400..599`.

---

## 6) Outputs Reference

| Output | Description |
|--------|-------------|
| `cloudfront_domain_name` | Distribution domain name |
| `cloudfront_distribution_id` | Distribution ID |
| `cloudfront_distribution_arn` | Distribution ARN |
| `cloudfront_key_group_id` | Signed URL key group ID, or `null` when not configured |

---

## 7) Behavior Notes

- Default behavior and ordered behaviors support both legacy British and preferred US spelling inputs.
- For private S3 origins, module creates CloudFront OAC and attaches it automatically.
- Signed URL support is enabled per ordered behavior using `requires_signed_url = true`.
- `viewer_certificate` uses default CloudFront cert when `acm_certificate_arn` is unset.

---

## 8) Best Practices

- Use private S3 origins with OAC for static content.
- Keep dynamic/API paths in ordered behaviors and disable caching where appropriate.
- Use explicit policy IDs when you need strict cache/request behavior control.
- Keep aliases and ACM cert lifecycle tightly controlled in production.
- Enable logging for production distributions.

---

## 9) Troubleshooting Checklist

- Distribution creation fails with cert/alias error:
  - Ensure aliases are set with an ACM cert in `us-east-1`.
- Ordered behavior origin ID not found:
  - Verify `target_origin_id` exactly matches an origin `origin_id`.
- Signed URL behavior fails:
  - Set `kms_key_arn` and ensure key policy allows public key retrieval path.
- Custom origin validation errors:
  - Ensure `origin_type = "custom"` has `custom_origin_config` and valid protocol/ports.
- Empty logs or no logs:
  - Confirm `logging.bucket` uses correct CloudFront logging bucket format and permissions.
