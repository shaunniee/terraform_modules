# Route 53 Terraform Module Usage

This module provides a reusable, dynamic way to manage **Route 53 hosted zones, DNS records, aliases, routing policies, and health checks**.  

It supports:

- Public and private hosted zones
- Standard and alias DNS records
- Routing policies: simple, weighted, latency, failover, geolocation
- Health checks created and managed inside the module
- Fully dynamic, data-driven configuration for multiple projects

---

## Table of Contents

1. [Module Inputs](#module-inputs)  
2. [Module Outputs](#module-outputs)  
3. [Basic Example](#basic-example)  
4. [Advanced Usage](#advanced-usage)  
   - Blue/Green Deployments  
   - Failover with Health Checks  
   - Latency-Based Routing  
   - Geolocation Routing  
   - Private Hosted Zones  
5. [Best Practices](#best-practices)  

---

## Module Inputs

### `zones` (required)

Define hosted zones:

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
- `private`: Boolean; true if private hosted zone
- `vpc_ids`: List of VPC IDs for private zones

---

### `records` (required)

Define DNS records per zone:

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
      routing_policy = {
        type           = "weighted"
        weight         = 100
        set_identifier = "www-main"
      }
    }
  }
}
```

Fields:

- `type`: Record type (`A`, `AAAA`, `CNAME`, `TXT`, etc.)
- `ttl`: Optional TTL (ignored for alias records)
- `values`: List of IPs or values
- `alias`: Optional alias object (for ALB, NLB, CloudFront, API Gateway)
- `routing_policy`: Optional routing policy object

Routing policy fields:

- `type`: simple, weighted, latency, failover, geolocation
- `weight`: Required for weighted
- `region`: Required for latency
- `failover`: PRIMARY or SECONDARY
- `set_identifier`: Unique ID per record for routing policy
- `continent`, `country`, `subdivision`: For geolocation routing
- `health_check_id`: Optional health check ID (for failover)

---

### `health_checks` (optional)

Define health checks to be created by the module:

```hcl
health_checks = {
  api_primary = {
    type          = "HTTPS"
    fqdn          = "api.example.com"
    resource_path = "/health"
    request_interval  = 30
    failure_threshold = 3
    measure_latency   = false
    regions           = ["us-east-1"]
  }
}
```

Fields:

- `type`: HTTP, HTTPS, TCP
- `fqdn`: Hostname to check
- `port`: Optional port
- `resource_path`: Optional path (`/health`)
- `request_interval`: Optional, seconds between checks
- `failure_threshold`: Optional, consecutive failures to mark unhealthy
- `measure_latency`: Optional, measure latency
- `regions`: Optional, AWS regions to probe

---

## Module Outputs

```hcl
output "zone_ids"         # map of zone key => zone ID
output "name_servers"     # map of zone key => NS records
output "health_check_ids" # map of health check key => health check ID
```

---

## Basic Example

```hcl
module "dns" {
  source = "./route53"

  zones = {
    public = { domain_name = "example.com" }
  }

  records = {
    public = {
      "www" = {
        type = "A"
        alias = {
          name                   = aws_lb.web.dns_name
          zone_id               = aws_lb.web.zone_id
          evaluate_target_health = true
        }
      }
    }
  }
}
```

Creates a public hosted zone with one `www` alias record pointing to an ALB.

---

## Advanced Usage

### 1. Blue/Green Deployments

Weighted routing:

```hcl
records = {
  public = {
    "api-blue" = {
      type = "A"
      alias = { name = aws_lb.blue.dns_name, zone_id = aws_lb.blue.zone_id }
      routing_policy = { type = "weighted", weight = 90, set_identifier = "blue" }
    }
    "api-green" = {
      type = "A"
      alias = { name = aws_lb.green.dns_name, zone_id = aws_lb.green.zone_id }
      routing_policy = { type = "weighted", weight = 10, set_identifier = "green" }
    }
  }
}
```

Gradually shift traffic between blue and green environments.

---

### 2. Failover with Health Checks

```hcl
health_checks = {
  api_primary = { type = "HTTPS", fqdn = "api.example.com", resource_path = "/health" }
}

records = {
  public = {
    "api-primary" = {
      type = "A"
      alias = { name = aws_lb.primary.dns_name, zone_id = aws_lb.primary.zone_id }
      routing_policy = { type = "failover", failover = "PRIMARY", set_identifier = "primary", health_check_id = module.dns.health_check_ids.api_primary }
    }
    "api-secondary" = {
      type = "A"
      alias = { name = aws_lb.secondary.dns_name, zone_id = aws_lb.secondary.zone_id }
      routing_policy = { type = "failover", failover = "SECONDARY", set_identifier = "secondary" }
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
    "app-eu" = { type = "A", alias = { name = aws_lb.eu.dns_name, zone_id = aws_lb.eu.zone_id }, routing_policy = { type = "latency", region = "eu-west-1", set_identifier = "eu" } }
    "app-us" = { type = "A", alias = { name = aws_lb.us.dns_name, zone_id = aws_lb.us.zone_id }, routing_policy = { type = "latency", region = "us-east-1", set_identifier = "us" } }
  }
}
```

Users are routed to the **nearest healthy region**.

---

### 4. Geolocation Routing

```hcl
records = {
  public = {
    "portal-eu" = { type = "A", alias = { name = aws_lb.eu.dns_name, zone_id = aws_lb.eu.zone_id }, routing_policy = { type = "geolocation", continent = "EU", set_identifier = "eu" } }
    "portal-default" = { type = "A", alias = { name = aws_lb.default.dns_name, zone_id = aws_lb.default.zone_id }, routing_policy = { type = "geolocation", set_identifier = "default" } }
  }
}
```

Serve users only from their region or a default fallback.

---

### 5. Private Hosted Zones

```hcl
zones = {
  private = { domain_name = "example.local", private = true, vpc_ids = [aws_vpc.main.id] }
}

records = {
  private = {
    "db" = { type = "CNAME", ttl = 30, values = ["aurora.cluster.local"] }
  }
}
```

DNS inside a VPC only; internal services stay private.

---

### 6. Apex Domain Alias (CloudFront)

```hcl
records = {
  public = {
    "" = { type = "A", alias = { name = aws_cloudfront_distribution.site.domain_name, zone_id = aws_cloudfront_distribution.site.hosted_zone_id } }
  }
}
```

Root domain points to CloudFront without needing `www`.

---

## Best Practices

- Prefer **module-managed health checks** for consistency.
- Always use **`set_identifier`** for weighted, failover, or geolocation records.
- Keep **TTL short** for dynamic failover scenarios.
- Use **alias records** where possible to avoid managing IPs.
- For private hosted zones, always attach **all VPCs that need DNS**.

