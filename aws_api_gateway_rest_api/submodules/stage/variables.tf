variable "rest_api_id" {
  type = string
}

variable "rest_api_name" {
  type = string
}

variable "stage_name" {
  type = string
}

variable "stage_description" {
  type    = string
  default = null
}

variable "deployment_description" {
  type    = string
  default = null
}

variable "redeployment_hash" {
  type = string
}

variable "stage_variables" {
  type    = map(string)
  default = {}
}

variable "xray_tracing_enabled" {
  type    = bool
  default = false
}

variable "cache_cluster_enabled" {
  type    = bool
  default = false
}

variable "cache_cluster_size" {
  type    = string
  default = null
}

variable "access_log_enabled" {
  type    = bool
  default = false
}

variable "create_access_log_group" {
  type    = bool
  default = false
}

variable "access_log_group_name" {
  type    = string
  default = null
}

variable "access_log_retention_in_days" {
  type    = number
  default = 14
}

variable "access_log_kms_key_arn" {
  type    = string
  default = null
}

variable "access_log_destination_arn" {
  type    = string
  default = null
}

variable "access_log_format" {
  type    = string
  default = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"resourcePath\":\"$context.resourcePath\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\"}"
}

variable "method_settings" {
  type = object({
    metrics_enabled                            = optional(bool)
    logging_level                              = optional(string)
    data_trace_enabled                         = optional(bool)
    throttling_burst_limit                     = optional(number)
    throttling_rate_limit                      = optional(number)
    caching_enabled                            = optional(bool)
    cache_ttl_in_seconds                       = optional(number)
    cache_data_encrypted                       = optional(bool)
    require_authorization_for_cache_control    = optional(bool)
    unauthorized_cache_control_header_strategy = optional(string)
  })
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
