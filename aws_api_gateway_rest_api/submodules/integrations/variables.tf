variable "rest_api_id" {
  type = string
}

variable "methods_index" {
  type = map(object({
    resource_id = string
    http_method = string
    id          = string
  }))
}

variable "integrations" {
  type = map(object({
    method_key              = string
    type                    = string
    integration_http_method = optional(string)
    uri                     = optional(string)
    connection_type         = optional(string)
    connection_id           = optional(string)
    passthrough_behavior    = optional(string)
    request_templates       = optional(map(string), {})
    request_parameters      = optional(map(string), {})
    content_handling        = optional(string)
    timeout_milliseconds    = optional(number)
    cache_key_parameters    = optional(list(string), [])
    cache_namespace         = optional(string)
  }))
  default = {}
}
