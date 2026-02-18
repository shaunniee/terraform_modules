variable "rest_api_id" {
  type = string
}

variable "authorizers" {
  type = map(object({
    name                              = string
    type                              = string
    provider_arns                     = optional(list(string), [])
    authorizer_uri                    = optional(string)
    authorizer_credentials            = optional(string)
    identity_source                   = optional(string)
    identity_validation_expression    = optional(string)
    authorizer_result_ttl_in_seconds  = optional(number)
  }))
  default = {}
}
