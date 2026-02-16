variable "zones" {
  description = "Hosted zones to create"
  type = map(object({
    domain_name = string
    comment     = optional(string)
    private     = optional(bool, false)
    vpc_ids     = optional(list(string), [])
  }))
}

variable "records" {
  description = "DNS records per zone"
  type = map(map(object({
    type    = string
    ttl     = optional(number)
    values  = optional(list(string))

    alias = optional(object({
      name                   = string
      zone_id               = string
      evaluate_target_health = optional(bool, false)
    }))

    routing_policy = optional(object({
      type            = string # simple | weighted | latency | failover | geolocation
      weight          = optional(number)
      region          = optional(string)
      failover        = optional(string)
      continent       = optional(string)
      country         = optional(string)
      subdivision     = optional(string)
      set_identifier  = optional(string)
      health_check_id = optional(string)
    }))
  })))
}

variable "health_checks" {
  description = "Optional Route53 health checks"
  type = map(object({
    type              = string            # HTTP | HTTPS | TCP
    fqdn              = string
    port              = optional(number)
    resource_path     = optional(string)
    request_interval  = optional(number, 30)
    failure_threshold = optional(number, 3)
    measure_latency   = optional(bool, false)
    inverted          = optional(bool, false)
    regions           = optional(list(string))
  }))
  default = {}
}
