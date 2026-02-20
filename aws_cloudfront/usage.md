# AWS CloudFront Terraform Module - Complete Guide

Reusable Terraform module for provisioning CloudFront distributions with support for S3 and custom origins, path-based behaviors, signed URLs, SPA fallback, custom domains, WAF, logging, Lambda@Edge, geo-restriction, origin groups (failover), and full observability (default alarms + dashboard).

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
- `aws_cloudwatch_metric_alarm.cloudfront` (default + custom alarms when observability enabled)
- `aws_cloudwatch_dashboard.this` (when observability + dashboard enabled)
- `aws_cloudfront_monitoring_subscription.this` (when realtime metrics enabled)
- `aws_cloudfront_realtime_log_config.this` (when realtime logging configured)
- Supporting data lookups for managed cache/origin request policies

---

## 2) Prerequisites

- Terraform `>= 1.5`
- AWS provider `>= 5.0`
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

### Scenario G: Keep `/api/*` Path and Rewrite Before API Gateway

Use a CloudFront Function on the `/api/*` behavior to strip the `/api` prefix before forwarding to API Gateway.

```hcl
resource "aws_cloudfront_function" "strip_api_prefix" {
  name    = "strip-api-prefix"
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = <<-JS
function handler(event) {
  var request = event.request;
  if (request.uri.indexOf('/api/') === 0) {
    request.uri = request.uri.substring(4);
  }
  return request;
}
JS
}

module "cloudfront_api_rewrite" {
  source = "./aws_cloudfront"

  distribution_name = "frontend-api-cdn"

  origins = {
    static = {
      domain_name       = "frontend-assets.s3.us-east-1.amazonaws.com"
      origin_id         = "static-origin"
      is_private_origin = false
      origin_type       = "s3"
    }

    api = {
      domain_name       = "abc123.execute-api.us-east-1.amazonaws.com"
      origin_id         = "api-origin"
      is_private_origin = false
      origin_type       = "custom"
      origin_path       = "/prod"
      custom_origin_config = {
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
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

      function_associations = {
        rewrite_api_prefix = {
          event_type   = "viewer-request"
          function_arn = aws_cloudfront_function.strip_api_prefix.arn
        }
      }
    }
  }
}
```

With this setup, `/api/users` on CloudFront is forwarded to `/users` on API Gateway stage `/prod`.

---

### Scenario H: Observability (Logging, Metrics, Alarms)

```hcl
module "cloudfront_observability" {
  source = "./aws_cloudfront"

  distribution_name = "frontend-observability-cdn"

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

  logging = {
    bucket          = "my-cloudfront-logs.s3.amazonaws.com"
    include_cookies = false
    prefix          = "frontend-observability/"
  }

  realtime_log_config = {
    sampling_rate = 100
    fields = [
      "timestamp",
      "c-ip",
      "cs-method",
      "cs-uri-stem",
      "sc-status",
      "time-to-first-byte"
    ]
    endpoints = [
      {
        role_arn   = "arn:aws:iam::123456789012:role/cloudfront-realtime-logs"
        stream_arn = "arn:aws:kinesis:us-east-1:123456789012:stream/cloudfront-realtime-logs"
      }
    ]
  }

  realtime_metrics_subscription_enabled = true

  cloudwatch_metric_alarms = {
    high_5xx_rate = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 5
      metric_name         = "5xxErrorRate"
      period              = 60
      statistic           = "Average"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }
}
```

Notes:
- CloudFront does not provide X-Ray-style tracing; use logs + metrics + alarms for observability.
- Alarm dimensions default to `DistributionId` and `Region=Global`.

---

### Scenario I: Origin Groups (Failover)

```hcl
module "cloudfront_failover" {
  source = "./aws_cloudfront"

  distribution_name = "resilient-cdn"

  origins = {
    primary = {
      domain_name       = "primary-assets.s3.us-east-1.amazonaws.com"
      origin_id         = "primary-s3"
      is_private_origin = true
      origin_type       = "s3"
    }
    failover = {
      domain_name       = "failover-assets.s3.us-west-2.amazonaws.com"
      origin_id         = "failover-s3"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  origin_groups = {
    s3_failover = {
      primary_origin_id     = "primary-s3"
      failover_origin_id    = "failover-s3"
      failover_status_codes = [500, 502, 503, 504]
    }
  }

  default_cache_behavior = {
    target_origin_id = "primary-s3"  # matches origin group primary
  }
}
```

Notes:
- Primary and failover origin IDs must reference origins defined in `origins`.
- Valid failover status codes: `400`, `403`, `404`, `416`, `500`, `502`, `503`, `504`.

---

### Scenario J: Geo-Restriction

```hcl
# Whitelist: only allow traffic from specific countries
module "cloudfront_geo_whitelist" {
  source = "./aws_cloudfront"

  distribution_name = "eu-only-cdn"

  origins = {
    web = {
      domain_name       = "eu-assets.s3.eu-west-1.amazonaws.com"
      origin_id         = "eu-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "eu-origin"
  }

  geo_restriction = {
    restriction_type = "whitelist"
    locations        = ["DE", "FR", "GB", "NL", "IT", "ES"]
  }
}

# Blacklist: block traffic from specific countries
module "cloudfront_geo_blacklist" {
  source = "./aws_cloudfront"

  distribution_name = "restricted-cdn"

  origins = {
    web = {
      domain_name       = "assets.s3.us-east-1.amazonaws.com"
      origin_id         = "web-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "web-origin"
  }

  geo_restriction = {
    restriction_type = "blacklist"
    locations        = ["CN", "RU"]
  }
}
```

Notes:
- Country codes must be ISO 3166-1-alpha-2 (uppercase, two letters: `US`, `GB`, `DE`, etc.).
- When `restriction_type` is `"none"` (default), `locations` is ignored.

---

### Scenario K: Lambda@Edge

```hcl
module "cloudfront_lambda_edge" {
  source = "./aws_cloudfront"

  distribution_name = "ssr-cdn"

  origins = {
    s3 = {
      domain_name       = "app-assets.s3.us-east-1.amazonaws.com"
      origin_id         = "s3-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "s3-origin"
    lambda_function_associations = {
      ssr = {
        event_type   = "origin-request"
        lambda_arn   = "arn:aws:lambda:us-east-1:123456789012:function:ssr-renderer:5"
        include_body = false
      }
    }
  }

  ordered_cache_behavior = {
    auth_check = {
      path_pattern       = "/protected/*"
      target_origin_id   = "s3-origin"
      allowed_methods    = ["GET", "HEAD", "OPTIONS"]
      cached_methods     = ["GET", "HEAD"]
      cache_disabled     = false
      requires_signed_url = false
      lambda_function_associations = {
        auth = {
          event_type   = "viewer-request"
          lambda_arn   = "arn:aws:lambda:us-east-1:123456789012:function:auth-at-edge:3"
          include_body = false
        }
      }
    }
  }
}
```

Notes:
- Lambda@Edge functions must be deployed in `us-east-1` and use a versioned ARN (not `$LATEST`).
- Valid `event_type` values: `viewer-request`, `viewer-response`, `origin-request`, `origin-response`.
- `include_body = true` is only supported for `viewer-request` and `origin-request`.

---

### Scenario L: Custom Error Responses

```hcl
module "cloudfront_error_pages" {
  source = "./aws_cloudfront"

  distribution_name = "branded-errors-cdn"

  origins = {
    web = {
      domain_name       = "assets.s3.us-east-1.amazonaws.com"
      origin_id         = "web-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "web-origin"
  }

  custom_error_responses = {
    not_found = {
      error_code            = 404
      response_code         = 404
      response_page_path    = "/errors/404.html"
      error_caching_min_ttl = 300
    }
    server_error = {
      error_code            = 500
      response_code         = 500
      response_page_path    = "/errors/500.html"
      error_caching_min_ttl = 60
    }
    forbidden = {
      error_code            = 403
      response_code         = 403
      response_page_path    = "/errors/403.html"
      error_caching_min_ttl = 300
    }
  }
}
```

Notes:
- `custom_error_responses` are applied in addition to any SPA fallback error responses.
- `response_page_path` must start with `/` and reference a file served by one of your origins.
- `error_caching_min_ttl` is in seconds; use short TTLs for transient 5xx errors.

---

### Scenario M: Observability with Default Alarms + Dashboard

```hcl
# Minimal: enable defaults with one line
module "cloudfront_observable" {
  source = "./aws_cloudfront"

  distribution_name = "frontend-cdn"

  origins = {
    web = {
      domain_name       = "frontend.s3.us-east-1.amazonaws.com"
      origin_id         = "web-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "web-origin"
  }

  observability = {
    enabled = true
  }
}

# Full: custom thresholds + alarm actions + additional manual alarms
module "cloudfront_full_observability" {
  source = "./aws_cloudfront"

  distribution_name = "frontend-prod-cdn"

  origins = {
    web = {
      domain_name       = "frontend.s3.us-east-1.amazonaws.com"
      origin_id         = "web-origin"
      is_private_origin = true
      origin_type       = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id = "web-origin"
  }

  observability = {
    enabled               = true
    enable_default_alarms = true
    enable_dashboard      = true

    error_5xx_rate_threshold = 3     # alarm at 3% 5xx (default: 5%)
    error_4xx_rate_threshold = 10    # alarm at 10% 4xx (default: 15%)
    origin_latency_threshold = 3     # alarm at 3s latency (default: 5s)

    default_alarm_actions             = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    default_ok_actions                = ["arn:aws:sns:us-east-1:123456789012:ops-ok"]
    default_insufficient_data_actions = []
  }

  # Additional custom alarm (merged; user keys override defaults on collision)
  cloudwatch_metric_alarms = {
    cache_hit_rate_low = {
      comparison_operator = "LessThanThreshold"
      evaluation_periods  = 5
      metric_name         = "CacheHitRate"
      period              = 300
      statistic           = "Average"
      threshold           = 80
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }
}
```

Notes:
- `observability.enabled = true` creates 3 default alarms (high 5xx rate, high 4xx rate, high origin latency) and an 8-widget CloudWatch dashboard.
- Custom alarms in `cloudwatch_metric_alarms` are merged with defaults; if a key matches a default alarm name, the custom version wins.
- Dashboard widgets: Requests, Cache Hit Rate, 4xx Error Rate, 5xx Error Rate, Bytes Downloaded, Bytes Uploaded, Origin Latency, Total Error Rate.
- All CloudFront metrics are in `us-east-1` with `Region=Global` dimension.

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
| `acm_certificate_arn` | string | `null` | Conditional | Required when aliases are set; must be `us-east-1` cert |
| `ssl_support_method` | string | `sni-only` | No | `sni-only`, `vip`, or `static-ip` |
| `minimum_protocol_version` | string | `TLSv1.2_2021` | No | Viewer TLS policy |

### Logging Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `logging` | object | `null` | No | Access logging config `{ bucket, include_cookies, prefix }` |

### Observability Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `observability` | object | `{}` | No | Master observability config (see schema below) |
| `cloudwatch_metric_alarms` | map(object) | `{}` | No | Custom CloudWatch metric alarms (merged with defaults) |
| `realtime_log_config` | object | `null` | No | Real-time logging config with Kinesis endpoints |
| `realtime_metrics_subscription_enabled` | bool | `false` | No | Enables CloudFront real-time metrics subscription |

`observability` object schema:

```hcl
observability = {
  enabled               = optional(bool, false)    # master switch
  enable_default_alarms = optional(bool, true)      # create 3 default alarms
  enable_dashboard      = optional(bool, true)      # create CloudWatch dashboard

  error_5xx_rate_threshold = optional(number, 5)    # 5xx rate % alarm threshold
  error_4xx_rate_threshold = optional(number, 15)   # 4xx rate % alarm threshold
  origin_latency_threshold = optional(number, 5)    # origin latency in seconds

  default_alarm_actions             = optional(list(string), [])
  default_ok_actions                = optional(list(string), [])
  default_insufficient_data_actions = optional(list(string), [])
}
```

Default alarms created when `observability.enabled = true` and `enable_default_alarms = true`:

| Alarm Key | Metric | Statistic | Threshold | Periods | Period |
|-----------|--------|-----------|-----------|---------|--------|
| `high_5xx_error_rate` | `5xxErrorRate` | Average | `error_5xx_rate_threshold` (5%) | 3 | 300s |
| `high_4xx_error_rate` | `4xxErrorRate` | Average | `error_4xx_rate_threshold` (15%) | 3 | 300s |
| `high_origin_latency` | `OriginLatency` | Average | `origin_latency_threshold` × 1000 (5000ms) | 3 | 300s |

### Origin Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `origins` | map(object) | - | Yes | Origin definitions (at least one) |
| `origin_groups` | map(object) | `{}` | No | Origin groups for failover (see schema below) |

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

`origin_groups` object schema:

```hcl
origin_groups = {
  key = {
    primary_origin_id     = string
    failover_origin_id    = string
    failover_status_codes = optional(list(number), [500, 502, 503, 504])
  }
}
```

Notes:
- `origin_type = "s3"` works with S3 origins (public or private).
- `is_private_origin = true` is supported only for S3 origins.
- `origin_type = "custom"` requires `custom_origin_config`.
- `origin_groups`: primary and failover must be different origins. Valid failover codes: `400`, `403`, `404`, `416`, `500`, `502`, `503`, `504`.

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
  target_origin_id           = string
  viewer_protocol_policy     = optional(string, "redirect-to-https")
  allowed_methods            = optional(list(string), ["GET", "HEAD", "OPTIONS"])
  cached_methods             = optional(list(string), ["GET", "HEAD"])
  cache_policy_id            = optional(string)
  origin_request_policy_id   = optional(string)
  response_headers_policy_id = optional(string)
  function_associations      = optional(map(object({...})), {})
  lambda_function_associations = optional(map(object({
    event_type   = string          # viewer-request, viewer-response, origin-request, origin-response
    lambda_arn   = string          # must be versioned ARN (not $LATEST)
    include_body = optional(bool, false)
  })), {})
}
```

`ordered_cache_behavior` / `ordered_cache_behaviour` item schema:

```hcl
{
  path_pattern               = string
  target_origin_id           = string
  allowed_methods            = list(string)
  cached_methods             = list(string)
  viewer_protocol_policy     = optional(string, "redirect-to-https")
  cache_policy_id            = optional(string)
  origin_request_policy_id   = optional(string)
  response_headers_policy_id = optional(string)
  cache_disabled             = bool
  requires_signed_url        = bool
  function_associations      = optional(map(object({...})), {})
  lambda_function_associations = optional(map(object({
    event_type   = string
    lambda_arn   = string
    include_body = optional(bool, false)
  })), {})
}
```

Behavior precedence for policy IDs:
- If `cache_policy_id` is set in behavior input, it is used.
- Otherwise:
  - `cache_disabled = true` => managed `CachingDisabled`
  - `cache_disabled = false` => managed `CachingOptimized`
- If `origin_request_policy_id` is not set, managed `CORS-S3Origin` is used.

### Geo-Restriction Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `geo_restriction` | object | `{}` | No | Geo-restriction config (see schema below) |

```hcl
geo_restriction = {
  restriction_type = optional(string, "none")   # none, whitelist, or blacklist
  locations        = optional(list(string), [])  # ISO 3166-1-alpha-2 codes
}
```

### Custom Error Response Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `custom_error_responses` | map(object) | `{}` | No | Custom error response pages and TTLs |

```hcl
custom_error_responses = {
  key = {
    error_code            = number            # 400–599
    response_code         = optional(number)
    response_page_path    = optional(string)  # must start with /
    error_caching_min_ttl = optional(number)  # seconds
  }
}
```

### SPA / Signed URL Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `spa_fallback` | bool | `false` | No | Enables SPA fallback error responses |
| `spa_fallback_status_codes` | list(number) | `[404]` | No | Error codes converted to `200` with default root object |
| `kms_key_arn` | string | `null` | Conditional | Required when any ordered behavior sets `requires_signed_url = true` |

---

## 5) Validation Rules Enforced by Module

### Core / Distribution
- `distribution_name` must match allowed format/length.
- `default_root_object` must be non-empty and not start with `/`.
- `price_class` must be one of `PriceClass_100`, `PriceClass_200`, `PriceClass_All`.
- `aliases` cannot contain empty values.
- `acm_certificate_arn` must be a valid ARN when set.
- When aliases are configured, `acm_certificate_arn` must be provided and in `us-east-1`.

### Origins
- `origins` must contain at least one origin.
- Every origin must have non-empty `domain_name` and `origin_id`.
- `origin_id` values must be unique across all origins.
- `origins[*].origin_type` must be `s3` or `custom`.
- `custom_origin_config` is required for `origin_type = "custom"`.
- `is_private_origin = true` is allowed only for `origin_type = "s3"`.
- Custom origin protocol, SSL, timeout, and port values are validated.
- `origin_groups`: `primary_origin_id` and `failover_origin_id` must be different.
- `origin_groups.failover_status_codes` must be valid CloudFront failover codes: `400`, `403`, `404`, `416`, `500`, `502`, `503`, `504`.

### Cache Behaviors
- Exactly one spelling variant can be used for each behavior family.
- One default behavior is required (preferred or deprecated spelling).
- All behavior `target_origin_id` values must reference a defined origin.
- `ordered_cache_behavior.path_pattern` must start with `/` and be unique.
- Allowed/cached methods are validated; cached methods must be a subset of allowed.
- If any ordered behavior sets `requires_signed_url = true`, `kms_key_arn` is required.

### Geo-Restriction
- `geo_restriction.restriction_type` must be `none`, `whitelist`, or `blacklist`.
- `geo_restriction.locations` must be non-empty when `restriction_type` is `whitelist` or `blacklist`.
- `geo_restriction.locations` must be ISO 3166-1-alpha-2 country codes (e.g., `US`, `GB`, `DE`).

### Custom Error Responses
- `custom_error_responses[*].error_code` must be `400`–`599`.
- `custom_error_responses[*].response_page_path` must start with `/` when provided.

### SPA / Signed URLs
- SPA fallback status codes must be in `400..599`.

### Observability / Alarms
- `observability.default_alarm_actions` ARNs must start with `arn:`.
- `observability.default_ok_actions` ARNs must start with `arn:`.
- `observability.default_insufficient_data_actions` ARNs must start with `arn:`.
- `observability.error_5xx_rate_threshold` must be `0`–`100`.
- `observability.error_4xx_rate_threshold` must be `0`–`100`.
- `observability.origin_latency_threshold` must be `> 0`.
- `cloudwatch_metric_alarms[*].comparison_operator` must be a valid CloudWatch operator.
- `cloudwatch_metric_alarms[*].evaluation_periods` must be `>= 1`.
- `cloudwatch_metric_alarms[*].period` must be `>= 10` seconds.
- `cloudwatch_metric_alarms` entries must set exactly one of `statistic` or `extended_statistic`.

### Real-Time Logging
- `realtime_log_config.sampling_rate` must be between `1` and `100`.
- `realtime_log_config.endpoints` must be non-empty and use valid IAM role/Kinesis stream ARNs.

---

## 6) Outputs Reference

| Output | Type | Description |
|--------|------|-------------|
| `cloudfront_domain_name` | string | Distribution domain name (e.g., `d111111abcdef8.cloudfront.net`) |
| `cloudfront_distribution_id` | string | Distribution ID |
| `cloudfront_distribution_arn` | string | Distribution ARN |
| `cloudfront_hosted_zone_id` | string | Route53 hosted zone ID for alias records |
| `cloudfront_etag` | string | Current ETag (needed for invalidations and imports) |
| `cloudfront_status` | string | Deployment status (`Deployed`, `InProgress`) |
| `cloudfront_key_group_id` | string | Signed URL key group ID, or `null` |
| `cloudwatch_metric_alarm_arns` | map(string) | Map of alarm ARNs (default + custom) keyed by alarm key |
| `cloudwatch_metric_alarm_names` | map(string) | Map of alarm names (default + custom) keyed by alarm key |
| `dashboard_arn` | string | CloudWatch dashboard ARN, or `null` if disabled |
| `dashboard_name` | string | CloudWatch dashboard name, or `null` if disabled |
| `realtime_log_config_arn` | string | Real-time log config ARN, or `null` |
| `realtime_log_config_name` | string | Real-time log config name, or `null` |
| `realtime_metrics_subscription_enabled` | bool | Whether real-time metrics subscription is enabled |
| `observability_summary` | object | `{ enabled, alarm_count, alarm_keys, dashboard_name }` |

---

## 7) Behavior Notes

- Default behavior and ordered behaviors support both legacy British and preferred US spelling inputs.
- For private S3 origins, module creates CloudFront OAC and attaches it automatically.
- Signed URL support is enabled per ordered behavior using `requires_signed_url = true`.
- `viewer_certificate` uses default CloudFront cert when `acm_certificate_arn` is unset.
- `response_headers_policy_id` can be set on both default and ordered behaviors for security headers, CORS, etc.
- `lambda_function_associations` on behaviors support `viewer-request`, `viewer-response`, `origin-request`, and `origin-response` event types. Lambda@Edge functions must be deployed in `us-east-1` with a versioned ARN.
- `custom_error_responses` are applied in addition to SPA fallback responses (if both are configured).
- `origin_groups` enable automatic failover between two origins when specified HTTP status codes are returned.
- When `observability.enabled = true`, 3 default alarms and an 8-widget dashboard are created. Custom alarms from `cloudwatch_metric_alarms` are merged; if a custom alarm key matches a default alarm key, the custom version wins.

---

## 8) Best Practices

- Use private S3 origins with OAC for static content — never use public buckets in production.
- Keep dynamic/API paths in ordered behaviors and disable caching where appropriate.
- Use explicit policy IDs when you need strict cache/request/response behavior control.
- Set `response_headers_policy_id` for security headers (CSP, HSTS, X-Frame-Options).
- Keep aliases and ACM cert lifecycle tightly controlled in production.
- Enable access logging for all production distributions.
- Enable `observability = { enabled = true }` for production — gives you 5xx, 4xx, and latency alarms plus a dashboard out of the box.
- Configure `origin_groups` for critical distributions to get automatic failover.
- Use geo-restriction for compliance (e.g., GDPR data residency).
- Use Lambda@Edge sparingly — it adds cold-start latency at edge locations; prefer CloudFront Functions for lightweight request/response transformations.
- Set `error_caching_min_ttl` on custom error responses: short for 5xx (transient), longer for 4xx (likely permanent).
- Use `kms_key_arn` and signed URLs only for paths that truly need access control.

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
- Default alarms not created:
  - Verify `observability.enabled = true`. Check `observability.enable_default_alarms` is not `false`.
- Dashboard not appearing:
  - Dashboard is created in the provider's default region. CloudFront metrics are only available when viewing the dashboard from `us-east-1`.
- Origin group failover not working:
  - Ensure `failover_status_codes` includes the HTTP status codes the origin actually returns.
- Lambda@Edge deployment errors:
  - Function must be in `us-east-1` and use a numbered version ARN (not `$LATEST`).
- Geo-restriction not blocking traffic:
  - Verify country codes are uppercase ISO 3166-1-alpha-2 format and `restriction_type` is set correctly.
