# Route 53 Terraform Module Usage

This module provides a reusable, dynamic way to manage **Route 53 hosted zones, DNS records, aliases, routing policies, and health checks**.

It supports:

- Public and private hosted zones
- Referencing **existing zones** via `existing_zone_ids` (avoids circular dependencies)
- Standard and alias DNS records
- Routing policies: simple (default), weighted, latency, failover, geolocation
- Health checks created and managed inside the module
- Fully dynamic, data-driven configuration for multiple projects

---

## Table of Contents

1. [Module Inputs](#module-inputs)
2. [Module Outputs](#module-outputs)
3. [Basic Examples](#basic-examples)
4. [Multi-Frontend CloudFront Setup](#multi-frontend-cloudfront-setup)
5. [Advanced Usage](#advanced-usage)
   - Blue/Green Deployments
   - Failover with Health Checks
   - Latency-Based Routing
   - Geolocation Routing
   - Private Hosted Zones
6. [Best Practices](#best-practices)

---

## Module Inputs

### `zones` (optional, default `{}`)

Define hosted zones to create. Can be empty when only attaching records to existing zones via `existing_zone_ids`.

```hcl
zones = {
  public = {
    domain_name = "example.com"
    comment     = "Public zone for website"
  }

  private = {
    domain_name = "example.local"
    private     = true
    vpc_ids     = [aws_vpc.main.id]
  }
}
```

Fields:

- `domain_name`: The DNS domain
- `comment`: Optional description
- `private`: Boolean; true if private hosted zone (default `false`)
- `vpc_ids`: List of VPC IDs for private zones (default `[]`)

---

### `existing_zone_ids` (optional, default `{}`)

Map of existing Route 53 zone IDs. Use this to add records to zones created by a separate module call — avoiding circular dependencies when resources like CloudFront or ACM also depend on the zone.

```hcl
existing_zone_ids = {
  main = "Z0123456789ABCDEFGHIJ"
}
```

Keys in this map can be referenced in `records` the same way as keys in `zones`. Created zones take precedence if the same key appears in both.

---

### `records` (optional, default `{}`)

Define DNS records per zone. Zone keys must exist in either `zones` or `existing_zone_ids`.

```hcl
records = {
  public = {
    "www" = {
      type = "A"
      alias = {
        name                   = aws_lb.web.dns_name
        zone_id               = aws_lb.web.zone_id
        evaluate_target_health = true
      }
      # routing_policy defaults to { type = "simple" } — not needed for basic records
    }
  }
}
```

Fields:

- `type`: Record type (`A`, `AAAA`, `CNAME`, `TXT`, `MX`, etc.)
- `ttl`: Optional TTL (automatically ignored for alias records)
- `values`: List of IPs or values (mutually exclusive with `alias`)
- `alias`: Optional alias object (for ALB, NLB, CloudFront, API Gateway, S3, etc.)
- `routing_policy`: Optional routing policy object (defaults to `{ type = "simple" }`)

Routing policy fields:

- `type`: `simple` | `weighted` | `latency` | `failover` | `geolocation`
- `weight`: Required for weighted
- `region`: Required for latency
- `failover`: `PRIMARY` or `SECONDARY`
- `set_identifier`: Required unique ID for weighted, latency, failover, or geolocation records
- `continent`, `country`, `subdivision`: For geolocation routing
- `health_check_id`: Optional health check ID

---

### `health_checks` (optional, default `{}`)

Define health checks to be created by the module:

```hcl
health_checks = {
  api_primary = {
    type              = "HTTPS"
    fqdn              = "api.example.com"
    resource_path     = "/health"
    request_interval  = 30
    failure_threshold = 3
    measure_latency   = false
    regions           = ["us-east-1"]
  }
}
```

Fields:

- `type`: `HTTP` | `HTTPS` | `TCP`
- `fqdn`: Hostname to check
- `port`: Optional port
- `resource_path`: Optional path (e.g. `/health`)
- `request_interval`: Seconds between checks (default `30`)
- `failure_threshold`: Consecutive failures to mark unhealthy (default `3`)
- `measure_latency`: Measure latency (default `false`)
- `inverted`: Invert health check result (default `false`)
- `regions`: Optional list of AWS regions to probe

---

## Module Outputs

| Output | Description |
|--------|-------------|
| `zone_ids` | All zone IDs — both created and externally provided — merged into a single map |
| `created_zone_ids` | Zone IDs for zones created by this module only (excludes `existing_zone_ids`) |
| `name_servers` | Name servers for zones created by this module |
| `health_check_ids` | Health check IDs keyed by health check name |

---

## Basic Examples

### Zone + Simple Alias Record

```hcl
module "dns" {
  source = "./aws_route53"

  zones = {
    public = { domain_name = "example.com" }
  }

  records = {
    public = {
      "www.example.com" = {
        type = "A"
        alias = {
          name                   = aws_lb.web.dns_name
          zone_id                = aws_lb.web.zone_id
          evaluate_target_health = true
        }
      }
    }
  }
}
```

Creates a public hosted zone with one alias record. No `routing_policy` needed — it defaults to `{ type = "simple" }`.

---

### Zone Only (No Records)

```hcl
module "dns_zone" {
  source = "./aws_route53"

  zones = {
    main = {
      domain_name = "example.com"
      comment     = "Primary public zone"
    }
  }
}
```

Creates only the hosted zone. Records can be added later in a separate module call using `existing_zone_ids`.

---

### Records Only (Existing Zone)

```hcl
module "dns_records" {
  source = "./aws_route53"

  existing_zone_ids = {
    main = module.dns_zone.zone_ids["main"]
  }

  records = {
    main = {
      "app.example.com" = {
        type = "A"
        alias = {
          name                   = aws_lb.app.dns_name
          zone_id                = aws_lb.app.zone_id
          evaluate_target_health = true
        }
      }
    }
  }
}
```

Adds records to a zone that already exists — no zone creation, no duplicate zone errors.

---

### Standard (Non-Alias) Records

```hcl
records = {
  main = {
    "example.com" = {
      type   = "MX"
      ttl    = 300
      values = ["10 mail1.example.com", "20 mail2.example.com"]
    }

    "example.com-txt" = {
      type   = "TXT"
      ttl    = 300
      values = ["v=spf1 include:_spf.google.com ~all"]
    }
  }
}
```

---

## Multi-Frontend CloudFront Setup

A common pattern: **two frontends** (public site + admin CMS) served via separate CloudFront distributions on a single apex domain, with subdomains.

| Frontend | Domain | CloudFront |
|----------|--------|------------|
| Public | `example.com` + `www.example.com` | CF Distribution 1 |
| Admin CMS | `admin.example.com` | CF Distribution 2 |

### The Dependency Challenge

The naive approach creates a circular dependency:

```
Route 53 (zone + records) → needs CF outputs
         ↑                        ↓
        ACM ←──────────── CloudFront
     (needs zone_id)    (needs cert ARN)
```

The solution: **two module calls** — one for the zone, one for the records.

```
dns_zone → ACM → CloudFront (public + admin) → dns_records
                                                    ↑
                                          uses existing_zone_ids
```

### Complete Example

```hcl
# =============================================================================
# Providers
# =============================================================================

provider "aws" {
  region = "ap-southeast-1"     # Primary region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"          # ACM certs for CloudFront MUST be in us-east-1
}

# =============================================================================
# STEP 1: Route 53 — Create the hosted zone only
# =============================================================================

module "dns_zone" {
  source = "./aws_route53"

  zones = {
    main = {
      domain_name = "example.com"
      comment     = "Primary public zone"
    }
  }
}

# =============================================================================
# STEP 2: ACM — Wildcard + apex certificate (us-east-1)
# =============================================================================

module "acm" {
  source = "./aws_acm"

  providers = {
    aws = aws.us_east_1
  }

  certificates = [
    {
      domain_name       = "example.com"
      san               = ["*.example.com"]
      validation_method = "DNS"
      zone_id           = module.dns_zone.zone_ids["main"]
    }
  ]
}

# =============================================================================
# STEP 3: S3 — Origin buckets
# =============================================================================

module "s3_public" {
  source = "./aws_s3"
  # ... public frontend bucket config
}

module "s3_admin" {
  source = "./aws_s3"
  # ... admin CMS bucket config
}

# =============================================================================
# STEP 4: CloudFront — Two distributions
# =============================================================================

module "cf_public" {
  source = "./aws_cloudfront"

  distribution_name   = "public-frontend"
  comment             = "Public website — example.com"
  default_root_object = "index.html"
  aliases             = ["example.com", "www.example.com"]
  acm_certificate_arn = module.acm.validated_certificate_arns["example.com"]

  origins = {
    s3 = {
      domain_name       = module.s3_public.bucket_regional_domain_name
      origin_id         = "s3-public-frontend"
      is_private_origin = true
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3-public-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  spa_fallback              = true
  spa_fallback_status_codes = [403, 404]
}

module "cf_admin" {
  source = "./aws_cloudfront"

  distribution_name   = "admin-cms"
  comment             = "Admin CMS — admin.example.com"
  default_root_object = "index.html"
  aliases             = ["admin.example.com"]
  acm_certificate_arn = module.acm.validated_certificate_arns["example.com"]

  origins = {
    s3 = {
      domain_name       = module.s3_admin.bucket_regional_domain_name
      origin_id         = "s3-admin-cms"
      is_private_origin = true
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3-admin-cms"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  spa_fallback              = true
  spa_fallback_status_codes = [403, 404]
}

# =============================================================================
# STEP 5: Route 53 — Alias records (uses existing zone from step 1)
# =============================================================================

module "dns_records" {
  source = "./aws_route53"

  existing_zone_ids = {
    main = module.dns_zone.zone_ids["main"]
  }

  records = {
    main = {

      # Apex → public CF
      "example.com" = {
        type = "A"
        alias = {
          name                   = module.cf_public.cloudfront_domain_name
          zone_id                = module.cf_public.cloudfront_hosted_zone_id
          evaluate_target_health = false
        }
      }

      # www → public CF
      "www.example.com" = {
        type = "A"
        alias = {
          name                   = module.cf_public.cloudfront_domain_name
          zone_id                = module.cf_public.cloudfront_hosted_zone_id
          evaluate_target_health = false
        }
      }

      # admin → admin CF
      "admin.example.com" = {
        type = "A"
        alias = {
          name                   = module.cf_admin.cloudfront_domain_name
          zone_id                = module.cf_admin.cloudfront_hosted_zone_id
          evaluate_target_health = false
        }
      }

      # IPv6 variants (CloudFront enables IPv6 by default)

      "example.com-ipv6" = {
        type = "AAAA"
        alias = {
          name                   = module.cf_public.cloudfront_domain_name
          zone_id                = module.cf_public.cloudfront_hosted_zone_id
          evaluate_target_health = false
        }
      }

      "www.example.com-ipv6" = {
        type = "AAAA"
        alias = {
          name                   = module.cf_public.cloudfront_domain_name
          zone_id                = module.cf_public.cloudfront_hosted_zone_id
          evaluate_target_health = false
        }
      }

      "admin.example.com-ipv6" = {
        type = "AAAA"
        alias = {
          name                   = module.cf_admin.cloudfront_domain_name
          zone_id                = module.cf_admin.cloudfront_hosted_zone_id
          evaluate_target_health = false
        }
      }
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "name_servers" {
  description = "Set these at your domain registrar"
  value       = module.dns_zone.name_servers["main"]
}

output "public_cf_domain" {
  value = module.cf_public.cloudfront_domain_name
}

output "admin_cf_domain" {
  value = module.cf_admin.cloudfront_domain_name
}
```

### How It Avoids Circular Dependencies

| Step | Module | Creates | Depends On |
|------|--------|---------|------------|
| 1 | `dns_zone` | Hosted zone | Nothing |
| 2 | `acm` | Certificate + DNS validation records | Zone ID from step 1 |
| 3 | `s3_public` / `s3_admin` | S3 buckets | Nothing |
| 4 | `cf_public` / `cf_admin` | CloudFront distributions | Cert ARN from step 2, S3 from step 3 |
| 5 | `dns_records` | Alias records | CF outputs from step 4, zone ID from step 1 via `existing_zone_ids` |

### Key Details

- **One ACM cert** with `example.com` + SAN `*.example.com` covers all subdomains
- **Provider alias** `aws.us_east_1` ensures the cert is in us-east-1 (CloudFront requirement)
- **`existing_zone_ids`** passes the zone from step 1 into step 5 without recreating it
- **`routing_policy`** is omitted on all records — defaults to `{ type = "simple" }`
- **AAAA records** are included because CloudFront serves IPv6 by default
- **`is_private_origin = true`** enables OAC on CloudFront — blocks direct S3 access
- After `terraform apply`, update your **domain registrar NS records** to match the output

---

## Advanced Usage

### 1. Blue/Green Deployments

Weighted routing to gradually shift traffic:

```hcl
records = {
  public = {
    "api.example.com-blue" = {
      type = "A"
      alias = {
        name    = aws_lb.blue.dns_name
        zone_id = aws_lb.blue.zone_id
      }
      routing_policy = {
        type           = "weighted"
        weight         = 90
        set_identifier = "blue"
      }
    }
    "api.example.com-green" = {
      type = "A"
      alias = {
        name    = aws_lb.green.dns_name
        zone_id = aws_lb.green.zone_id
      }
      routing_policy = {
        type           = "weighted"
        weight         = 10
        set_identifier = "green"
      }
    }
  }
}
```

Adjust `weight` values to control traffic split.

---

### 2. Failover with Health Checks

```hcl
health_checks = {
  api_primary = {
    type          = "HTTPS"
    fqdn          = "api.example.com"
    resource_path = "/health"
  }
}

records = {
  public = {
    "api.example.com-primary" = {
      type = "A"
      alias = {
        name    = aws_lb.primary.dns_name
        zone_id = aws_lb.primary.zone_id
      }
      routing_policy = {
        type            = "failover"
        failover        = "PRIMARY"
        set_identifier  = "primary"
        health_check_id = module.dns.health_check_ids["api_primary"]
      }
    }
    "api.example.com-secondary" = {
      type = "A"
      alias = {
        name    = aws_lb.secondary.dns_name
        zone_id = aws_lb.secondary.zone_id
      }
      routing_policy = {
        type           = "failover"
        failover       = "SECONDARY"
        set_identifier = "secondary"
      }
    }
  }
}
```

Automatic DNS failover when the primary is unhealthy.

---

### 3. Latency-Based Routing

```hcl
records = {
  public = {
    "app.example.com-eu" = {
      type = "A"
      alias = {
        name    = aws_lb.eu.dns_name
        zone_id = aws_lb.eu.zone_id
      }
      routing_policy = {
        type           = "latency"
        region         = "eu-west-1"
        set_identifier = "eu"
      }
    }
    "app.example.com-us" = {
      type = "A"
      alias = {
        name    = aws_lb.us.dns_name
        zone_id = aws_lb.us.zone_id
      }
      routing_policy = {
        type           = "latency"
        region         = "us-east-1"
        set_identifier = "us"
      }
    }
  }
}
```

Users are routed to the **nearest healthy region**.

---

### 4. Geolocation Routing

```hcl
records = {
  public = {
    "portal.example.com-eu" = {
      type = "A"
      alias = {
        name    = aws_lb.eu.dns_name
        zone_id = aws_lb.eu.zone_id
      }
      routing_policy = {
        type           = "geolocation"
        continent      = "EU"
        set_identifier = "eu"
      }
    }
    "portal.example.com-default" = {
      type = "A"
      alias = {
        name    = aws_lb.default.dns_name
        zone_id = aws_lb.default.zone_id
      }
      routing_policy = {
        type           = "geolocation"
        country        = "*"
        set_identifier = "default"
      }
    }
  }
}
```

Serve EU users from EU infrastructure; everyone else hits the default.

---

### 5. Private Hosted Zones

```hcl
module "dns" {
  source = "./aws_route53"

  zones = {
    private = {
      domain_name = "example.local"
      private     = true
      vpc_ids     = [aws_vpc.main.id]
    }
  }

  records = {
    private = {
      "db.example.local" = {
        type   = "CNAME"
        ttl    = 30
        values = ["aurora.cluster.local"]
      }
    }
  }
}
```

DNS inside a VPC only; internal services stay private.

---

### 6. Apex Domain Alias (CloudFront)

```hcl
records = {
  public = {
    "example.com" = {
      type = "A"
      alias = {
        name    = module.cf.cloudfront_domain_name
        zone_id = module.cf.cloudfront_hosted_zone_id
      }
    }
  }
}
```

Root domain points directly to CloudFront. No `routing_policy` needed — defaults to simple.

---

## Best Practices

- **Split zone and records** into separate module calls when downstream resources (ACM, CloudFront) depend on the zone — use `existing_zone_ids` for records.
- Prefer **module-managed health checks** for consistency.
- Always use **`set_identifier`** for weighted, failover, latency, or geolocation records.
- Keep **TTL short** for dynamic failover scenarios.
- Use **alias records** where possible to avoid managing IPs and to get free health checks.
- For private hosted zones, always attach **all VPCs that need DNS resolution**.
- Add **AAAA (IPv6) alias records** alongside A records when targeting CloudFront or ALBs.
- For CloudFront certificates, always provision ACM in **us-east-1** using a provider alias.

