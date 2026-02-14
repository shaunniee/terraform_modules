# AWS CloudFront Terraform Module

Terraform module for creating a CloudFront distribution with:
- Multiple origins and ordered cache behaviors
- Optional signed URLs using CloudFront key groups
- Optional SPA fallback responses
- Optional custom domain + ACM certificate
- Optional WAF association and access logging

## Required Inputs

| Variable | Type | Required | Notes |
|----------|------|----------|-------|
| `distribution_name` | string | Yes | Name prefix for CloudFront resources |
| `origins` | map(object) | Yes | At least one origin is required |
| `default_cache_behavior` or `default_cache_behaviour` | object | Yes | Use only one; US spelling is preferred |

## Optional Inputs

| Variable | Type | Default | Notes |
|----------|------|---------|-------|
| `comment` | string | `null` | Distribution comment (falls back to `distribution_name`) |
| `tags` | map(string) | `{}` | Tags for supported resources |
| `default_root_object` | string | `index.html` | Must not start with `/` |
| `price_class` | string | `PriceClass_100` | `PriceClass_100`, `PriceClass_200`, `PriceClass_All` |
| `ordered_cache_behavior` | map(object) | `null` | Preferred spelling |
| `ordered_cache_behaviour` | map(object) | `null` | Deprecated spelling |
| `spa_fallback` | bool | `false` | Enable SPA error fallback |
| `spa_fallback_status_codes` | list(number) | `[404]` | Must be within `400-599` |
| `kms_key_arn` | string | `null` | Required if any behavior sets `requires_signed_url = true` |
| `aliases` | list(string) | `[]` | Custom domain names (CNAMEs) |
| `acm_certificate_arn` | string | `null` | Required when `aliases` is non-empty |
| `ssl_support_method` | string | `sni-only` | For custom cert mode |
| `minimum_protocol_version` | string | `TLSv1.2_2021` | For custom cert mode |
| `web_acl_id` | string | `null` | Optional WAF web ACL ARN |
| `logging` | object | `null` | CloudFront access logging config |

## Basic Example

```hcl
module "cloudfront" {
  source = "./aws_cloudfront"

  distribution_name = "my-app-cdn"

  origins = {
    app = {
      domain_name       = "my-app-bucket.s3.us-east-1.amazonaws.com"
      origin_id         = "app-origin"
      is_private_origin = true
    }
  }

  default_cache_behavior = {
    target_origin_id = "app-origin"
  }
}
```

## Example: Custom Domain + WAF + Logging + Tags

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
    }
  }

  default_cache_behavior = {
    target_origin_id = "web-origin"
  }

  ordered_cache_behavior = {
    static_assets = {
      path_pattern        = "/assets/*"
      target_origin_id    = "web-origin"
      allowed_methods     = ["GET", "HEAD", "OPTIONS"]
      cached_methods      = ["GET", "HEAD"]
      cache_disabled      = false
      requires_signed_url = false
    }
  }

  tags = {
    Environment = "production"
    Service     = "frontend"
    ManagedBy   = "terraform"
  }
}
```

## Example: Signed URL Protected Path

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

## Outputs

| Output | Description |
|--------|-------------|
| `cloudfront_domain_name` | Distribution domain name |
| `cloudfront_distribution_id` | Distribution ID |
| `cloudfront_distribution_arn` | Distribution ARN |
| `cloudfront_key_group_id` | Signed URL key group ID (or `null`) |

## Migration Note

New US spellings are supported:
- `default_cache_behavior` (preferred) replaces `default_cache_behaviour`
- `ordered_cache_behavior` (preferred) replaces `ordered_cache_behaviour`

Set only one spelling for each variable family.
