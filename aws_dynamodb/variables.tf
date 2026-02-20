variable "table_name" {
  description = "DynamoDB table name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.table_name))
    error_message = "table_name must be 3-255 chars and only include letters, numbers, underscore, hyphen, or dot."
  }
}

variable "hash_key" {
  description = "Partition key attribute name."
  type        = string

  validation {
    condition     = trimspace(var.hash_key) != ""
    error_message = "hash_key must be non-empty."
  }
}

variable "range_key" {
  description = "Sort key attribute name (optional)."
  type        = string
  default     = null
}

variable "billing_mode" {
  description = "DynamoDB billing mode."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Read capacity units for PROVISIONED mode."
  type        = number
  default     = null

  validation {
    condition     = var.read_capacity == null || var.read_capacity >= 1
    error_message = "read_capacity must be null or >= 1."
  }
}

variable "write_capacity" {
  description = "Write capacity units for PROVISIONED mode."
  type        = number
  default     = null

  validation {
    condition     = var.write_capacity == null || var.write_capacity >= 1
    error_message = "write_capacity must be null or >= 1."
  }
}

variable "attributes" {
  description = "Attribute definitions used by table/index key schemas."
  type = list(object({
    name = string
    type = string # S | N | B
  }))

  validation {
    condition     = length(var.attributes) > 0
    error_message = "attributes must contain at least one attribute definition."
  }

  validation {
    condition     = length(distinct([for a in var.attributes : a.name])) == length(var.attributes)
    error_message = "attributes names must be unique."
  }

  validation {
    condition = alltrue([
      for a in var.attributes : contains(["S", "N", "B"], a.type)
    ])
    error_message = "attributes[*].type must be one of: S, N, B."
  }
}

variable "global_secondary_indexes" {
  description = "Global secondary indexes."
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string), [])
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default = []

  validation {
    condition     = length(distinct([for g in var.global_secondary_indexes : g.name])) == length(var.global_secondary_indexes)
    error_message = "global_secondary_indexes names must be unique."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], g.projection_type)
    ])
    error_message = "global_secondary_indexes[*].projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes :
      g.projection_type == "INCLUDE" ? length(g.non_key_attributes) > 0 : true
    ])
    error_message = "global_secondary_indexes[*].non_key_attributes must be non-empty when projection_type is INCLUDE."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes :
      try(g.read_capacity, null) == null || g.read_capacity >= 1
    ])
    error_message = "global_secondary_indexes[*].read_capacity must be null or >= 1."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes :
      try(g.write_capacity, null) == null || g.write_capacity >= 1
    ])
    error_message = "global_secondary_indexes[*].write_capacity must be null or >= 1."
  }
}

variable "local_secondary_indexes" {
  description = "Local secondary indexes."
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for l in var.local_secondary_indexes : l.name])) == length(var.local_secondary_indexes)
    error_message = "local_secondary_indexes names must be unique."
  }

  validation {
    condition = alltrue([
      for l in var.local_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], l.projection_type)
    ])
    error_message = "local_secondary_indexes[*].projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  }

  validation {
    condition = alltrue([
      for l in var.local_secondary_indexes :
      l.projection_type == "INCLUDE" ? length(l.non_key_attributes) > 0 : true
    ])
    error_message = "local_secondary_indexes[*].non_key_attributes must be non-empty when projection_type is INCLUDE."
  }
}

variable "replicas" {
  description = "Replica regions for DynamoDB global tables."
  type = list(object({
    region_name = string
    kms_key_arn = optional(string)
  }))
  default = []

  validation {
    condition     = length(distinct([for r in var.replicas : r.region_name])) == length(var.replicas)
    error_message = "replicas region_name values must be unique."
  }

  validation {
    condition = alltrue([
      for r in var.replicas : can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", r.region_name))
    ])
    error_message = "replicas[*].region_name must look like a valid AWS region (for example: us-east-1)."
  }

  validation {
    condition = alltrue([
      for r in var.replicas :
      try(r.kms_key_arn, null) == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", r.kms_key_arn))
    ])
    error_message = "replicas[*].kms_key_arn must be a valid KMS key ARN when provided."
  }
}

variable "ttl" {
  description = "TTL configuration for the table."
  type = object({
    enabled        = bool
    attribute_name = optional(string)
  })
  default = {
    enabled        = false
    attribute_name = null
  }
}

variable "stream_enabled" {
  description = "Whether DynamoDB streams are enabled."
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "When stream_enabled=true, one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  type        = string
  default     = null

  validation {
    condition     = var.stream_view_type == null || contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be null or one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Enable point-in-time recovery."
  type        = bool
  default     = true
}

variable "server_side_encryption" {
  description = "Server-side encryption configuration."
  type = object({
    enabled     = bool
    kms_key_arn = optional(string)
  })
  default = {
    enabled     = true
    kms_key_arn = null
  }

  validation {
    condition     = var.server_side_encryption.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.server_side_encryption.kms_key_arn))
    error_message = "server_side_encryption.kms_key_arn must be a valid KMS key ARN when provided."
  }
}

variable "deletion_protection_enabled" {
  description = "Enable deletion protection for the table."
  type        = bool
  default     = false
}

variable "table_class" {
  description = "DynamoDB table class."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "tags" {
  description = "Tags to apply to the table."
  type        = map(string)
  default     = {}
}

variable "observability" {
  description = "High-level observability toggles to avoid manual per-feature configuration."
  type = object({
    enabled                                             = optional(bool, false)
    enable_default_alarms                               = optional(bool, true)
    enable_anomaly_detection_alarms                     = optional(bool, false)
    enable_contributor_insights_table                   = optional(bool, true)
    enable_contributor_insights_all_global_secondary_indexes = optional(bool, true)
    enable_cloudtrail_data_events                       = optional(bool, false)
    cloudtrail_s3_bucket_name                           = optional(string)
    default_alarm_actions                               = optional(list(string), [])
    default_ok_actions                                  = optional(list(string), [])
    default_insufficient_data_actions                   = optional(list(string), [])
  })
  default = {
    enabled                                             = false
    enable_default_alarms                               = true
    enable_anomaly_detection_alarms                     = false
    enable_contributor_insights_table                   = true
    enable_contributor_insights_all_global_secondary_indexes = true
    enable_cloudtrail_data_events                       = false
    cloudtrail_s3_bucket_name                           = null
    default_alarm_actions                               = []
    default_ok_actions                                  = []
    default_insufficient_data_actions                   = []
  }

  validation {
    condition = (
      !try(var.observability.enabled, false) ||
      !try(var.observability.enable_cloudtrail_data_events, false) ||
      (
        coalesce(
          try(var.observability.cloudtrail_s3_bucket_name, null),
          try(var.cloudtrail_data_events.s3_bucket_name, null)
        ) != null &&
        trimspace(
          coalesce(
            try(var.observability.cloudtrail_s3_bucket_name, null),
            try(var.cloudtrail_data_events.s3_bucket_name, "")
          )
        ) != ""
      )
    )
    error_message = "When observability.enabled and observability.enable_cloudtrail_data_events are true, set observability.cloudtrail_s3_bucket_name (or cloudtrail_data_events.s3_bucket_name)."
  }
}

variable "cloudwatch_metric_alarms" {
  description = "Map of CloudWatch metric alarms keyed by logical alarm key. Defaults namespace to AWS/DynamoDB and injects TableName dimension."
  type = map(object({
    enabled                     = optional(bool, true)
    alarm_name                  = optional(string)
    alarm_description           = optional(string)
    comparison_operator         = string
    evaluation_periods          = number
    metric_name                 = string
    namespace                   = optional(string, "AWS/DynamoDB")
    period                      = number
    statistic                   = optional(string)
    extended_statistic          = optional(string)
    threshold                   = number
    datapoints_to_alarm         = optional(number)
    treat_missing_data          = optional(string)
    alarm_actions               = optional(list(string), [])
    ok_actions                  = optional(list(string), [])
    insufficient_data_actions   = optional(list(string), [])
    dimensions                  = optional(map(string), {})
    tags                        = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      ((try(alarm.statistic, null) != null) != (try(alarm.extended_statistic, null) != null))
    ])
    error_message = "Each cloudwatch_metric_alarms entry must set exactly one of statistic or extended_statistic."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_alarms) :
      try(alarm.treat_missing_data, null) == null || contains(["breaching", "notBreaching", "ignore", "missing"], alarm.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }
}

variable "cloudwatch_metric_anomaly_alarms" {
  description = "Map of CloudWatch anomaly detection alarms keyed by logical alarm key. Each alarm uses ANOMALY_DETECTION_BAND on a DynamoDB metric with TableName dimension injected by default."
  type = map(object({
    enabled                     = optional(bool, true)
    alarm_name                  = optional(string)
    alarm_description           = optional(string)
    comparison_operator         = optional(string, "GreaterThanUpperThreshold")
    evaluation_periods          = number
    metric_name                 = string
    namespace                   = optional(string, "AWS/DynamoDB")
    period                      = number
    statistic                   = string
    anomaly_detection_stddev    = optional(number, 2)
    datapoints_to_alarm         = optional(number)
    treat_missing_data          = optional(string)
    alarm_actions               = optional(list(string), [])
    ok_actions                  = optional(list(string), [])
    insufficient_data_actions   = optional(list(string), [])
    dimensions                  = optional(map(string), {})
    tags                        = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_anomaly_alarms) :
      contains([
        "GreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold"
      ], try(alarm.comparison_operator, "GreaterThanUpperThreshold"))
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].comparison_operator must be GreaterThanUpperThreshold, LessThanLowerThreshold, or LessThanLowerOrGreaterThanUpperThreshold."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_anomaly_alarms) :
      try(alarm.treat_missing_data, null) == null || contains(["breaching", "notBreaching", "ignore", "missing"], alarm.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition = alltrue([
      for alarm in values(var.cloudwatch_metric_anomaly_alarms) :
      try(alarm.anomaly_detection_stddev, 2) > 0
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].anomaly_detection_stddev must be greater than 0."
  }
}

variable "contributor_insights" {
  description = "Contributor Insights configuration for DynamoDB table and optional GSIs (useful for hot-key tracing/analysis)."
  type = object({
    table_enabled                         = optional(bool, false)
    all_global_secondary_indexes_enabled = optional(bool, false)
    global_secondary_index_names         = optional(list(string), [])
  })
  default = {
    table_enabled                         = false
    all_global_secondary_indexes_enabled = false
    global_secondary_index_names         = []
  }

  validation {
    condition = length(distinct(try(var.contributor_insights.global_secondary_index_names, []))) == length(try(var.contributor_insights.global_secondary_index_names, []))
    error_message = "contributor_insights.global_secondary_index_names must contain unique names."
  }

  validation {
    condition = alltrue([
      for name in try(var.contributor_insights.global_secondary_index_names, []) : contains([for g in var.global_secondary_indexes : g.name], name)
    ])
    error_message = "contributor_insights.global_secondary_index_names must reference existing global_secondary_indexes names."
  }

  validation {
    condition = !(
      try(var.contributor_insights.all_global_secondary_indexes_enabled, false) &&
      length(try(var.contributor_insights.global_secondary_index_names, [])) > 0
    )
    error_message = "Set either contributor_insights.all_global_secondary_indexes_enabled=true or contributor_insights.global_secondary_index_names, but not both."
  }
}

variable "cloudtrail_data_events" {
  description = "Optional CloudTrail data-event logging for this table (audit logging). Creates a dedicated trail writing to the provided S3 bucket."
  type = object({
    enabled                    = optional(bool, false)
    trail_name                 = optional(string)
    s3_bucket_name             = optional(string)
    kms_key_id                 = optional(string)
    enable_log_file_validation = optional(bool, true)
    include_management_events  = optional(bool, false)
    read_write_type            = optional(string, "All")
    cloud_watch_logs_enabled   = optional(bool, false)
    create_cloud_watch_logs_role = optional(bool, false)
    cloud_watch_logs_group_name = optional(string)
    cloud_watch_logs_retention_in_days = optional(number, 90)
    cloud_watch_logs_role_arn  = optional(string)
    tags                       = optional(map(string), {})
  })
  default = {
    enabled                   = false
    trail_name                = null
    s3_bucket_name            = null
    kms_key_id                = null
    enable_log_file_validation = true
    include_management_events = false
    read_write_type           = "All"
    cloud_watch_logs_enabled  = false
    create_cloud_watch_logs_role = false
    cloud_watch_logs_group_name = null
    cloud_watch_logs_retention_in_days = 90
    cloud_watch_logs_role_arn = null
    tags                      = {}
  }

  validation {
    condition     = !try(var.cloudtrail_data_events.enabled, false) || (try(var.cloudtrail_data_events.s3_bucket_name, null) != null && trimspace(var.cloudtrail_data_events.s3_bucket_name) != "")
    error_message = "cloudtrail_data_events.s3_bucket_name is required when cloudtrail_data_events.enabled is true."
  }

  validation {
    condition     = contains(["All", "ReadOnly", "WriteOnly"], try(var.cloudtrail_data_events.read_write_type, "All"))
    error_message = "cloudtrail_data_events.read_write_type must be one of All, ReadOnly, WriteOnly."
  }

  validation {
    condition     = try(var.cloudtrail_data_events.cloud_watch_logs_retention_in_days, 90) >= 1
    error_message = "cloudtrail_data_events.cloud_watch_logs_retention_in_days must be >= 1."
  }

  validation {
    condition = (
      !try(var.cloudtrail_data_events.cloud_watch_logs_enabled, false) ||
      (
        try(var.cloudtrail_data_events.cloud_watch_logs_role_arn, null) == null ||
        can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/.+$", var.cloudtrail_data_events.cloud_watch_logs_role_arn))
      )
    )
    error_message = "cloudtrail_data_events.cloud_watch_logs_role_arn must be a valid IAM role ARN when provided."
  }

  validation {
    condition = (
      !try(var.cloudtrail_data_events.cloud_watch_logs_enabled, false) ||
      (
        try(var.cloudtrail_data_events.create_cloud_watch_logs_role, false)
        ? try(var.cloudtrail_data_events.cloud_watch_logs_role_arn, null) == null
        : (try(var.cloudtrail_data_events.cloud_watch_logs_role_arn, null) != null && trimspace(var.cloudtrail_data_events.cloud_watch_logs_role_arn) != "")
      )
    )
    error_message = "When cloudtrail_data_events.cloud_watch_logs_enabled=true, set exactly one mode: create_cloud_watch_logs_role=true (module-managed role) OR provide cloud_watch_logs_role_arn (external role)."
  }
}
