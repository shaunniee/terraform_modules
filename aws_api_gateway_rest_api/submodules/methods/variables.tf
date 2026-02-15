variable "rest_api_id" {
  type = string
}

variable "resource_ids" {
  type = map(string)
}

variable "methods" {
  type = map(object({
    resource_key         = optional(string)
    http_method          = string
    authorization        = optional(string, "NONE")
    authorizer_id        = optional(string)
    api_key_required     = optional(bool, false)
    request_models       = optional(map(string), {})
    request_parameters   = optional(map(bool), {})
    request_validator_id = optional(string)
    operation_name       = optional(string)
  }))
  default = {}
}
