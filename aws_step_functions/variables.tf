variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "The name of the Step Functions state machine"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,80}$", var.name))
    error_message = "name must be 1-80 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "definition" {
  description = "The Amazon States Language (ASL) JSON definition of the state machine."
  type        = string

  validation {
    condition     = can(jsondecode(var.definition))
    error_message = "definition must be valid JSON (Amazon States Language)."
  }
}

variable "type" {
  description = "The type of the state machine. Valid values: STANDARD, EXPRESS."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.type)
    error_message = "type must be one of: STANDARD, EXPRESS."
  }
}

variable "publish" {
  description = "Whether to publish a version of the state machine during creation."
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Creates a unique name beginning with the specified prefix. Conflicts with name if both are set."
  type        = string
  default     = null
}

# =============================================================================
# IAM Configuration
# =============================================================================

variable "execution_role_arn" {
  description = "Existing IAM role ARN for Step Functions execution. If null, module creates and manages a role."
  type        = string
  default     = null

  validation {
    condition     = var.execution_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role\\/.+$", var.execution_role_arn))
    error_message = "execution_role_arn must be a valid IAM role ARN."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary policy to attach to the module-created IAM role."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:policy\\/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be a valid IAM policy ARN."
  }
}

variable "additional_policy_arns" {
  description = "List of additional IAM managed policy ARNs to attach to the module-created role."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.additional_policy_arns :
      can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]*:policy\\/.+$", arn))
    ])
    error_message = "Each additional_policy_arns entry must be a valid IAM policy ARN."
  }
}

variable "inline_policies" {
  description = "Map of inline IAM policy names to JSON policy documents to attach to the module-created role."
  type        = map(string)
  default     = {}
}

variable "enable_logging_permissions" {
  description = "Whether to attach CloudWatch Logs write permissions when module manages the execution role."
  type        = bool
  default     = true
}

variable "enable_tracing_permissions" {
  description = "Whether to attach AWSXRayDaemonWriteAccess when tracing is enabled and module manages the execution role."
  type        = bool
  default     = false
}

# =============================================================================
# Logging Configuration
# =============================================================================

variable "create_cloudwatch_log_group" {
  description = "Whether to create a dedicated CloudWatch log group for the state machine."
  type        = bool
  default     = true
}

variable "logging_level" {
  description = "Defines which category of execution history events are logged. Valid values: ALL, ERROR, FATAL, OFF."
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.logging_level)
    error_message = "logging_level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

variable "logging_include_execution_data" {
  description = "Whether the execution data (input/output) is included in log events when logging is enabled."
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days for the state machine log group."
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

# =============================================================================
# Tracing Configuration
# =============================================================================

variable "tracing_enabled" {
  description = "Whether to enable X-Ray tracing for the state machine."
  type        = bool
  default     = false
}

# =============================================================================
# Encryption Configuration
# =============================================================================

variable "kms_key_id" {
  description = "KMS key ARN for encrypting state machine data at rest. If null, AWS-owned keys are used."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.kms_key_id))
    error_message = "kms_key_id must be a valid KMS key ARN."
  }
}

variable "encryption_type" {
  description = "Encryption type for the state machine. Valid values: AWS_OWNED_KEY, CUSTOMER_MANAGED_KMS_KEY."
  type        = string
  default     = "AWS_OWNED_KEY"

  validation {
    condition     = contains(["AWS_OWNED_KEY", "CUSTOMER_MANAGED_KMS_KEY"], var.encryption_type)
    error_message = "encryption_type must be one of: AWS_OWNED_KEY, CUSTOMER_MANAGED_KMS_KEY."
  }
}

# =============================================================================
# Alias and Version Configuration
# =============================================================================

variable "aliases" {
  description = "Map of Step Functions state machine aliases keyed by alias name. Each alias can route to one or two versions."
  type = map(object({
    description = optional(string)
    routing_configuration = optional(list(object({
      state_machine_version_arn = string
      weight                    = number
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for alias_name in keys(var.aliases) :
      can(regex("^[a-zA-Z0-9_-]{1,80}$", alias_name))
    ])
    error_message = "Alias names must be 1-80 characters and use letters, numbers, hyphens, or underscores."
  }

  validation {
    condition = alltrue([
      for cfg in values(var.aliases) :
      length(try(cfg.routing_configuration, [])) <= 2
    ])
    error_message = "aliases[*].routing_configuration supports a maximum of 2 routing entries (for weighted traffic shifting)."
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
    namespace                 = optional(string, "AWS/States")
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
  description = "Map of CloudWatch anomaly detection alarms keyed by logical alarm key. Each alarm uses ANOMALY_DETECTION_BAND with StateMachineArn dimension injected by default."
  type = map(object({
    enabled                   = optional(bool, true)
    alarm_name                = optional(string)
    alarm_description         = optional(string)
    comparison_operator       = optional(string, "GreaterThanUpperThreshold")
    evaluation_periods        = number
    metric_name               = string
    namespace                 = optional(string, "AWS/States")
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
  description = "Map of CloudWatch log metric filters on the state machine log group. For general-purpose log pattern matching (e.g., ERROR, TaskFailed, etc.)."
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
