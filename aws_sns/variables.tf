# =============================================================================
# Topic Identity
# =============================================================================

variable "name" {
  description = "Name of the SNS topic. `.fifo` suffix is appended automatically for FIFO topics."
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 251
    error_message = "Topic name must be 1–251 characters (leaves room for `.fifo` suffix under the 256-char limit)."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name))
    error_message = "Topic name may only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "display_name" {
  description = "Display name for the topic (shown in email \"From\" field). Max 100 characters for SMS."
  type        = string
  default     = null

  validation {
    condition     = var.display_name == null ? true : length(var.display_name) <= 256
    error_message = "display_name must be <= 256 characters (keep <= 100 for SMS topics)."
  }
}

variable "fifo_topic" {
  description = "Whether this is a FIFO topic. When true, `.fifo` is appended to the topic name."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

# =============================================================================
# FIFO Settings
# =============================================================================

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO topics. Uses SHA-256 hash of message body as dedup ID."
  type        = bool
  default     = false
}

# =============================================================================
# Encryption
# =============================================================================

variable "kms_master_key_id" {
  description = "KMS key ID, ARN, or alias for server-side encryption. Use `\"alias/aws/sns\"` for the AWS-managed key. Set to null for no encryption."
  type        = string
  default     = "alias/aws/sns"

  validation {
    condition     = var.kms_master_key_id == null ? true : length(var.kms_master_key_id) > 0
    error_message = "kms_master_key_id must be non-empty when provided."
  }
}

# =============================================================================
# Delivery & Retry
# =============================================================================

variable "delivery_policy" {
  description = "JSON delivery policy for HTTP/S endpoints. Controls retry backoff, throttle, and healthy/unhealthy retry policy."
  type        = string
  default     = null

  validation {
    condition     = var.delivery_policy == null ? true : can(jsondecode(var.delivery_policy))
    error_message = "delivery_policy must be valid JSON when provided."
  }
}

# =============================================================================
# Topic Policy
# =============================================================================

variable "topic_policy" {
  description = "IAM policy document (JSON string) for the SNS topic. Controls who can publish/subscribe."
  type        = string
  default     = null

  validation {
    condition     = var.topic_policy == null ? true : can(jsondecode(var.topic_policy))
    error_message = "topic_policy must be valid JSON when provided."
  }
}

# =============================================================================
# Data Protection
# =============================================================================

variable "data_protection_policy" {
  description = "JSON data protection policy for PII detection and masking. See AWS docs for policy structure."
  type        = string
  default     = null

  validation {
    condition     = var.data_protection_policy == null ? true : can(jsondecode(var.data_protection_policy))
    error_message = "data_protection_policy must be valid JSON when provided."
  }
}

# =============================================================================
# Archive Policy (FIFO only)
# =============================================================================

variable "archive_policy" {
  description = "JSON archive policy for FIFO topic message archiving. Only valid when `fifo_topic = true`."
  type        = string
  default     = null

  validation {
    condition     = var.archive_policy == null ? true : can(jsondecode(var.archive_policy))
    error_message = "archive_policy must be valid JSON when provided."
  }
}

# =============================================================================
# Subscriptions
# =============================================================================

variable "subscriptions" {
  description = <<-EOT
    Map of subscriptions for the topic. Keys are used as stable identifiers (reordering won't destroy/recreate).
    Supported protocols: email, email-json, sqs, lambda, http, https, sms, application, firehose.
  EOT
  type = map(object({
    protocol = string
    endpoint = string

    # Delivery options
    raw_message_delivery = optional(bool, false)
    filter_policy        = optional(string) # JSON filter policy
    filter_policy_scope  = optional(string, "MessageAttributes") # MessageAttributes | MessageBody

    # DLQ for failed deliveries
    redrive_policy = optional(string) # JSON: {"deadLetterTargetArn": "arn:..."}

    # Firehose-specific
    subscription_role_arn = optional(string)

    # HTTP/S-specific
    delivery_policy = optional(string) # Per-subscription JSON delivery policy

    # Confirmation
    confirmation_timeout_in_minutes = optional(number, 1)

    # Auto-confirm
    endpoint_auto_confirms = optional(bool, false)
  }))
  default = {}

  # Protocol validation
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : contains([
        "email", "email-json", "sqs", "lambda", "http", "https",
        "sms", "application", "firehose"
      ], v.protocol)
    ])
    error_message = "subscriptions[*].protocol must be one of: email, email-json, sqs, lambda, http, https, sms, application, firehose."
  }

  # Endpoint non-empty
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : length(trimspace(v.endpoint)) > 0
    ])
    error_message = "subscriptions[*].endpoint must be non-empty."
  }

  # Filter policy JSON validation
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : v.filter_policy == null ? true : can(jsondecode(v.filter_policy))
    ])
    error_message = "subscriptions[*].filter_policy must be valid JSON when provided."
  }

  # Filter policy scope validation
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : contains(["MessageAttributes", "MessageBody"], v.filter_policy_scope)
    ])
    error_message = "subscriptions[*].filter_policy_scope must be \"MessageAttributes\" or \"MessageBody\"."
  }

  # Redrive policy JSON validation
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : v.redrive_policy == null ? true : can(jsondecode(v.redrive_policy))
    ])
    error_message = "subscriptions[*].redrive_policy must be valid JSON when provided."
  }

  # Subscription role ARN format (required for firehose)
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : v.subscription_role_arn == null ? true : can(regex("^arn:", v.subscription_role_arn))
    ])
    error_message = "subscriptions[*].subscription_role_arn must be a valid ARN when provided."
  }

  # Firehose requires subscription_role_arn
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : v.protocol == "firehose" ? v.subscription_role_arn != null : true
    ])
    error_message = "subscriptions with protocol = \"firehose\" require subscription_role_arn."
  }

  # Per-subscription delivery policy JSON
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : v.delivery_policy == null ? true : can(jsondecode(v.delivery_policy))
    ])
    error_message = "subscriptions[*].delivery_policy must be valid JSON when provided."
  }

  # HTTP/S endpoint format
  validation {
    condition = alltrue([
      for k, v in var.subscriptions :
        contains(["http", "https"], v.protocol) ? can(regex("^https?://", v.endpoint)) : true
    ])
    error_message = "subscriptions with protocol = http/https must have an endpoint starting with http:// or https://."
  }

  # SQS/Lambda/Firehose endpoint must be ARN
  validation {
    condition = alltrue([
      for k, v in var.subscriptions :
        contains(["sqs", "lambda", "firehose", "application"], v.protocol) ? can(regex("^arn:", v.endpoint)) : true
    ])
    error_message = "subscriptions with protocol = sqs/lambda/firehose/application must have an ARN endpoint."
  }

  # Confirmation timeout range
  validation {
    condition = alltrue([
      for k, v in var.subscriptions : v.confirmation_timeout_in_minutes >= 1 && v.confirmation_timeout_in_minutes <= 10080
    ])
    error_message = "subscriptions[*].confirmation_timeout_in_minutes must be 1–10080 (1 min to 7 days)."
  }
}

# =============================================================================
# Observability
# =============================================================================

variable "observability" {
  description = <<-EOT
    Observability configuration for CloudWatch alarms and dashboard.
    Set `enabled = true` to activate.
  EOT
  type = object({
    enabled                = optional(bool, false)
    enable_default_alarms  = optional(bool, true)
    enable_dashboard       = optional(bool, true)

    # Delivery status logging
    enable_delivery_status_logging        = optional(bool, false)
    delivery_status_success_sample_rate   = optional(number, 100) # 0–100 percent
    delivery_status_iam_role_arn          = optional(string)       # Bring your own IAM role; if null, module creates one

    # Anomaly detection
    enable_anomaly_detection_alarms = optional(bool, false)

    # Default alarm thresholds
    failed_notifications_threshold    = optional(number, 1)   # NumberOfNotificationsFailed
    sms_success_rate_threshold        = optional(number, 0.9) # SMSSuccessRate (0.0–1.0)
    enable_zero_publishes_alarm       = optional(bool, false) # Opt-in: fires when no messages published
    zero_publishes_evaluation_periods = optional(number, 6)   # Eval periods for zero-publishes alarm

    # Alarm actions
    default_alarm_actions                = optional(list(string), [])
    default_ok_actions                   = optional(list(string), [])
    default_insufficient_data_actions    = optional(list(string), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_alarm_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_alarm_actions ARNs must start with 'arn:'."
  }

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_ok_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_ok_actions ARNs must start with 'arn:'."
  }

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_insufficient_data_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_insufficient_data_actions ARNs must start with 'arn:'."
  }

  validation {
    condition = try(var.observability.delivery_status_success_sample_rate, 100) >= 0 && try(var.observability.delivery_status_success_sample_rate, 100) <= 100
    error_message = "observability.delivery_status_success_sample_rate must be 0–100."
  }

  validation {
    condition = try(var.observability.delivery_status_iam_role_arn, null) == null ? true : can(regex("^arn:", var.observability.delivery_status_iam_role_arn))
    error_message = "observability.delivery_status_iam_role_arn must be a valid ARN when provided."
  }

  validation {
    condition     = try(var.observability.failed_notifications_threshold, 1) >= 1
    error_message = "observability.failed_notifications_threshold must be >= 1."
  }

  validation {
    condition = try(var.observability.sms_success_rate_threshold, 0.9) >= 0 && try(var.observability.sms_success_rate_threshold, 0.9) <= 1
    error_message = "observability.sms_success_rate_threshold must be 0.0–1.0."
  }
}

# =============================================================================
# Custom CloudWatch Alarms
# =============================================================================

variable "cloudwatch_metric_alarms" {
  description = <<-EOT
    Map of custom CloudWatch alarms for the SNS topic (AWS/SNS namespace).
    Merged on top of default alarms. User alarms override defaults on key collision.
  EOT
  type = map(object({
    metric_name         = string
    comparison_operator = string
    threshold           = optional(number)
    evaluation_periods  = optional(number, 2)
    period              = optional(number, 300)
    statistic           = optional(string, "Sum")
    extended_statistic  = optional(string)
    treat_missing_data  = optional(string, "notBreaching")
    alarm_description   = optional(string)
    alarm_actions              = optional(list(string))
    ok_actions                 = optional(list(string))
    insufficient_data_actions  = optional(list(string))
    tags                       = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_alarms : contains([
        "GreaterThanOrEqualToThreshold",
        "GreaterThanThreshold",
        "LessThanOrEqualToThreshold",
        "LessThanThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "GreaterThanUpperThreshold"
      ], v.comparison_operator)
    ])
    error_message = "cloudwatch_metric_alarms[*].comparison_operator must be a valid CloudWatch comparison operator."
  }

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_alarms : contains([
        "breaching", "notBreaching", "ignore", "missing"
      ], v.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_alarms[*].treat_missing_data must be breaching, notBreaching, ignore, or missing."
  }

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_alarms :
        !(v.statistic != null && v.statistic != "Sum" && v.extended_statistic != null) &&
        !(v.statistic == null && v.extended_statistic == null)
    ])
    error_message = "cloudwatch_metric_alarms[*]: statistic and extended_statistic are mutually exclusive; at least one must be set."
  }

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_alarms : v.evaluation_periods >= 1
    ])
    error_message = "cloudwatch_metric_alarms[*].evaluation_periods must be >= 1."
  }

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_alarms : v.period >= 10
    ])
    error_message = "cloudwatch_metric_alarms[*].period must be >= 10."
  }
}

# =============================================================================
# Anomaly Detection Alarms
# =============================================================================

variable "cloudwatch_metric_anomaly_alarms" {
  description = <<-EOT
    Map of CloudWatch anomaly-detection alarms for the SNS topic.
    Merged on top of the default anomaly alarms (publishes_anomaly, failed_anomaly).
    User-supplied alarms override defaults on key collision.
  EOT
  type = map(object({
    metric_name              = string
    comparison_operator      = string
    statistic                = optional(string, "Sum")
    period                   = optional(number, 300)
    evaluation_periods       = optional(number, 2)
    treat_missing_data       = optional(string, "notBreaching")
    anomaly_detection_stddev = optional(number, 2)
    alarm_description        = optional(string)
    alarm_actions            = optional(list(string))
    ok_actions               = optional(list(string))
    insufficient_data_actions = optional(list(string))
    tags                     = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_anomaly_alarms : contains([
        "LessThanLowerOrGreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "GreaterThanUpperThreshold"
      ], v.comparison_operator)
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].comparison_operator must be LessThanLowerOrGreaterThanUpperThreshold, LessThanLowerThreshold, or GreaterThanUpperThreshold."
  }

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_anomaly_alarms : contains([
        "breaching", "notBreaching", "ignore", "missing"
      ], v.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].treat_missing_data must be breaching, notBreaching, ignore, or missing."
  }

  validation {
    condition = alltrue([
      for k, v in var.cloudwatch_metric_anomaly_alarms : v.anomaly_detection_stddev >= 0
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].anomaly_detection_stddev must be >= 0."
  }
}
