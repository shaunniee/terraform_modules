variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "The name of the AppSync GraphQL API"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_ ]{1,128}$", var.name))
    error_message = "name must be 1-128 characters and contain only letters, numbers, hyphens, underscores, and spaces."
  }
}

variable "api_type" {
  description = "The API type. Valid values: GRAPHQL, MERGED."
  type        = string
  default     = "GRAPHQL"

  validation {
    condition     = contains(["GRAPHQL", "MERGED"], var.api_type)
    error_message = "api_type must be one of: GRAPHQL, MERGED."
  }
}

variable "schema" {
  description = "The GraphQL schema definition (SDL). Required when api_type is GRAPHQL."
  type        = string
  default     = null
}

variable "visibility" {
  description = "API visibility. GLOBAL makes it available on the internet; PRIVATE restricts to VPC. Valid values: GLOBAL, PRIVATE."
  type        = string
  default     = "GLOBAL"

  validation {
    condition     = contains(["GLOBAL", "PRIVATE"], var.visibility)
    error_message = "visibility must be one of: GLOBAL, PRIVATE."
  }
}

variable "introspection_config" {
  description = "Whether introspection queries are enabled. Valid values: ENABLED, DISABLED."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.introspection_config)
    error_message = "introspection_config must be one of: ENABLED, DISABLED."
  }
}

variable "query_depth_limit" {
  description = "Maximum depth of a query. Valid range: 1-75. 0 disables."
  type        = number
  default     = 0

  validation {
    condition     = var.query_depth_limit >= 0 && var.query_depth_limit <= 75
    error_message = "query_depth_limit must be between 0 and 75 (0 = disabled)."
  }
}

variable "resolver_count_limit" {
  description = "Maximum number of resolvers that can be invoked in a single request. Valid range: 1-10000. 0 disables."
  type        = number
  default     = 0

  validation {
    condition     = var.resolver_count_limit >= 0 && var.resolver_count_limit <= 10000
    error_message = "resolver_count_limit must be between 0 and 10000 (0 = disabled)."
  }
}

# =============================================================================
# Authentication Configuration
# =============================================================================

variable "authentication_type" {
  description = "The default authentication type for the API. Valid values: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, AWS_LAMBDA."
  type        = string
  default     = "API_KEY"

  validation {
    condition     = contains(["API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT", "AWS_LAMBDA"], var.authentication_type)
    error_message = "authentication_type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, AWS_LAMBDA."
  }
}

variable "user_pool_config" {
  description = "Cognito User Pool configuration for the default authentication provider. Required when authentication_type is AMAZON_COGNITO_USER_POOLS."
  type = object({
    user_pool_id        = string
    aws_region          = optional(string)
    app_id_client_regex = optional(string)
    default_action      = optional(string, "ALLOW")
  })
  default = null

  validation {
    condition     = var.user_pool_config == null || contains(["ALLOW", "DENY"], try(var.user_pool_config.default_action, "ALLOW"))
    error_message = "user_pool_config.default_action must be one of: ALLOW, DENY."
  }
}

variable "openid_connect_config" {
  description = "OpenID Connect configuration for the default authentication provider. Required when authentication_type is OPENID_CONNECT."
  type = object({
    issuer    = string
    client_id = optional(string)
    auth_ttl  = optional(number)
    iat_ttl   = optional(number)
  })
  default = null
}

variable "lambda_authorizer_config" {
  description = "Lambda authorizer configuration for the default authentication provider. Required when authentication_type is AWS_LAMBDA."
  type = object({
    authorizer_uri                   = string
    authorizer_result_ttl_in_seconds = optional(number, 300)
    identity_validation_expression   = optional(string)
  })
  default = null

  validation {
    condition     = var.lambda_authorizer_config == null || try(var.lambda_authorizer_config.authorizer_result_ttl_in_seconds, 300) >= 0 && try(var.lambda_authorizer_config.authorizer_result_ttl_in_seconds, 300) <= 3600
    error_message = "lambda_authorizer_config.authorizer_result_ttl_in_seconds must be between 0 and 3600."
  }
}

variable "additional_authentication_providers" {
  description = "List of additional authentication providers for the GraphQL API."
  type = list(object({
    authentication_type = string
    user_pool_config = optional(object({
      user_pool_id        = string
      aws_region          = optional(string)
      app_id_client_regex = optional(string)
    }))
    openid_connect_config = optional(object({
      issuer    = string
      client_id = optional(string)
      auth_ttl  = optional(number)
      iat_ttl   = optional(number)
    }))
    lambda_authorizer_config = optional(object({
      authorizer_uri                   = string
      authorizer_result_ttl_in_seconds = optional(number, 300)
      identity_validation_expression   = optional(string)
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for provider in var.additional_authentication_providers :
      contains(["API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT", "AWS_LAMBDA"], provider.authentication_type)
    ])
    error_message = "Each additional_authentication_providers[*].authentication_type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, AWS_LAMBDA."
  }
}

# =============================================================================
# API Keys
# =============================================================================

variable "api_keys" {
  description = "Map of API keys keyed by logical name. Each key can have an optional description and expiration."
  type = map(object({
    description = optional(string)
    expires     = optional(string)
  }))
  default = {}
}

# =============================================================================
# Logging & Tracing Configuration
# =============================================================================

variable "logging_enabled" {
  description = "Whether to enable CloudWatch logging for the API."
  type        = bool
  default     = false
}

variable "log_field_log_level" {
  description = "Field-level logging level. Valid values: ALL, ERROR, NONE."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["ALL", "ERROR", "NONE"], var.log_field_log_level)
    error_message = "log_field_log_level must be one of: ALL, ERROR, NONE."
  }
}

variable "log_exclude_verbose_content" {
  description = "Whether to exclude verbose content (headers, context, evaluated mapping templates) from logs."
  type        = bool
  default     = true
}

variable "create_cloudwatch_log_group" {
  description = "Whether to create a dedicated CloudWatch log group for the API."
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days for the API log group."
  type        = number
  default     = 14

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a valid CloudWatch retention value (0 = never expire)."
  }
}

variable "log_group_kms_key_arn" {
  description = "Optional KMS key ARN for encrypting CloudWatch logs."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.log_group_kms_key_arn))
    error_message = "log_group_kms_key_arn must be a valid KMS key ARN."
  }
}

variable "xray_enabled" {
  description = "Whether to enable X-Ray tracing for the API."
  type        = bool
  default     = false
}

# =============================================================================
# IAM Configuration (logging role)
# =============================================================================

variable "logging_role_arn" {
  description = "Existing IAM role ARN for AppSync CloudWatch logging. If null and logging is enabled, module creates one."
  type        = string
  default     = null

  validation {
    condition     = var.logging_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role\\/.+$", var.logging_role_arn))
    error_message = "logging_role_arn must be a valid IAM role ARN."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary policy to attach to module-created IAM roles."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:policy\\/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be a valid IAM policy ARN."
  }
}

# =============================================================================
# Caching Configuration
# =============================================================================

variable "caching_enabled" {
  description = "Whether to enable API caching."
  type        = bool
  default     = false
}

variable "caching_config" {
  description = "Caching configuration when caching_enabled is true."
  type = object({
    type                       = optional(string, "SMALL")
    ttl                        = optional(number, 3600)
    at_rest_encryption_enabled = optional(bool, true)
    transit_encryption_enabled = optional(bool, true)
  })
  default = {
    type                       = "SMALL"
    ttl                        = 3600
    at_rest_encryption_enabled = true
    transit_encryption_enabled = true
  }

  validation {
    condition = contains([
      "SMALL", "MEDIUM", "LARGE", "XLARGE",
      "LARGE_2X", "LARGE_4X", "LARGE_8X", "LARGE_12X"
    ], try(var.caching_config.type, "SMALL"))
    error_message = "caching_config.type must be one of: SMALL, MEDIUM, LARGE, XLARGE, LARGE_2X, LARGE_4X, LARGE_8X, LARGE_12X."
  }

  validation {
    condition     = try(var.caching_config.ttl, 3600) >= 1 && try(var.caching_config.ttl, 3600) <= 3600
    error_message = "caching_config.ttl must be between 1 and 3600 seconds."
  }
}

# =============================================================================
# Data Sources
# =============================================================================

variable "datasources" {
  description = "Map of AppSync data sources keyed by logical name."
  type = map(object({
    type             = string
    description      = optional(string)
    service_role_arn = optional(string)

    # DynamoDB
    dynamodb_config = optional(object({
      table_name             = string
      region                 = optional(string)
      use_caller_credentials = optional(bool, false)
      versioned              = optional(bool, false)
      delta_sync_config = optional(object({
        base_table_ttl        = optional(number)
        delta_sync_table_name = string
        delta_sync_table_ttl  = optional(number)
      }))
    }))

    # Lambda
    lambda_config = optional(object({
      function_arn = string
    }))

    # HTTP
    http_config = optional(object({
      endpoint = string
      authorization_config = optional(object({
        authorization_type = optional(string, "AWS_IAM")
        aws_iam_config = optional(object({
          signing_region       = optional(string)
          signing_service_name = optional(string)
        }))
      }))
    }))

    # Elasticsearch / OpenSearch
    elasticsearch_config = optional(object({
      endpoint = string
      region   = optional(string)
    }))

    # OpenSearch Serverless
    opensearchservice_config = optional(object({
      endpoint = string
      region   = optional(string)
    }))

    # Relational Database (RDS)
    relational_database_config = optional(object({
      source_type = optional(string, "RDS_HTTP_ENDPOINT")
      http_endpoint_config = object({
        db_cluster_identifier = string
        aws_secret_store_arn  = string
        database_name         = optional(string)
        schema                = optional(string)
        region                = optional(string)
      })
    }))

    # EventBridge
    event_bridge_config = optional(object({
      event_bus_arn = string
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for ds in values(var.datasources) :
      contains(["AWS_LAMBDA", "AMAZON_DYNAMODB", "AMAZON_ELASTICSEARCH", "AMAZON_OPENSEARCH_SERVICE", "HTTP", "RELATIONAL_DATABASE", "AMAZON_EVENTBRIDGE", "NONE"], ds.type)
    ])
    error_message = "Each datasource type must be one of: AWS_LAMBDA, AMAZON_DYNAMODB, AMAZON_ELASTICSEARCH, AMAZON_OPENSEARCH_SERVICE, HTTP, RELATIONAL_DATABASE, AMAZON_EVENTBRIDGE, NONE."
  }
}

# =============================================================================
# Functions (for pipeline resolvers)
# =============================================================================

variable "functions" {
  description = "Map of AppSync functions keyed by logical name. Used in pipeline resolvers."
  type = map(object({
    name            = optional(string)
    description     = optional(string)
    data_source     = string
    runtime_name    = optional(string, "APPSYNC_JS")
    runtime_version = optional(string, "1.0.0")
    code            = string
    max_batch_size  = optional(number, 0)
    sync_config = optional(object({
      conflict_detection = optional(string, "VERSION")
      conflict_handler   = optional(string, "OPTIMISTIC_CONCURRENCY")
      lambda_conflict_handler_config = optional(object({
        lambda_conflict_handler_arn = string
      }))
    }))
  }))
  default = {}
}

# =============================================================================
# Resolvers
# =============================================================================

variable "resolvers" {
  description = "Map of AppSync resolvers keyed by logical name (e.g., 'Query.getOrder')."
  type = map(object({
    type            = string
    field           = string
    data_source     = optional(string)
    kind            = optional(string, "UNIT")
    runtime_name    = optional(string, "APPSYNC_JS")
    runtime_version = optional(string, "1.0.0")
    code            = string
    max_batch_size  = optional(number, 0)

    # Pipeline resolver
    pipeline_config = optional(object({
      functions = list(string)
    }))

    # Caching
    caching_config = optional(object({
      ttl          = optional(number)
      caching_keys = optional(list(string), [])
    }))

    # Conflict resolution (for Sync/offline)
    sync_config = optional(object({
      conflict_detection = optional(string, "VERSION")
      conflict_handler   = optional(string, "OPTIMISTIC_CONCURRENCY")
      lambda_conflict_handler_config = optional(object({
        lambda_conflict_handler_arn = string
      }))
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.resolvers) :
      contains(["UNIT", "PIPELINE"], try(r.kind, "UNIT"))
    ])
    error_message = "Each resolver kind must be one of: UNIT, PIPELINE."
  }
}

# =============================================================================
# Domain Name
# =============================================================================

variable "domain_name" {
  description = "Custom domain name configuration for the API."
  type = object({
    domain_name     = string
    certificate_arn = string
    description     = optional(string)
  })
  default = null
}

# =============================================================================
# WAF Configuration
# =============================================================================

variable "waf_web_acl_arn" {
  description = "ARN of a WAFv2 Web ACL to associate with the AppSync API."
  type        = string
  default     = null

  validation {
    condition     = var.waf_web_acl_arn == null || can(regex("^arn:aws[a-zA-Z-]*:wafv2:.+$", var.waf_web_acl_arn))
    error_message = "waf_web_acl_arn must be a valid WAFv2 Web ACL ARN."
  }
}

# =============================================================================
# Merged API Configuration
# =============================================================================

variable "merged_api_execution_role_arn" {
  description = "IAM role ARN for merged API. Required when api_type is MERGED."
  type        = string
  default     = null

  validation {
    condition     = var.merged_api_execution_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role\\/.+$", var.merged_api_execution_role_arn))
    error_message = "merged_api_execution_role_arn must be a valid IAM role ARN."
  }
}

variable "source_api_associations" {
  description = "Map of source API associations for a Merged API."
  type = map(object({
    source_api_id                            = string
    source_api_association_config_merge_type = optional(string, "AUTO_MERGE")
    description                              = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for assoc in values(var.source_api_associations) :
      contains(["AUTO_MERGE", "MANUAL_MERGE"], try(assoc.source_api_association_config_merge_type, "AUTO_MERGE"))
    ])
    error_message = "source_api_associations[*].source_api_association_config_merge_type must be one of: AUTO_MERGE, MANUAL_MERGE."
  }
}

# =============================================================================
# Observability Configuration
# =============================================================================

variable "observability" {
  description = "High-level observability toggles to avoid manual per-feature alarm setup."
  type = object({
    enabled                           = optional(bool, false)
    enable_default_alarms             = optional(bool, true)
    enable_anomaly_detection_alarms   = optional(bool, false)
    enable_dashboard                  = optional(bool, false)
    default_alarm_actions             = optional(list(string), [])
    default_ok_actions                = optional(list(string), [])
    default_insufficient_data_actions = optional(list(string), [])
  })
  default = {
    enabled                           = false
    enable_default_alarms             = true
    enable_anomaly_detection_alarms   = false
    enable_dashboard                  = false
    default_alarm_actions             = []
    default_ok_actions                = []
    default_insufficient_data_actions = []
  }
}

variable "metric_alarms" {
  description = "Map of CloudWatch metric alarms keyed by logical alarm key."
  type = map(object({
    enabled                   = optional(bool, true)
    alarm_name                = optional(string)
    alarm_description         = optional(string)
    comparison_operator       = string
    evaluation_periods        = number
    metric_name               = string
    namespace                 = optional(string, "AWS/AppSync")
    period                    = number
    statistic                 = optional(string)
    extended_statistic        = optional(string)
    threshold                 = number
    datapoints_to_alarm       = optional(number)
    treat_missing_data        = optional(string)
    alarm_actions             = optional(list(string), [])
    ok_actions                = optional(list(string), [])
    insufficient_data_actions = optional(list(string), [])
    dimensions                = optional(map(string), {})
    tags                      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.metric_alarms) :
      ((try(alarm.statistic, null) != null) != (try(alarm.extended_statistic, null) != null))
    ])
    error_message = "Each metric_alarms entry must set exactly one of statistic or extended_statistic."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.metric_alarms) :
      try(alarm.treat_missing_data, null) == null || contains(["breaching", "notBreaching", "ignore", "missing"], alarm.treat_missing_data)
    ])
    error_message = "metric_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }
}

variable "metric_anomaly_alarms" {
  description = "Map of CloudWatch anomaly detection alarms keyed by logical alarm key. Each alarm uses ANOMALY_DETECTION_BAND with GraphQLAPIId dimension injected by default."
  type = map(object({
    enabled                   = optional(bool, true)
    alarm_name                = optional(string)
    alarm_description         = optional(string)
    comparison_operator       = optional(string, "GreaterThanUpperThreshold")
    evaluation_periods        = number
    metric_name               = string
    namespace                 = optional(string, "AWS/AppSync")
    period                    = number
    statistic                 = string
    anomaly_detection_stddev  = optional(number, 2)
    datapoints_to_alarm       = optional(number)
    treat_missing_data        = optional(string)
    alarm_actions             = optional(list(string), [])
    ok_actions                = optional(list(string), [])
    insufficient_data_actions = optional(list(string), [])
    dimensions                = optional(map(string), {})
    tags                      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.metric_anomaly_alarms) :
      contains([
        "GreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold"
      ], try(alarm.comparison_operator, "GreaterThanUpperThreshold"))
    ])
    error_message = "metric_anomaly_alarms[*].comparison_operator must be GreaterThanUpperThreshold, LessThanLowerThreshold, or LessThanLowerOrGreaterThanUpperThreshold."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.metric_anomaly_alarms) :
      try(alarm.treat_missing_data, null) == null || contains(["breaching", "notBreaching", "ignore", "missing"], alarm.treat_missing_data)
    ])
    error_message = "metric_anomaly_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.metric_anomaly_alarms) :
      try(alarm.anomaly_detection_stddev, 2) > 0
    ])
    error_message = "metric_anomaly_alarms[*].anomaly_detection_stddev must be greater than 0."
  }
}

variable "log_metric_filters" {
  description = "Map of CloudWatch log metric filters on the AppSync log group."
  type = map(object({
    enabled          = optional(bool, true)
    pattern          = string
    metric_namespace = string
    metric_name      = string
    metric_value     = optional(string, "1")
    default_value    = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for filter in values(var.log_metric_filters) : trimspace(filter.pattern) != "" && trimspace(filter.metric_namespace) != "" && trimspace(filter.metric_name) != ""
    ])
    error_message = "Each log_metric_filters entry must have non-empty pattern, metric_namespace, and metric_name."
  }
}
