variable "name" {
  description = "API Gateway REST API name."
  type        = string

  validation {
    condition     = trimspace(var.name) != ""
    error_message = "name must be non-empty."
  }
}

variable "description" {
  description = "API description."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}

variable "endpoint_configuration_types" {
  description = "Endpoint types for API Gateway REST API."
  type        = list(string)
  default     = ["REGIONAL"]

  validation {
    condition = length(var.endpoint_configuration_types) > 0 && alltrue([
      for t in var.endpoint_configuration_types : contains(["REGIONAL", "EDGE", "PRIVATE"], t)
    ])
    error_message = "endpoint_configuration_types must include one or more of: REGIONAL, EDGE, PRIVATE."
  }
}

variable "binary_media_types" {
  description = "Binary media types supported by the API."
  type        = list(string)
  default     = []
}

variable "minimum_compression_size" {
  description = "Minimum compression size in bytes (0-10485760), or null to disable."
  type        = number
  default     = null

  validation {
    condition     = var.minimum_compression_size == null || (var.minimum_compression_size >= 0 && var.minimum_compression_size <= 10485760)
    error_message = "minimum_compression_size must be null or between 0 and 10485760."
  }
}

variable "api_key_source" {
  description = "API key source for requests."
  type        = string
  default     = "HEADER"

  validation {
    condition     = contains(["HEADER", "AUTHORIZER"], var.api_key_source)
    error_message = "api_key_source must be HEADER or AUTHORIZER."
  }
}

variable "disable_execute_api_endpoint" {
  description = "Disable the default execute-api endpoint."
  type        = bool
  default     = false
}

variable "resources" {
  description = "API resources map keyed by resource key. parent_key can be null for root."
  type = map(object({
    path_part  = string
    parent_key = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.resources :
      trimspace(r.path_part) != "" && (try(r.parent_key, null) == null || contains(keys(var.resources), r.parent_key))
    ])
    error_message = "Each resource must have non-empty path_part and parent_key must reference another resources key when set."
  }
}

variable "methods" {
  description = "API methods keyed by method key. resource_key defaults to root when omitted."
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

  validation {
    condition = alltrue([
      for m in values(var.methods) :
      contains(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "ANY"], upper(m.http_method))
    ])
    error_message = "methods[*].http_method must be one of GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, ANY."
  }

  validation {
    condition = alltrue([
      for m in values(var.methods) :
      contains(["NONE", "AWS_IAM", "CUSTOM", "COGNITO_USER_POOLS"], try(m.authorization, "NONE"))
    ])
    error_message = "methods[*].authorization must be NONE, AWS_IAM, CUSTOM, or COGNITO_USER_POOLS."
  }

  validation {
    condition = alltrue([
      for m in values(var.methods) :
      try(m.resource_key, null) == null || contains(keys(var.resources), m.resource_key)
    ])
    error_message = "methods[*].resource_key must reference an existing resources key when provided."
  }
}

variable "integrations" {
  description = "Integrations keyed by integration key, each linked to a method_key."
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

  validation {
    condition = alltrue([
      for i in values(var.integrations) : contains(keys(var.methods), i.method_key)
    ])
    error_message = "integrations[*].method_key must reference an existing methods key."
  }

  validation {
    condition = alltrue([
      for i in values(var.integrations) : contains(["HTTP", "HTTP_PROXY", "AWS", "AWS_PROXY", "MOCK"], i.type)
    ])
    error_message = "integrations[*].type must be one of HTTP, HTTP_PROXY, AWS, AWS_PROXY, MOCK."
  }

  validation {
    condition = alltrue([
      for i in values(var.integrations) :
      try(i.timeout_milliseconds, null) == null || (i.timeout_milliseconds >= 50 && i.timeout_milliseconds <= 29000)
    ])
    error_message = "integrations[*].timeout_milliseconds must be null or between 50 and 29000."
  }
}

variable "method_responses" {
  description = "Method responses keyed by response key."
  type = map(object({
    method_key          = string
    status_code         = string
    response_models     = optional(map(string), {})
    response_parameters = optional(map(bool), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.method_responses) :
      contains(keys(var.methods), r.method_key) && can(regex("^[1-5][0-9][0-9]$", r.status_code))
    ])
    error_message = "method_responses[*].method_key must reference methods and status_code must be a valid HTTP status code."
  }
}

variable "integration_responses" {
  description = "Integration responses keyed by response key."
  type = map(object({
    method_response_key = string
    status_code         = optional(string)
    selection_pattern   = optional(string)
    response_templates  = optional(map(string), {})
    response_parameters = optional(map(string), {})
    content_handling    = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.integration_responses) :
      contains(keys(var.method_responses), r.method_response_key)
    ])
    error_message = "integration_responses[*].method_response_key must reference an existing method_responses key."
  }

  validation {
    condition = alltrue([
      for r in values(var.integration_responses) :
      try(r.status_code, null) == null || can(regex("^[1-5][0-9][0-9]$", r.status_code))
    ])
    error_message = "integration_responses[*].status_code must be null or a valid HTTP status code."
  }
}

variable "stage_name" {
  description = "Stage name."
  type        = string
  default     = "v1"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1-128 characters and contain letters, numbers, underscore, or hyphen."
  }
}

variable "stage_description" {
  description = "Stage description."
  type        = string
  default     = null
}

variable "deployment_description" {
  description = "Deployment description."
  type        = string
  default     = null
}

variable "stage_variables" {
  description = "Stage variables."
  type        = map(string)
  default     = {}
}

variable "xray_tracing_enabled" {
  description = "Enable X-Ray tracing for stage."
  type        = bool
  default     = false
}

variable "cache_cluster_enabled" {
  description = "Enable cache cluster for stage."
  type        = bool
  default     = false
}

variable "cache_cluster_size" {
  description = "Cache cluster size when enabled."
  type        = string
  default     = null
}

variable "method_settings" {
  description = "Global method settings applied to */*."
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

  validation {
    condition     = var.method_settings == null || try(var.method_settings.logging_level, null) == null || contains(["OFF", "ERROR", "INFO"], var.method_settings.logging_level)
    error_message = "method_settings.logging_level must be OFF, ERROR, or INFO."
  }
}

variable "access_log_enabled" {
  description = "Enable API Gateway stage access logs."
  type        = bool
  default     = false

  validation {
    condition     = !var.access_log_enabled || var.create_access_log_group || var.access_log_destination_arn != null
    error_message = "When access_log_enabled is true, either create_access_log_group must be true or access_log_destination_arn must be provided."
  }
}

variable "create_access_log_group" {
  description = "Create a CloudWatch log group for access logs."
  type        = bool
  default     = false
}

variable "access_log_group_name" {
  description = "Custom access log group name when create_access_log_group is true."
  type        = string
  default     = null
}

variable "access_log_retention_in_days" {
  description = "CloudWatch access log retention in days."
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.access_log_retention_in_days)
    error_message = "access_log_retention_in_days must be a valid CloudWatch retention value."
  }
}

variable "access_log_kms_key_arn" {
  description = "KMS key ARN for access log group encryption."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.access_log_kms_key_arn))
    error_message = "access_log_kms_key_arn must be a valid KMS key ARN."
  }
}

variable "access_log_destination_arn" {
  description = "Existing log destination ARN for stage access logs."
  type        = string
  default     = null
}

variable "access_log_format" {
  description = "Access log format for stage."
  type        = string
  default     = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"resourcePath\":\"$context.resourcePath\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\"}"
}

variable "create_domain_name" {
  description = "Whether to create a custom domain and base path mapping."
  type        = bool
  default     = false

  validation {
    condition     = !var.create_domain_name || (var.domain_name != null && var.certificate_arn != null)
    error_message = "When create_domain_name is true, domain_name and certificate_arn are required."
  }
}

variable "domain_name" {
  description = "Custom domain name for API Gateway."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for custom domain."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws[a-zA-Z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate\\/.+$", var.certificate_arn))
    error_message = "certificate_arn must be a valid ACM certificate ARN."
  }
}

variable "base_path" {
  description = "Base path mapping. Null maps to root path."
  type        = string
  default     = null
}

variable "security_policy" {
  description = "TLS security policy for custom domain."
  type        = string
  default     = "TLS_1_2"

  validation {
    condition     = contains(["TLS_1_0", "TLS_1_2"], var.security_policy)
    error_message = "security_policy must be TLS_1_0 or TLS_1_2."
  }
}

variable "create_route53_record" {
  description = "Whether to create Route53 alias A record for custom domain."
  type        = bool
  default     = false

  validation {
    condition     = !var.create_route53_record || var.create_domain_name
    error_message = "create_route53_record requires create_domain_name = true."
  }

  validation {
    condition     = !var.create_route53_record || var.hosted_zone_id != null
    error_message = "hosted_zone_id is required when create_route53_record is true."
  }
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for alias record."
  type        = string
  default     = null
}

variable "record_name" {
  description = "Route53 record name. Defaults to domain_name when null."
  type        = string
  default     = null
}
