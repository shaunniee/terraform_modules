# =============================================================================
# Queue Identity
# =============================================================================

variable "name" {
  description = "Base name for the SQS queue. `.fifo` suffix is appended automatically for FIFO queues."
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 75
    error_message = "Queue name must be 1–75 characters (leaves room for `-dlq.fifo` suffix under the 80-char limit)."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name))
    error_message = "Queue name may only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "fifo_queue" {
  description = "Whether this is a FIFO queue. When true, `.fifo` is appended to both main and DLQ names."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Queue Settings
# =============================================================================

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue (seconds). Should be >= your consumer's processing time."
  type        = number
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be 0–43200 (0s to 12h)."
  }
}

variable "message_retention_seconds" {
  description = "How long SQS retains a message (seconds). Default 4 days, max 14 days."
  type        = number
  default     = 345600

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be 60–1209600 (1 min to 14 days)."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long-poll wait time (seconds). Set >0 to enable long polling and reduce empty receives."
  type        = number
  default     = 0

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be 0–20."
  }
}

variable "delay_seconds" {
  description = "Delivery delay for new messages (seconds). Messages are invisible for this duration after being sent."
  type        = number
  default     = 0

  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "delay_seconds must be 0–900 (0s to 15min)."
  }
}

variable "max_message_size" {
  description = "Maximum message size in bytes."
  type        = number
  default     = 262144

  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 262144
    error_message = "max_message_size must be 1024–262144 (1KB to 256KB)."
  }
}

# =============================================================================
# FIFO-specific Settings
# =============================================================================

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO queues. Uses SHA-256 hash of message body as dedup ID."
  type        = bool
  default     = false
}

variable "deduplication_scope" {
  description = "Deduplication scope for FIFO queues: `messageGroup` or `queue`."
  type        = string
  default     = null

  validation {
    condition     = var.deduplication_scope == null ? true : contains(["messageGroup", "queue"], var.deduplication_scope)
    error_message = "deduplication_scope must be \"messageGroup\" or \"queue\" when provided."
  }
}

variable "fifo_throughput_limit" {
  description = "FIFO throughput limit: `perQueue` or `perMessageGroupId`. Use `perMessageGroupId` with high-throughput mode."
  type        = string
  default     = null

  validation {
    condition     = var.fifo_throughput_limit == null ? true : contains(["perQueue", "perMessageGroupId"], var.fifo_throughput_limit)
    error_message = "fifo_throughput_limit must be \"perQueue\" or \"perMessageGroupId\" when provided."
  }
}

# =============================================================================
# Encryption
# =============================================================================

variable "sqs_managed_sse_enabled" {
  description = "Enable SQS-managed server-side encryption (SSE-SQS). Mutually exclusive with `kms_master_key_id`."
  type        = bool
  default     = true
}

variable "kms_master_key_id" {
  description = "KMS key ID or ARN for SSE-KMS encryption. When set, `sqs_managed_sse_enabled` must be false."
  type        = string
  default     = null

  validation {
    condition     = var.kms_master_key_id == null ? true : length(var.kms_master_key_id) > 0
    error_message = "kms_master_key_id must be non-empty when provided."
  }
}

variable "kms_data_key_reuse_period_seconds" {
  description = "How long (seconds) SQS can reuse a KMS data key before calling KMS again. Reduces KMS costs."
  type        = number
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds must be 60–86400 (1 min to 24h)."
  }
}

# =============================================================================
# Dead-Letter Queue
# =============================================================================

variable "create_dlq" {
  description = "Whether to create a managed dead-letter queue. Mutually exclusive with `dlq_arn`."
  type        = bool
  default     = false
}

variable "dlq_arn" {
  description = "ARN of an existing external DLQ. When set, `create_dlq` must be false."
  type        = string
  default     = null

  validation {
    condition     = var.dlq_arn == null ? true : can(regex("^arn:", var.dlq_arn))
    error_message = "dlq_arn must be a valid ARN (starts with 'arn:') when provided."
  }
}

variable "max_receive_count" {
  description = "Number of receives before a message is sent to the DLQ. Only applies when a DLQ is configured."
  type        = number
  default     = 5

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be 1–1000."
  }
}

variable "dlq_message_retention_seconds" {
  description = "Message retention for the managed DLQ (seconds). Defaults to 14 days (maximum) so failed messages aren't lost."
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be 60–1209600 (1 min to 14 days)."
  }
}

variable "dlq_tags" {
  description = "Additional tags for the managed DLQ (merged with `tags`)."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Queue Policy
# =============================================================================

variable "queue_policy" {
  description = "IAM policy document (JSON string) to attach to the main queue. Use for cross-account access, SNS subscriptions, EventBridge targets, etc."
  type        = string
  default     = null

  validation {
    condition     = var.queue_policy == null ? true : can(jsondecode(var.queue_policy))
    error_message = "queue_policy must be valid JSON when provided."
  }
}

variable "dlq_queue_policy" {
  description = "IAM policy document (JSON string) to attach to the DLQ."
  type        = string
  default     = null

  validation {
    condition     = var.dlq_queue_policy == null ? true : can(jsondecode(var.dlq_queue_policy))
    error_message = "dlq_queue_policy must be valid JSON when provided."
  }
}

# =============================================================================
# Observability
# =============================================================================

variable "observability" {
  description = <<-EOT
    Observability configuration for CloudWatch alarms and dashboard.
    Set `enabled = true` to activate alarms and dashboard.
  EOT
  type = object({
    enabled                  = optional(bool, false)
    enable_default_alarms    = optional(bool, true)
    enable_dlq_alarm         = optional(bool, true)
    enable_zero_sends_alarm  = optional(bool, false)  # Opt-in: alarm when no messages sent for N periods
    enable_empty_receives_alarm = optional(bool, false) # Opt-in: alarm when too many empty receives (polling inefficiency)
    enable_anomaly_detection_alarms = optional(bool, false) # Opt-in: ANOMALY_DETECTION_BAND alarms
    enable_dashboard         = optional(bool, true)

    # Default alarm thresholds
    queue_depth_threshold          = optional(number, 1000)   # ApproximateNumberOfMessagesVisible
    oldest_message_age_threshold   = optional(number, 3600)   # ApproximateAgeOfOldestMessage (seconds)
    dlq_depth_threshold            = optional(number, 1)      # DLQ ApproximateNumberOfMessagesVisible
    zero_sends_evaluation_periods  = optional(number, 3)      # Consecutive 5-min periods with 0 sends before alarm
    empty_receives_threshold       = optional(number, 1000)   # NumberOfEmptyReceives per 5 minutes

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
    condition     = try(var.observability.queue_depth_threshold, 1000) >= 1
    error_message = "observability.queue_depth_threshold must be >= 1."
  }

  validation {
    condition     = try(var.observability.oldest_message_age_threshold, 3600) >= 1
    error_message = "observability.oldest_message_age_threshold must be >= 1."
  }

  validation {
    condition     = try(var.observability.dlq_depth_threshold, 1) >= 1
    error_message = "observability.dlq_depth_threshold must be >= 1."
  }

  validation {
    condition     = try(var.observability.zero_sends_evaluation_periods, 3) >= 1
    error_message = "observability.zero_sends_evaluation_periods must be >= 1."
  }

  validation {
    condition     = try(var.observability.empty_receives_threshold, 1000) >= 1
    error_message = "observability.empty_receives_threshold must be >= 1."
  }
}

# =============================================================================
# Custom CloudWatch Alarms
# =============================================================================

variable "cloudwatch_metric_alarms" {
  description = <<-EOT
    Map of custom CloudWatch alarms for the SQS queue (AWS/SQS namespace).
    These are merged on top of any default alarms. Use `queue = "main"` or `"dlq"` to target.
  EOT
  type = map(object({
    queue               = optional(string, "main") # "main" or "dlq"
    metric_name         = string
    comparison_operator = string
    threshold           = optional(number)
    evaluation_periods  = optional(number, 2)
    period              = optional(number, 300)
    statistic           = optional(string, "Sum")
    extended_statistic  = optional(string) # e.g. "p95" — mutually exclusive with statistic
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
      for k, v in var.cloudwatch_metric_alarms : contains(["main", "dlq"], v.queue)
    ])
    error_message = "cloudwatch_metric_alarms[*].queue must be \"main\" or \"dlq\"."
  }

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
    Map of CloudWatch anomaly-detection alarms for the SQS queue.
    Merged on top of the default anomaly alarms (queue_depth_anomaly, message_age_anomaly).
    User-supplied alarms override defaults on key collision.
  EOT
  type = map(object({
    enabled                  = optional(bool, true)
    metric_name              = string
    comparison_operator      = string
    statistic                = optional(string, "Maximum")
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

# =============================================================================
# Cross-cutting Validations
# =============================================================================

check "validate_encryption_mutual_exclusivity" {
  assert {
    condition     = !(var.sqs_managed_sse_enabled && var.kms_master_key_id != null)
    error_message = "sqs_managed_sse_enabled and kms_master_key_id are mutually exclusive. Use one or the other."
  }
}

check "validate_dlq_mutual_exclusivity" {
  assert {
    condition     = !(var.create_dlq && var.dlq_arn != null)
    error_message = "create_dlq and dlq_arn are mutually exclusive. Either create a managed DLQ or reference an external one."
  }
}

check "validate_fifo_features" {
  assert {
    condition = var.fifo_queue ? true : (
      var.content_based_deduplication == false &&
      var.deduplication_scope == null &&
      var.fifo_throughput_limit == null
    )
    error_message = "content_based_deduplication, deduplication_scope, and fifo_throughput_limit require fifo_queue = true."
  }
}

check "validate_dlq_alarm_requires_dlq" {
  assert {
    condition = try(var.observability.enable_dlq_alarm, true) ? (var.create_dlq || var.dlq_arn != null || !try(var.observability.enabled, false)) : true
    error_message = "observability.enable_dlq_alarm requires either create_dlq = true or dlq_arn to be set when observability is enabled."
  }
}