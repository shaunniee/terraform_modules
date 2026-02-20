variable "distribution_name" {
  description = "Name for the CloudFront distribution"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.distribution_name))
    error_message = "distribution_name must be 1-64 characters and contain only letters, numbers, and hyphens."
  }
}

variable "comment" {
  description = "Optional comment for the CloudFront distribution."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "default_root_object" {
  type    = string
  default = "index.html"

  validation {
    condition     = trimspace(var.default_root_object) != "" && !startswith(var.default_root_object, "/")
    error_message = "default_root_object must be non-empty and must not start with '/'."
  }
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "aliases" {
  description = "Alternate domain names (CNAMEs) for the distribution."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for a in var.aliases :
      trimspace(a) != ""
    ])
    error_message = "aliases cannot contain empty values."
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domain TLS. Required when aliases are set."
  type        = string
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null || can(regex("^arn:aws[a-zA-Z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate\\/.+$", var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be a valid ACM certificate ARN."
  }

  validation {
    condition     = length(var.aliases) == 0 || var.acm_certificate_arn == null || can(regex("^arn:aws[a-zA-Z-]*:acm:us-east-1:[0-9]{12}:certificate\\/.+$", var.acm_certificate_arn))
    error_message = "When aliases are configured, acm_certificate_arn must be in us-east-1 for CloudFront."
  }
}

variable "ssl_support_method" {
  description = "SSL support method for custom certificate."
  type        = string
  default     = "sni-only"

  validation {
    condition     = contains(["sni-only", "vip", "static-ip"], var.ssl_support_method)
    error_message = "ssl_support_method must be one of: sni-only, vip, static-ip."
  }
}

variable "minimum_protocol_version" {
  description = "Minimum TLS protocol version for viewer connections when using ACM certificate."
  type        = string
  default     = "TLSv1.2_2021"

  validation {
    condition = contains([
      "SSLv3",
      "TLSv1",
      "TLSv1_2016",
      "TLSv1.1_2016",
      "TLSv1.2_2018",
      "TLSv1.2_2019",
      "TLSv1.2_2021",
      "TLSv1.3_2021"
    ], var.minimum_protocol_version)
    error_message = "minimum_protocol_version must be a valid CloudFront TLS policy value."
  }
}

variable "web_acl_id" {
  description = "Optional AWS WAF web ACL ARN to associate with the distribution."
  type        = string
  default     = null
}

variable "logging" {
  description = "Optional access logging configuration for CloudFront."
  type = object({
    bucket          = string
    include_cookies = bool
    prefix          = string
  })
  default = null

  validation {
    condition     = var.logging == null || trimspace(var.logging.bucket) != ""
    error_message = "logging.bucket must be non-empty when logging is configured."
  }
}

variable "origins" {
  description = <<EOT
Map of origins:
key = origin name
value = {
  domain_name       = "bucket-or-domain"
  origin_id         = "origin-id"
  is_private_origin = true/false
  origin_type       = "s3" | "custom" (optional, default "s3")
  origin_path       = "/optional-path" (optional)
  custom_origin_config = {
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"
    origin_ssl_protocols   = ["TLSv1.2"]
    origin_read_timeout    = 30
    origin_keepalive_timeout = 5
  } (required only when origin_type = "custom")
}
EOT
  type = map(object({
    domain_name       = string
    origin_id         = string
    is_private_origin = bool
    origin_type       = optional(string, "s3")
    origin_path       = optional(string)
    custom_origin_config = optional(object({
      http_port               = optional(number, 80)
      https_port              = optional(number, 443)
      origin_protocol_policy  = optional(string, "https-only")
      origin_ssl_protocols    = optional(list(string), ["TLSv1.2"])
      origin_read_timeout     = optional(number, 30)
      origin_keepalive_timeout = optional(number, 5)
    }))
  }))

  validation {
    condition     = length(var.origins) > 0
    error_message = "origins must contain at least one origin."
  }

  validation {
    condition = alltrue([
      for o in values(var.origins) :
      trimspace(o.domain_name) != "" && trimspace(o.origin_id) != ""
    ])
    error_message = "Each origin must include non-empty domain_name and origin_id."
  }

  validation {
    condition     = length(distinct([for o in values(var.origins) : o.origin_id])) == length(var.origins)
    error_message = "Each origin.origin_id must be unique."
  }

  validation {
    condition = alltrue([
      for o in values(var.origins) :
      contains(["s3", "custom"], lower(try(o.origin_type, "s3")))
    ])
    error_message = "origins[*].origin_type must be one of: s3, custom."
  }

  validation {
    condition = alltrue([
      for o in values(var.origins) :
      lower(try(o.origin_type, "s3")) != "custom" || try(o.custom_origin_config, null) != null
    ])
    error_message = "origins[*].custom_origin_config is required when origin_type is custom."
  }

  validation {
    condition = alltrue([
      for o in values(var.origins) :
      !o.is_private_origin || lower(try(o.origin_type, "s3")) == "s3"
    ])
    error_message = "is_private_origin can only be true for S3 origins."
  }

  validation {
    condition = alltrue(flatten([
      for o in values(var.origins) : [
        lower(try(o.origin_type, "s3")) != "custom" || contains(["http-only", "https-only", "match-viewer"], try(o.custom_origin_config.origin_protocol_policy, "https-only")),
        lower(try(o.origin_type, "s3")) != "custom" || length(try(o.custom_origin_config.origin_ssl_protocols, ["TLSv1.2"])) > 0,
        lower(try(o.origin_type, "s3")) != "custom" || alltrue([
          for protocol in try(o.custom_origin_config.origin_ssl_protocols, ["TLSv1.2"]) :
          contains(["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"], protocol)
        ]),
        lower(try(o.origin_type, "s3")) != "custom" || (try(o.custom_origin_config.http_port, 80) >= 1 && try(o.custom_origin_config.http_port, 80) <= 65535),
        lower(try(o.origin_type, "s3")) != "custom" || (try(o.custom_origin_config.https_port, 443) >= 1 && try(o.custom_origin_config.https_port, 443) <= 65535),
        lower(try(o.origin_type, "s3")) != "custom" || (try(o.custom_origin_config.origin_read_timeout, 30) >= 1 && try(o.custom_origin_config.origin_read_timeout, 30) <= 120),
        lower(try(o.origin_type, "s3")) != "custom" || (try(o.custom_origin_config.origin_keepalive_timeout, 5) >= 1 && try(o.custom_origin_config.origin_keepalive_timeout, 5) <= 120)
      ]
    ]))
    error_message = "Invalid custom origin settings: check protocol policy, SSL protocols, ports (1-65535), read timeout (1-120), and keepalive timeout (1-120)."
  }
}

variable "default_cache_behavior" {
  description = "Default cache behavior (preferred spelling)."
  type = object({
    target_origin_id       = string
    viewer_protocol_policy = optional(string, "redirect-to-https")
    allowed_methods        = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods         = optional(list(string), ["GET", "HEAD"])
    cache_policy_id        = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    function_associations = optional(map(object({
      event_type   = optional(string, "viewer-request")
      function_arn = string
    })), {})
    lambda_function_associations = optional(map(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool, false)
    })), {})
  })
  default = null

  validation {
    condition     = var.default_cache_behavior == null || trimspace(var.default_cache_behavior.target_origin_id) != ""
    error_message = "default_cache_behavior.target_origin_id must be non-empty when provided."
  }

  validation {
    condition = var.default_cache_behavior == null || contains([
      "allow-all", "https-only", "redirect-to-https"
    ], try(var.default_cache_behavior.viewer_protocol_policy, "redirect-to-https"))
    error_message = "default_cache_behavior.viewer_protocol_policy must be allow-all, https-only, or redirect-to-https."
  }

  validation {
    condition = var.default_cache_behavior == null || (
      length(try(var.default_cache_behavior.allowed_methods, ["GET", "HEAD", "OPTIONS"])) > 0 &&
      alltrue([
        for m in try(var.default_cache_behavior.allowed_methods, ["GET", "HEAD", "OPTIONS"]) :
        contains(["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"], m)
      ])
    )
    error_message = "default_cache_behavior.allowed_methods must be non-empty and only include valid CloudFront methods."
  }

  validation {
    condition = var.default_cache_behavior == null || (
      length(try(var.default_cache_behavior.cached_methods, ["GET", "HEAD"])) > 0 &&
      alltrue([
        for m in try(var.default_cache_behavior.cached_methods, ["GET", "HEAD"]) :
        contains(["GET", "HEAD", "OPTIONS"], m)
      ]) &&
      alltrue([
        for m in try(var.default_cache_behavior.cached_methods, ["GET", "HEAD"]) :
        contains(try(var.default_cache_behavior.allowed_methods, ["GET", "HEAD", "OPTIONS"]), m)
      ])
    )
    error_message = "default_cache_behavior.cached_methods must be non-empty, only include GET/HEAD/OPTIONS, and be a subset of allowed_methods."
  }

  validation {
    condition = var.default_cache_behavior == null || alltrue([
      for f in values(try(var.default_cache_behavior.function_associations, {})) :
      trimspace(f.function_arn) != "" && contains(["viewer-request", "viewer-response"], try(f.event_type, "viewer-request"))
    ])
    error_message = "default_cache_behavior.function_associations must use non-empty function_arn and event_type of viewer-request or viewer-response."
  }
}

variable "default_cache_behaviour" {
  description = "DEPRECATED: use default_cache_behavior."
  type = object({
    target_origin_id       = string
    viewer_protocol_policy = optional(string, "redirect-to-https")
    allowed_methods        = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods         = optional(list(string), ["GET", "HEAD"])
    cache_policy_id        = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    function_associations = optional(map(object({
      event_type   = optional(string, "viewer-request")
      function_arn = string
    })), {})
    lambda_function_associations = optional(map(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool, false)
    })), {})
  })
  default = null

  validation {
    condition     = var.default_cache_behaviour == null || trimspace(var.default_cache_behaviour.target_origin_id) != ""
    error_message = "default_cache_behaviour.target_origin_id must be non-empty when provided."
  }

  validation {
    condition = var.default_cache_behaviour == null || contains([
      "allow-all", "https-only", "redirect-to-https"
    ], try(var.default_cache_behaviour.viewer_protocol_policy, "redirect-to-https"))
    error_message = "default_cache_behaviour.viewer_protocol_policy must be allow-all, https-only, or redirect-to-https."
  }

  validation {
    condition = var.default_cache_behaviour == null || (
      length(try(var.default_cache_behaviour.allowed_methods, ["GET", "HEAD", "OPTIONS"])) > 0 &&
      alltrue([
        for m in try(var.default_cache_behaviour.allowed_methods, ["GET", "HEAD", "OPTIONS"]) :
        contains(["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"], m)
      ])
    )
    error_message = "default_cache_behaviour.allowed_methods must be non-empty and only include valid CloudFront methods."
  }

  validation {
    condition = var.default_cache_behaviour == null || (
      length(try(var.default_cache_behaviour.cached_methods, ["GET", "HEAD"])) > 0 &&
      alltrue([
        for m in try(var.default_cache_behaviour.cached_methods, ["GET", "HEAD"]) :
        contains(["GET", "HEAD", "OPTIONS"], m)
      ]) &&
      alltrue([
        for m in try(var.default_cache_behaviour.cached_methods, ["GET", "HEAD"]) :
        contains(try(var.default_cache_behaviour.allowed_methods, ["GET", "HEAD", "OPTIONS"]), m)
      ])
    )
    error_message = "default_cache_behaviour.cached_methods must be non-empty, only include GET/HEAD/OPTIONS, and be a subset of allowed_methods."
  }

  validation {
    condition = var.default_cache_behaviour == null || alltrue([
      for f in values(try(var.default_cache_behaviour.function_associations, {})) :
      trimspace(f.function_arn) != "" && contains(["viewer-request", "viewer-response"], try(f.event_type, "viewer-request"))
    ])
    error_message = "default_cache_behaviour.function_associations must use non-empty function_arn and event_type of viewer-request or viewer-response."
  }
}

variable "ordered_cache_behavior" {
  description = <<EOT
Map of ordered cache behaviors (preferred spelling):
key = behavior name
value = {
  path_pattern        = string
  target_origin_id    = string
  allowed_methods     = list(string)
  cached_methods      = list(string)
  cache_disabled      = bool
  requires_signed_url = bool
}
EOT
  type = map(object({
    path_pattern        = string
    target_origin_id    = string
    allowed_methods     = list(string)
    cached_methods      = list(string)
    viewer_protocol_policy     = optional(string, "redirect-to-https")
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    function_associations = optional(map(object({
      event_type   = optional(string, "viewer-request")
      function_arn = string
    })), {})
    lambda_function_associations = optional(map(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool, false)
    })), {})
    cache_disabled      = bool
    requires_signed_url = bool
  }))
  default = null

  validation {
    condition = var.ordered_cache_behavior == null || alltrue([
      for b in values(var.ordered_cache_behavior) :
      startswith(b.path_pattern, "/")
    ])
    error_message = "Each ordered_cache_behavior.path_pattern must start with '/'."
  }

  validation {
    condition = var.ordered_cache_behavior == null || alltrue([
      for b in values(var.ordered_cache_behavior) :
      trimspace(b.target_origin_id) != ""
    ])
    error_message = "Each ordered_cache_behavior.target_origin_id must be non-empty."
  }

  validation {
    condition = var.ordered_cache_behavior == null || alltrue([
      for b in values(var.ordered_cache_behavior) :
      length(b.allowed_methods) > 0 && alltrue([
        for m in b.allowed_methods :
        contains(["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"], m)
      ])
    ])
    error_message = "ordered_cache_behavior.allowed_methods must be non-empty and only include valid CloudFront methods."
  }

  validation {
    condition = var.ordered_cache_behavior == null || alltrue([
      for b in values(var.ordered_cache_behavior) :
      length(b.cached_methods) > 0 && alltrue([
        for m in b.cached_methods :
        contains(["GET", "HEAD", "OPTIONS"], m)
      ])
    ])
    error_message = "ordered_cache_behavior.cached_methods must be non-empty and only include GET, HEAD, or OPTIONS."
  }

  validation {
    condition = var.ordered_cache_behavior == null || alltrue([
      for b in values(var.ordered_cache_behavior) :
      alltrue([for m in b.cached_methods : contains(b.allowed_methods, m)])
    ])
    error_message = "Each cached method must also be present in allowed_methods."
  }

  validation {
    condition = var.ordered_cache_behavior == null || alltrue([
      for b in values(var.ordered_cache_behavior) :
      contains(["allow-all", "https-only", "redirect-to-https"], try(b.viewer_protocol_policy, "redirect-to-https"))
    ])
    error_message = "ordered_cache_behavior.viewer_protocol_policy must be allow-all, https-only, or redirect-to-https."
  }

  validation {
    condition = var.ordered_cache_behavior == null || alltrue(flatten([
      for b in values(var.ordered_cache_behavior) : [
        for f in values(try(b.function_associations, {})) :
        trimspace(f.function_arn) != "" && contains(["viewer-request", "viewer-response"], try(f.event_type, "viewer-request"))
      ]
    ]))
    error_message = "ordered_cache_behavior.function_associations must use non-empty function_arn and event_type of viewer-request or viewer-response."
  }

  validation {
    condition = var.ordered_cache_behavior == null || length(distinct([
      for b in values(var.ordered_cache_behavior) :
      b.path_pattern
    ])) == length(var.ordered_cache_behavior)
    error_message = "Each ordered_cache_behavior.path_pattern must be unique."
  }
}

variable "ordered_cache_behaviour" {
  description = "DEPRECATED: use ordered_cache_behavior."
  type = map(object({
    path_pattern        = string
    target_origin_id    = string
    allowed_methods     = list(string)
    cached_methods      = list(string)
    viewer_protocol_policy     = optional(string, "redirect-to-https")
    cache_policy_id            = optional(string)
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
    function_associations = optional(map(object({
      event_type   = optional(string, "viewer-request")
      function_arn = string
    })), {})
    lambda_function_associations = optional(map(object({
      event_type   = string
      lambda_arn   = string
      include_body = optional(bool, false)
    })), {})
    cache_disabled      = bool
    requires_signed_url = bool
  }))
  default = null

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue([
      for b in values(var.ordered_cache_behaviour) :
      startswith(b.path_pattern, "/")
    ])
    error_message = "Each ordered_cache_behaviour.path_pattern must start with '/'."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue([
      for b in values(var.ordered_cache_behaviour) :
      trimspace(b.target_origin_id) != ""
    ])
    error_message = "Each ordered_cache_behaviour.target_origin_id must be non-empty."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue([
      for b in values(var.ordered_cache_behaviour) :
      length(b.allowed_methods) > 0 && alltrue([
        for m in b.allowed_methods :
        contains(["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"], m)
      ])
    ])
    error_message = "ordered_cache_behaviour.allowed_methods must be non-empty and only include valid CloudFront methods."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue([
      for b in values(var.ordered_cache_behaviour) :
      length(b.cached_methods) > 0 && alltrue([
        for m in b.cached_methods :
        contains(["GET", "HEAD", "OPTIONS"], m)
      ])
    ])
    error_message = "ordered_cache_behaviour.cached_methods must be non-empty and only include GET, HEAD, or OPTIONS."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue([
      for b in values(var.ordered_cache_behaviour) :
      alltrue([for m in b.cached_methods : contains(b.allowed_methods, m)])
    ])
    error_message = "Each cached method must also be present in allowed_methods."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue([
      for b in values(var.ordered_cache_behaviour) :
      contains(["allow-all", "https-only", "redirect-to-https"], try(b.viewer_protocol_policy, "redirect-to-https"))
    ])
    error_message = "ordered_cache_behaviour.viewer_protocol_policy must be allow-all, https-only, or redirect-to-https."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || alltrue(flatten([
      for b in values(var.ordered_cache_behaviour) : [
        for f in values(try(b.function_associations, {})) :
        trimspace(f.function_arn) != "" && contains(["viewer-request", "viewer-response"], try(f.event_type, "viewer-request"))
      ]
    ]))
    error_message = "ordered_cache_behaviour.function_associations must use non-empty function_arn and event_type of viewer-request or viewer-response."
  }

  validation {
    condition = var.ordered_cache_behaviour == null || length(distinct([
      for b in values(var.ordered_cache_behaviour) :
      b.path_pattern
    ])) == length(var.ordered_cache_behaviour)
    error_message = "Each ordered_cache_behaviour.path_pattern must be unique."
  }
}

variable "geo_restriction" {
  description = "Geo-restriction configuration. `restriction_type` is `none`, `whitelist`, or `blacklist`; `locations` are ISO 3166-1-alpha-2 country codes."
  type = object({
    restriction_type = optional(string, "none")
    locations        = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], try(var.geo_restriction.restriction_type, "none"))
    error_message = "geo_restriction.restriction_type must be none, whitelist, or blacklist."
  }

  validation {
    condition = try(var.geo_restriction.restriction_type, "none") == "none" || length(try(var.geo_restriction.locations, [])) > 0
    error_message = "geo_restriction.locations must be non-empty when restriction_type is whitelist or blacklist."
  }

  validation {
    condition = alltrue([
      for loc in try(var.geo_restriction.locations, []) : can(regex("^[A-Z]{2}$", loc))
    ])
    error_message = "geo_restriction.locations must be ISO 3166-1-alpha-2 country codes (e.g., US, GB, DE)."
  }
}

variable "origin_groups" {
  description = "Map of origin groups for failover. Each group has a primary and failover origin_id, and a set of HTTP status codes that trigger failover."
  type = map(object({
    primary_origin_id  = string
    failover_origin_id = string
    failover_status_codes = optional(list(number), [500, 502, 503, 504])
  }))
  default = {}

  validation {
    condition = alltrue([
      for g in values(var.origin_groups) :
      g.primary_origin_id != g.failover_origin_id
    ])
    error_message = "origin_groups: primary_origin_id and failover_origin_id must be different."
  }

  validation {
    condition = alltrue(flatten([
      for g in values(var.origin_groups) : [
        for code in g.failover_status_codes :
        contains([400, 403, 404, 416, 500, 502, 503, 504], code)
      ]
    ]))
    error_message = "origin_groups.failover_status_codes must be valid CloudFront failover codes: 400, 403, 404, 416, 500, 502, 503, 504."
  }
}

variable "custom_error_responses" {
  description = "Map of custom error responses. Allows custom error pages and TTLs beyond SPA fallback."
  type = map(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for e in values(var.custom_error_responses) :
      e.error_code >= 400 && e.error_code <= 599
    ])
    error_message = "custom_error_responses[*].error_code must be 400–599."
  }

  validation {
    condition = alltrue([
      for e in values(var.custom_error_responses) :
      e.response_page_path == null || startswith(e.response_page_path, "/")
    ])
    error_message = "custom_error_responses[*].response_page_path must start with '/' when provided."
  }
}

variable "spa_fallback" {
  type    = bool
  default = false
}

variable "spa_fallback_status_codes" {
  type    = list(number)
  default = [404]

  validation {
    condition = alltrue([
      for code in var.spa_fallback_status_codes :
      code >= 400 && code <= 599
    ])
    error_message = "spa_fallback_status_codes can only contain HTTP error status codes (400-599)."
  }
}

# Optional: KMS key ARN for signing URLs
variable "kms_key_arn" {
  description = "KMS key ARN used to sign CloudFront URLs"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "cloudwatch_metric_alarms" {
  description = "Map of CloudWatch metric alarms keyed by logical alarm key. Defaults namespace to AWS/CloudFront and injects DistributionId + Region=Global dimensions."
  type = map(object({
    enabled                    = optional(bool, true)
    alarm_name                 = optional(string)
    alarm_description          = optional(string)
    comparison_operator        = string
    evaluation_periods         = number
    metric_name                = string
    namespace                  = optional(string, "AWS/CloudFront")
    period                     = number
    statistic                  = optional(string)
    extended_statistic         = optional(string)
    threshold                  = number
    datapoints_to_alarm        = optional(number)
    treat_missing_data         = optional(string)
    alarm_actions              = optional(list(string), [])
    ok_actions                 = optional(list(string), [])
    insufficient_data_actions  = optional(list(string), [])
    dimensions                 = optional(map(string), {})
    tags                       = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      ((try(alarm.statistic, null) != null) != (try(alarm.extended_statistic, null) != null))
    ])
    error_message = "Each cloudwatch_metric_alarms entry must set exactly one of statistic or extended_statistic."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      try(alarm.treat_missing_data, null) == null || contains(["breaching", "notBreaching", "ignore", "missing"], alarm.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      contains([
        "GreaterThanOrEqualToThreshold",
        "GreaterThanThreshold",
        "LessThanOrEqualToThreshold",
        "LessThanThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "GreaterThanUpperThreshold"
      ], alarm.comparison_operator)
    ])
    error_message = "cloudwatch_metric_alarms[*].comparison_operator must be a valid CloudWatch comparison operator."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      alarm.evaluation_periods >= 1
    ])
    error_message = "cloudwatch_metric_alarms[*].evaluation_periods must be >= 1."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      alarm.period >= 10
    ])
    error_message = "cloudwatch_metric_alarms[*].period must be >= 10."
  }
}

variable "realtime_log_config" {
  description = "Optional CloudFront real-time log configuration. When set, attaches real-time logs to default and ordered cache behaviors."
  type = object({
    name          = optional(string)
    sampling_rate = optional(number, 100)
    fields        = optional(list(string), [
      "timestamp",
      "c-ip",
      "cs-method",
      "cs-uri-stem",
      "sc-status",
      "time-to-first-byte",
      "x-edge-location"
    ])
    endpoints = list(object({
      stream_type = optional(string, "Kinesis")
      role_arn    = string
      stream_arn  = string
    }))
  })
  default = null

  validation {
    condition     = var.realtime_log_config == null || (try(var.realtime_log_config.sampling_rate, 100) >= 1 && try(var.realtime_log_config.sampling_rate, 100) <= 100)
    error_message = "realtime_log_config.sampling_rate must be between 1 and 100."
  }

  validation {
    condition = var.realtime_log_config == null || alltrue([
      for endpoint in var.realtime_log_config.endpoints :
      contains(["Kinesis"], try(endpoint.stream_type, "Kinesis")) &&
      can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/.+$", endpoint.role_arn)) &&
      can(regex("^arn:aws[a-zA-Z-]*:kinesis:[a-z0-9-]+:[0-9]{12}:stream/.+$", endpoint.stream_arn))
    ])
    error_message = "realtime_log_config.endpoints must use stream_type=Kinesis and valid role_arn/stream_arn values."
  }

  validation {
    condition     = var.realtime_log_config == null || length(var.realtime_log_config.endpoints) > 0
    error_message = "realtime_log_config.endpoints must include at least one endpoint when realtime_log_config is set."
  }
}

variable "realtime_metrics_subscription_enabled" {
  description = "Enable CloudFront real-time metrics subscription for the distribution."
  type        = bool
  default     = false
}

# =============================================================================
# Observability
# =============================================================================

variable "observability" {
  description = <<-EOT
    Observability configuration for CloudWatch alarms and dashboard.
    Set `enabled = true` to activate default alarms and dashboard.
  EOT
  type = object({
    enabled               = optional(bool, false)
    enable_default_alarms = optional(bool, true)
    enable_dashboard      = optional(bool, true)
    enable_anomaly_detection_alarms = optional(bool, false)

    # Default alarm thresholds
    error_5xx_rate_threshold = optional(number, 5)   # 5xxErrorRate percentage
    error_4xx_rate_threshold = optional(number, 15)  # 4xxErrorRate percentage
    origin_latency_threshold = optional(number, 5)   # OriginLatency in seconds

    # Alarm actions
    default_alarm_actions             = optional(list(string), [])
    default_ok_actions                = optional(list(string), [])
    default_insufficient_data_actions = optional(list(string), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_alarm_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_alarm_actions ARNs must start with 'arn:'."
  }

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_ok_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_ok_actions ARNs must start with 'arn:'."
  }

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_insufficient_data_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_insufficient_data_actions ARNs must start with 'arn:'."
  }

  validation {
    condition     = try(var.observability.error_5xx_rate_threshold, 5) >= 0 && try(var.observability.error_5xx_rate_threshold, 5) <= 100
    error_message = "observability.error_5xx_rate_threshold must be 0–100."
  }

  validation {
    condition     = try(var.observability.error_4xx_rate_threshold, 15) >= 0 && try(var.observability.error_4xx_rate_threshold, 15) <= 100
    error_message = "observability.error_4xx_rate_threshold must be 0–100."
  }

  validation {
    condition     = try(var.observability.origin_latency_threshold, 5) > 0
    error_message = "observability.origin_latency_threshold must be > 0."
  }
}

variable "cloudwatch_metric_anomaly_alarms" {
  description = "Map of CloudWatch anomaly detection alarms keyed by logical alarm key. Each alarm uses ANOMALY_DETECTION_BAND with DistributionId + Region=Global dimensions injected by default."
  type = map(object({
    enabled                    = optional(bool, true)
    alarm_name                 = optional(string)
    alarm_description          = optional(string)
    comparison_operator        = optional(string, "GreaterThanUpperThreshold")
    evaluation_periods         = number
    metric_name                = string
    namespace                  = optional(string, "AWS/CloudFront")
    period                     = number
    statistic                  = string
    anomaly_detection_stddev   = optional(number, 2)
    datapoints_to_alarm        = optional(number)
    treat_missing_data         = optional(string)
    alarm_actions              = optional(list(string), [])
    ok_actions                 = optional(list(string), [])
    insufficient_data_actions  = optional(list(string), [])
    dimensions                 = optional(map(string), {})
    tags                       = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_anomaly_alarms) :
      contains([
        "GreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold"
      ], try(alarm.comparison_operator, "GreaterThanUpperThreshold"))
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].comparison_operator must be GreaterThanUpperThreshold, LessThanLowerThreshold, or LessThanLowerOrGreaterThanUpperThreshold."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_anomaly_alarms) :
      try(alarm.treat_missing_data, null) == null || contains(["breaching", "notBreaching", "ignore", "missing"], alarm.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_anomaly_alarms) :
      try(alarm.anomaly_detection_stddev, 2) > 0
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].anomaly_detection_stddev must be greater than 0."
  }
}
