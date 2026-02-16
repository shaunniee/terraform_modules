variable "certificates" {
  description = "List of ACM certificates to create"
  type = list(object({
    domain_name       = string
    san               = optional(list(string), [])
    validation_method = string # DNS or EMAIL
    zone_id           = optional(string) # for DNS validation
    tags              = optional(map(string), {})
  }))
  default = []
}

variable "certificates_map" {
  description = "Map version of certificates for easier lookup in Route53"
  type        = map(any)
  default     = {}
}