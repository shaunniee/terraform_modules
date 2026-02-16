variable "certificates" {
  description = "List of ACM certificates to create. Certificates are keyed internally by domain_name."
  type = list(object({
    domain_name       = string
    san               = optional(list(string), [])
    validation_method = string
    zone_id           = optional(string)
    tags              = optional(map(string), {})
  }))
  default = []

  validation {
    condition     = length(distinct([for cert in var.certificates : lower(trimspace(cert.domain_name))])) == length(var.certificates)
    error_message = "Each certificate domain_name must be unique."
  }

  validation {
    condition = alltrue([
      for cert in var.certificates :
      trimspace(cert.domain_name) != ""
    ])
    error_message = "certificates[*].domain_name must be non-empty."
  }

  validation {
    condition = alltrue([
      for cert in var.certificates :
      contains(["DNS", "EMAIL"], upper(trimspace(cert.validation_method)))
    ])
    error_message = "certificates[*].validation_method must be DNS or EMAIL."
  }

  validation {
    condition = alltrue(flatten([
      for cert in var.certificates : [
        for san in cert.san : trimspace(san) != "" && lower(trimspace(san)) != lower(trimspace(cert.domain_name))
      ]
    ]))
    error_message = "certificates[*].san values must be non-empty and must not duplicate their certificate domain_name."
  }

  validation {
    condition = alltrue([
      for cert in var.certificates :
      try(cert.zone_id, null) == null || trimspace(cert.zone_id) != ""
    ])
    error_message = "certificates[*].zone_id must be null or a non-empty string."
  }
}

variable "certificates_map" {
  description = "Map keyed by certificate domain_name with optional Route53 zone_id for DNS validation records."
  type = map(object({
    zone_id = optional(string)
  }))
  default     = {}

  validation {
    condition = alltrue([
      for domain, cfg in var.certificates_map :
      trimspace(domain) != "" && (try(cfg.zone_id, null) == null || trimspace(cfg.zone_id) != "")
    ])
    error_message = "certificates_map keys must be non-empty and zone_id must be null or a non-empty string."
  }
}