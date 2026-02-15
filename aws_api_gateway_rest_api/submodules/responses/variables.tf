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

variable "method_responses" {
  type = map(object({
    method_key          = string
    status_code         = string
    response_models     = optional(map(string), {})
    response_parameters = optional(map(bool), {})
  }))
  default = {}
}

variable "integration_responses" {
  type = map(object({
    method_response_key = string
    status_code         = optional(string)
    selection_pattern   = optional(string)
    response_templates  = optional(map(string), {})
    response_parameters = optional(map(string), {})
    content_handling    = optional(string)
  }))
  default = {}
}
