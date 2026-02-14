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
    condition     = trim(var.default_root_object) != "" && !startswith(var.default_root_object, "/")
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
      trim(a) != ""
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
    condition     = var.logging == null || trim(var.logging.bucket) != ""
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
}
EOT
  type = map(object({
    domain_name       = string
    origin_id         = string
    is_private_origin = bool
  }))

  validation {
    condition     = length(var.origins) > 0
    error_message = "origins must contain at least one origin."
  }

  validation {
    condition = alltrue([
      for o in values(var.origins) :
      trim(o.domain_name) != "" && trim(o.origin_id) != ""
    ])
    error_message = "Each origin must include non-empty domain_name and origin_id."
  }

  validation {
    condition     = length(distinct([for o in values(var.origins) : o.origin_id])) == length(var.origins)
    error_message = "Each origin.origin_id must be unique."
  }
}

variable "default_cache_behavior" {
  description = "Default cache behavior (preferred spelling)."
  type = object({
    target_origin_id = string
  })
  default = null

  validation {
    condition     = var.default_cache_behavior == null || trim(var.default_cache_behavior.target_origin_id) != ""
    error_message = "default_cache_behavior.target_origin_id must be non-empty when provided."
  }
}

variable "default_cache_behaviour" {
  description = "DEPRECATED: use default_cache_behavior."
  type = object({
    target_origin_id = string
  })
  default = null

  validation {
    condition     = var.default_cache_behaviour == null || trim(var.default_cache_behaviour.target_origin_id) != ""
    error_message = "default_cache_behaviour.target_origin_id must be non-empty when provided."
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
      trim(b.target_origin_id) != ""
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
      trim(b.target_origin_id) != ""
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
    condition = var.ordered_cache_behaviour == null || length(distinct([
      for b in values(var.ordered_cache_behaviour) :
      b.path_pattern
    ])) == length(var.ordered_cache_behaviour)
    error_message = "Each ordered_cache_behaviour.path_pattern must be unique."
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
