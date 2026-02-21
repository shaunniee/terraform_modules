variable "event_buses" {
  description = "List of EventBridge event buses to create. Use name = \"default\" to attach rules to the default bus without creating a new bus resource."
  type = list(object({
    name             = string
    description      = optional(string)
    tags             = optional(map(string), {})
    prevent_destroy  = optional(bool, false)
    rules = optional(list(object({
      name                = string
      description         = optional(string)
      is_enabled          = optional(bool, true)
      event_pattern       = optional(string) # JSON pattern as string
      schedule_expression = optional(string)
      tags                = optional(map(string), {})
      targets = optional(list(object({
        arn             = string
        id              = string
        input           = optional(string)
        input_path      = optional(string)
        role_arn        = optional(string)
        dead_letter_arn = optional(string)
        retry_policy = optional(object({
          maximum_event_age_in_seconds = optional(number)
          maximum_retry_attempts       = optional(number)
        }))
        input_transformer = optional(object({
          input_paths_map = optional(map(string))
          input_template  = string
        }))
        create_lambda_permission       = optional(bool, true)
        lambda_permission_statement_id = optional(string)
        lambda_function_name           = optional(string)
        lambda_qualifier               = optional(string)

        # --- Specialized target blocks (all optional) ---
        ecs_target = optional(object({
          task_definition_arn = string
          task_count          = optional(number, 1)
          launch_type         = optional(string) # FARGATE | EC2 | EXTERNAL
          platform_version    = optional(string)
          group               = optional(string)
          enable_execute_command = optional(bool, false)
          enable_ecs_managed_tags = optional(bool, false)
          propagate_tags       = optional(string) # TASK_DEFINITION
          tags                 = optional(map(string), {})
          network_configuration = optional(object({
            subnets          = list(string)
            security_groups  = optional(list(string), [])
            assign_public_ip = optional(bool, false)
          }))
          capacity_provider_strategy = optional(list(object({
            capacity_provider = string
            weight            = optional(number, 1)
            base              = optional(number, 0)
          })), [])
          placement_constraint = optional(list(object({
            type       = string
            expression = optional(string)
          })), [])
        }))
        kinesis_target = optional(object({
          partition_key_path = optional(string)
        }))
        sqs_target = optional(object({
          message_group_id = optional(string)
        }))
        http_target = optional(object({
          header_parameters       = optional(map(string), {})
          query_string_parameters = optional(map(string), {})
          path_parameter_values   = optional(list(string), [])
        }))
        batch_target = optional(object({
          job_definition = string
          job_name       = string
          array_size     = optional(number)
          job_attempts   = optional(number)
        }))
      })), [])
    })), [])
  }))
  default = []

  # ---- Name uniqueness / non-empty ----

  validation {
    condition     = length(var.event_buses) == length(distinct([for bus in var.event_buses : bus.name]))
    error_message = "Each event bus name must be unique."
  }

  validation {
    condition     = alltrue([for bus in var.event_buses : length(trimspace(bus.name)) > 0])
    error_message = "Event bus names must be non-empty."
  }

  # Bus/rule/target names must not contain colons (used as composite key separator)
  validation {
    condition     = alltrue([for bus in var.event_buses : !can(regex(":", bus.name))])
    error_message = "Event bus names must not contain colons (':') — they are used as internal composite-key separators."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : !can(regex(":", rule.name))
      ]
    ]))
    error_message = "Rule names must not contain colons (':') — they are used as internal composite-key separators."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : !can(regex(":", target.id))
        ])
      ]
    ]))
    error_message = "Target ids must not contain colons (':') — they are used as internal composite-key separators."
  }

  # Bus name format: must be 'default' or match EventBridge naming convention
  validation {
    condition = alltrue([
      for bus in var.event_buses : bus.name == "default" || can(regex("^[/\\.\\-_A-Za-z0-9]+$", bus.name))
    ])
    error_message = "Event bus names must be 'default' or contain only letters, numbers, hyphens, underscores, periods, and forward slashes."
  }

  # ---- Rule validations ----

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : (
          (rule.event_pattern != null && trimspace(rule.event_pattern) != "") !=
          (rule.schedule_expression != null && trimspace(rule.schedule_expression) != "")
        )
      ]
    ]))
    error_message = "Each rule must set exactly one of event_pattern or schedule_expression (non-empty)."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : (
          rule.event_pattern == null || trimspace(rule.event_pattern) == "" || can(jsondecode(rule.event_pattern))
        )
      ]
    ]))
    error_message = "When set, event_pattern must be valid JSON."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : (
          rule.schedule_expression == null || trimspace(rule.schedule_expression) == "" || can(regex("^(rate|cron)\\(.+\\)$", trimspace(rule.schedule_expression)))
        )
      ]
    ]))
    error_message = "When set, schedule_expression must look like rate(...) or cron(...)."
  }

  # Schedule rules are only on the default bus
  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : (
          rule.schedule_expression == null || trimspace(rule.schedule_expression) == "" || bus.name == "default"
        )
      ]
    ]))
    error_message = "Schedule-based rules (schedule_expression) can only be created on the default event bus."
  }

  validation {
    condition = alltrue([
      for bus in var.event_buses : (
        length(try(bus.rules, [])) == length(distinct([for rule in try(bus.rules, []) : rule.name]))
      )
    ])
    error_message = "Rule names must be unique within each event bus."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : length(trimspace(rule.name)) > 0
      ]
    ]))
    error_message = "Rule names must be non-empty."
  }

  # ---- Target validations ----

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : (
          length(coalesce(rule.targets, [])) == length(distinct([for target in coalesce(rule.targets, []) : target.id]))
        )
      ]
    ]))
    error_message = "Target ids must be unique within each rule."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : length(trimspace(target.id)) > 0
        ])
      ]
    ]))
    error_message = "Target ids must be non-empty."
  }

  # input, input_path, input_transformer are mutually exclusive
  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : (
            length([
              for v in [
                try(target.input, null) != null ? 1 : null,
                try(target.input_path, null) != null ? 1 : null,
                try(target.input_transformer, null) != null ? 1 : null
              ] : v if v != null
            ]) <= 1
          )
        ])
      ]
    ]))
    error_message = "A target can set at most one of input, input_path, or input_transformer."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : can(regex("^arn:", target.arn))
        ])
      ]
    ]))
    error_message = "Each target arn must be a valid ARN string starting with 'arn:'."
  }

  # role_arn format validation
  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : (
            try(target.role_arn, null) == null || can(regex("^arn:aws:iam::[0-9]+:role/", target.role_arn))
          )
        ])
      ]
    ]))
    error_message = "When set, role_arn must be a valid IAM role ARN (arn:aws:iam::<account>:role/...)."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : (
            try(target.dead_letter_arn, null) == null || can(regex("^arn:", target.dead_letter_arn))
          )
        ])
      ]
    ]))
    error_message = "When set, dead_letter_arn must be a valid ARN string starting with 'arn:'."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : (
            try(target.retry_policy.maximum_event_age_in_seconds, null) == null ||
            (
              target.retry_policy.maximum_event_age_in_seconds >= 60 &&
              target.retry_policy.maximum_event_age_in_seconds <= 86400
            )
          )
        ])
      ]
    ]))
    error_message = "retry_policy.maximum_event_age_in_seconds must be between 60 and 86400 when set."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : (
            try(target.retry_policy.maximum_retry_attempts, null) == null ||
            (
              target.retry_policy.maximum_retry_attempts >= 0 &&
              target.retry_policy.maximum_retry_attempts <= 185
            )
          )
        ])
      ]
    ]))
    error_message = "retry_policy.maximum_retry_attempts must be between 0 and 185 when set."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : alltrue([
          for target in coalesce(rule.targets, []) : (
            try(target.lambda_permission_statement_id, null) == null ||
            can(regex("^[A-Za-z0-9_-]{1,100}$", target.lambda_permission_statement_id))
          )
        ])
      ]
    ]))
    error_message = "lambda_permission_statement_id must be 1-100 chars using letters, numbers, hyphens, or underscores."
  }
}

variable "lambda_permission_statement_id_prefix" {
  description = "Prefix used when auto-generating Lambda permission statement IDs for EventBridge targets."
  type        = string
  default     = "AllowExecutionFromEventBridge"

  validation {
    condition     = length(trimspace(var.lambda_permission_statement_id_prefix)) > 0 && can(regex("^[A-Za-z0-9_-]{1,80}$", var.lambda_permission_statement_id_prefix))
    error_message = "lambda_permission_statement_id_prefix must be 1-80 chars using letters, numbers, hyphens, or underscores."
  }
}

# =============================================================================
# Observability — boolean toggles for alarms & dashboard
# =============================================================================

variable "observability" {
  description = <<-EOT
    Observability configuration with boolean toggles.
    - enabled                                    : master switch for all observability features
    - enable_default_alarms                      : auto-create bus-level ThrottledRules + InvocationsSentToDLQ + InvocationsFailedToBeSentToDLQ alarms
    - enable_per_rule_failed_invocation_alarms   : auto-create per-rule FailedInvocations alarms
    - enable_dropped_events_alarm                : auto-create per-bus DroppedEvents alarm (events matching no rule)
    - enable_dashboard                           : create a CloudWatch dashboard
    - enable_event_logging                       : create per-bus catch-all rules that send all events to CloudWatch Logs
    - event_log_retention_in_days                : retention for event log groups (0 = never expire)
    - event_log_kms_key_arn                      : KMS key for event log group encryption
    - default_alarm_actions / ok_actions / insufficient_data_actions : SNS topic ARNs for default alarms
  EOT
  type = object({
    enabled                                  = optional(bool, false)
    enable_default_alarms                    = optional(bool, true)
    enable_per_rule_failed_invocation_alarms = optional(bool, true)
    enable_dashboard                         = optional(bool, false)
    enable_dropped_events_alarm              = optional(bool, true)
    enable_event_logging                     = optional(bool, false)
    event_log_retention_in_days              = optional(number, 14)
    event_log_kms_key_arn                    = optional(string)
    default_alarm_actions                    = optional(list(string), [])
    default_ok_actions                       = optional(list(string), [])
    default_insufficient_data_actions        = optional(list(string), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_alarm_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_alarm_actions must contain valid ARNs."
  }

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_ok_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_ok_actions must contain valid ARNs."
  }

  validation {
    condition = alltrue([
      for arn in try(var.observability.default_insufficient_data_actions, []) : can(regex("^arn:", arn))
    ])
    error_message = "observability.default_insufficient_data_actions must contain valid ARNs."
  }

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], try(var.observability.event_log_retention_in_days, 14))
    error_message = "observability.event_log_retention_in_days must be a valid CloudWatch Logs retention value (0 = never expire)."
  }

  validation {
    condition     = try(var.observability.event_log_kms_key_arn, null) == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.observability.event_log_kms_key_arn))
    error_message = "observability.event_log_kms_key_arn must be a valid KMS key ARN when provided."
  }
}

# =============================================================================
# Module-level tags
# =============================================================================

variable "tags" {
  description = "A map of tags applied to all taggable resources created by this module."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Event Archives
# =============================================================================

variable "archives" {
  description = <<-EOT
    List of EventBridge event archives to create.
    Set bus_name to reference a bus managed by this module, or event_source_arn for an external source.
  EOT
  type = list(object({
    name               = string
    description        = optional(string)
    event_source_arn   = optional(string)
    bus_name           = optional(string)
    event_pattern      = optional(string)
    retention_days     = optional(number, 0)
  }))
  default = []

  validation {
    condition     = length(var.archives) == length(distinct([for a in var.archives : a.name]))
    error_message = "Archive names must be unique."
  }

  validation {
    condition = alltrue([
      for a in var.archives : a.event_source_arn != null || a.bus_name != null
    ])
    error_message = "Each archive must specify either event_source_arn or bus_name."
  }

  validation {
    condition = alltrue([
      for a in var.archives : (
        try(a.event_pattern, null) == null || can(jsondecode(a.event_pattern))
      )
    ])
    error_message = "When set, archive event_pattern must be valid JSON."
  }

  validation {
    condition = alltrue([
      for a in var.archives : a.retention_days >= 0
    ])
    error_message = "retention_days must be >= 0 (0 = indefinite)."
  }

}

# =============================================================================
# Event Bus Policies (cross-account)
# =============================================================================

variable "bus_policies" {
  description = <<-EOT
    List of event bus resource policies. Each entry attaches a JSON policy to the specified bus.
    bus_name must reference a bus managed by this module (or 'default').
  EOT
  type = list(object({
    bus_name = string
    policy   = string
  }))
  default = []

  validation {
    condition     = length(var.bus_policies) == length(distinct([for p in var.bus_policies : p.bus_name]))
    error_message = "Only one policy per bus is allowed."
  }

  validation {
    condition = alltrue([
      for p in var.bus_policies : can(jsondecode(p.policy))
    ])
    error_message = "Each bus policy must be valid JSON."
  }
}

variable "cloudwatch_metric_alarms" {
  description = "CloudWatch metric alarms to create for EventBridge. Use rule_key to auto-populate EventBusName and RuleName dimensions from module-managed rules."
  type = map(object({
    enabled                   = optional(bool, true)
    alarm_name                = optional(string)
    alarm_description         = optional(string)
    comparison_operator       = string
    evaluation_periods        = number
    datapoints_to_alarm       = optional(number)
    metric_name               = string
    namespace                 = optional(string, "AWS/Events")
    period                    = number
    statistic                 = optional(string, "Sum")
    extended_statistic        = optional(string)
    threshold                 = number
    treat_missing_data        = optional(string)
    unit                      = optional(string)
    actions_enabled           = optional(bool, true)
    alarm_actions             = optional(list(string), [])
    ok_actions                = optional(list(string), [])
    insufficient_data_actions = optional(list(string), [])
    rule_key                  = optional(string)
    event_bus_name            = optional(string)
    dimensions                = optional(map(string), {})
    tags                      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_alarms : contains([
        "GreaterThanOrEqualToThreshold",
        "GreaterThanThreshold",
        "LessThanThreshold",
        "LessThanOrEqualToThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "GreaterThanUpperThreshold"
      ], alarm.comparison_operator)
    ])
    error_message = "cloudwatch_metric_alarms[*].comparison_operator must be a valid CloudWatch comparison operator."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_alarms : try(alarm.treat_missing_data, null) == null || contains([
        "breaching",
        "notBreaching",
        "ignore",
        "missing"
      ], alarm.treat_missing_data)
    ])
    error_message = "cloudwatch_metric_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_alarms : try(alarm.rule_key, null) == null || can(regex("^[^:]+:[^:]+$", trimspace(alarm.rule_key)))
    ])
    error_message = "cloudwatch_metric_alarms[*].rule_key must be in '<bus_name>:<rule_name>' format when provided."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_alarms : !(
        try(alarm.statistic, null) != null && try(alarm.extended_statistic, null) != null
      )
    ])
    error_message = "cloudwatch_metric_alarms[*]: statistic and extended_statistic are mutually exclusive — set only one."
  }
}

variable "dlq_cloudwatch_metric_alarms" {
  description = "CloudWatch metric alarms for DLQs attached to module-managed Lambda targets. Uses AWS/SQS metrics with QueueName dimension resolved from target_key/dead_letter_arn/queue_name."
  type = map(object({
    enabled                   = optional(bool, true)
    alarm_name                = optional(string)
    alarm_description         = optional(string)
    comparison_operator       = string
    evaluation_periods        = number
    datapoints_to_alarm       = optional(number)
    metric_name               = string
    namespace                 = optional(string, "AWS/SQS")
    period                    = number
    statistic                 = optional(string, "Sum")
    extended_statistic        = optional(string)
    threshold                 = number
    treat_missing_data        = optional(string)
    unit                      = optional(string)
    actions_enabled           = optional(bool, true)
    alarm_actions             = optional(list(string), [])
    ok_actions                = optional(list(string), [])
    insufficient_data_actions = optional(list(string), [])
    target_key                = optional(string)
    dead_letter_arn           = optional(string)
    queue_name                = optional(string)
    dimensions                = optional(map(string), {})
    tags                      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, alarm in var.dlq_cloudwatch_metric_alarms : contains([
        "GreaterThanOrEqualToThreshold",
        "GreaterThanThreshold",
        "LessThanThreshold",
        "LessThanOrEqualToThreshold",
        "LessThanLowerOrGreaterThanUpperThreshold",
        "LessThanLowerThreshold",
        "GreaterThanUpperThreshold"
      ], alarm.comparison_operator)
    ])
    error_message = "dlq_cloudwatch_metric_alarms[*].comparison_operator must be a valid CloudWatch comparison operator."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.dlq_cloudwatch_metric_alarms : try(alarm.treat_missing_data, null) == null || contains([
        "breaching",
        "notBreaching",
        "ignore",
        "missing"
      ], alarm.treat_missing_data)
    ])
    error_message = "dlq_cloudwatch_metric_alarms[*].treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.dlq_cloudwatch_metric_alarms : try(alarm.target_key, null) == null || can(regex("^[^:]+:[^:]+:[^:]+$", trimspace(alarm.target_key)))
    ])
    error_message = "dlq_cloudwatch_metric_alarms[*].target_key must be in '<bus_name>:<rule_name>:<target_id>' format when provided."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.dlq_cloudwatch_metric_alarms : try(alarm.dead_letter_arn, null) == null || can(regex("^arn:", alarm.dead_letter_arn))
    ])
    error_message = "dlq_cloudwatch_metric_alarms[*].dead_letter_arn must be a valid ARN when provided."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.dlq_cloudwatch_metric_alarms : !(
        try(alarm.statistic, null) != null && try(alarm.extended_statistic, null) != null
      )
    ])
    error_message = "dlq_cloudwatch_metric_alarms[*]: statistic and extended_statistic are mutually exclusive — set only one."
  }
}

variable "cloudwatch_metric_anomaly_alarms" {
  description = "CloudWatch anomaly detection alarms for EventBridge metrics. Uses ANOMALY_DETECTION_BAND to alert on unusual patterns without static thresholds."
  type = map(object({
    enabled             = optional(bool, true)
    alarm_name          = optional(string)
    alarm_description   = optional(string)
    evaluation_periods  = optional(number, 2)
    metric_name         = string
    namespace           = optional(string, "AWS/Events")
    period              = optional(number, 300)
    statistic           = optional(string, "Sum")
    band_width          = optional(number, 2)
    actions_enabled     = optional(bool, true)
    alarm_actions       = optional(list(string), [])
    ok_actions          = optional(list(string), [])
    insufficient_data_actions = optional(list(string), [])
    rule_key            = optional(string)
    event_bus_name      = optional(string)
    dimensions          = optional(map(string), {})
    tags                = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_anomaly_alarms : try(alarm.rule_key, null) == null || can(regex("^[^:]+:[^:]+$", trimspace(alarm.rule_key)))
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].rule_key must be in '<bus_name>:<rule_name>' format when provided."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_anomaly_alarms : try(alarm.band_width, 2) > 0
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].band_width must be greater than 0."
  }

  validation {
    condition = alltrue([
      for _, alarm in var.cloudwatch_metric_anomaly_alarms : try(alarm.evaluation_periods, 2) >= 1
    ])
    error_message = "cloudwatch_metric_anomaly_alarms[*].evaluation_periods must be >= 1."
  }
}

# =============================================================================
# EventBridge Connections (for API Destinations / HTTP targets)
# =============================================================================

variable "connections" {
  description = <<-EOT
    EventBridge connections for API destination targets.
    Each connection defines an authorization method (API_KEY, BASIC, or OAUTH_CLIENT_CREDENTIALS) used by API destinations.
  EOT
  type = map(object({
    description         = optional(string)
    authorization_type  = string # API_KEY | BASIC | OAUTH_CLIENT_CREDENTIALS
    auth_parameters = object({
      api_key = optional(object({
        key   = string
        value = string
      }))
      basic = optional(object({
        username = string
        password = string
      }))
      oauth = optional(object({
        authorization_endpoint = string
        http_method            = string
        client_parameters = object({
          client_id     = string
          client_secret = string
        })
        body_parameters     = optional(map(string), {})
        header_parameters   = optional(map(string), {})
        query_string_parameters = optional(map(string), {})
      }))
      invocation_http_parameters = optional(object({
        body   = optional(list(object({ key = string, value = string, is_value_secret = optional(bool, false) })), [])
        header = optional(list(object({ key = string, value = string, is_value_secret = optional(bool, false) })), [])
        query_string = optional(list(object({ key = string, value = string, is_value_secret = optional(bool, false) })), [])
      }))
    })
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, conn in var.connections : contains(["API_KEY", "BASIC", "OAUTH_CLIENT_CREDENTIALS"], conn.authorization_type)
    ])
    error_message = "connections[*].authorization_type must be one of API_KEY, BASIC, or OAUTH_CLIENT_CREDENTIALS."
  }
}

# =============================================================================
# EventBridge API Destinations
# =============================================================================

variable "api_destinations" {
  description = <<-EOT
    EventBridge API destinations for HTTP/webhook targets.
    Each API destination uses a connection (by key) and defines an endpoint + http_method.
  EOT
  type = map(object({
    description                      = optional(string)
    invocation_endpoint              = string
    http_method                      = string # GET | POST | PUT | DELETE | PATCH | HEAD | OPTIONS
    invocation_rate_limit_per_second = optional(number, 300)
    connection_key                   = string # Key into var.connections
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, dest in var.api_destinations : contains(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"], dest.http_method)
    ])
    error_message = "api_destinations[*].http_method must be a valid HTTP method."
  }

  validation {
    condition = alltrue([
      for _, dest in var.api_destinations : dest.invocation_rate_limit_per_second >= 1 && dest.invocation_rate_limit_per_second <= 300
    ])
    error_message = "api_destinations[*].invocation_rate_limit_per_second must be between 1 and 300."
  }

  validation {
    condition = alltrue([
      for _, dest in var.api_destinations : can(regex("^https://", dest.invocation_endpoint))
    ])
    error_message = "api_destinations[*].invocation_endpoint must start with https://."
  }
}

# =============================================================================
# EventBridge Schema Registries
# =============================================================================

variable "schema_registries" {
  description = <<-EOT
    EventBridge schema registries to create.
    Schema registries are namespaces for organizing event schemas.
    The built-in 'aws.events' and 'discovered-schemas' registries are managed by AWS and cannot be created here.
  EOT
  type = map(object({
    description = optional(string)
    tags        = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, _ in var.schema_registries : !contains(["aws.events", "discovered-schemas"], name)
    ])
    error_message = "schema_registries cannot use reserved names 'aws.events' or 'discovered-schemas' — these are managed by AWS."
  }

  validation {
    condition = alltrue([
      for name, _ in var.schema_registries : can(regex("^[A-Za-z][A-Za-z0-9._-]{0,63}$", name))
    ])
    error_message = "Schema registry names must start with a letter, be 1-64 chars, and contain only letters, numbers, dots, hyphens, or underscores."
  }
}

# =============================================================================
# EventBridge Schemas
# =============================================================================

variable "schemas" {
  description = <<-EOT
    EventBridge schemas to create within registries.
    Each schema defines an event contract (OpenAPI 3.0 or JSONSchemaDraft4).
    The registry_key must reference a registry managed by this module.
  EOT
  type = map(object({
    registry_key = string          # Key into var.schema_registries
    type         = string          # OpenApi3 | JSONSchemaDraft4
    description  = optional(string)
    content      = string          # JSON or YAML schema body
    tags         = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, schema in var.schemas : contains(["OpenApi3", "JSONSchemaDraft4"], schema.type)
    ])
    error_message = "schemas[*].type must be 'OpenApi3' or 'JSONSchemaDraft4'."
  }

  validation {
    condition = alltrue([
      for _, schema in var.schemas : length(trimspace(schema.content)) > 0
    ])
    error_message = "schemas[*].content must be non-empty."
  }

  validation {
    condition = alltrue([
      for name, _ in var.schemas : can(regex("^[A-Za-z][A-Za-z0-9._@-]{0,384}$", name))
    ])
    error_message = "Schema names must start with a letter, be 1-385 chars, and contain only letters, numbers, dots, hyphens, underscores, or '@'."
  }
}

# =============================================================================
# EventBridge Schema Discoverers
# =============================================================================

variable "schema_discoverers" {
  description = <<-EOT
    EventBridge schema discoverers — automatically detect and register schemas
    from events flowing through a bus. Each discoverer is attached to exactly
    one event bus managed by this module (use bus_name key).
  EOT
  type = map(object({
    bus_name    = string           # Key into var.event_buses (bus name)
    description = optional(string)
    tags        = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, d in var.schema_discoverers : length(trimspace(d.bus_name)) > 0
    ])
    error_message = "schema_discoverers[*].bus_name must be non-empty."
  }
}

# =============================================================================
# EventBridge Pipes
# =============================================================================

variable "pipes" {
  description = <<-EOT
    Map of EventBridge Pipes to create. Each pipe connects a source to a target
    with optional filtering, enrichment, and logging.
  EOT
  type = map(object({
    description   = optional(string)
    desired_state = optional(string, "RUNNING") # RUNNING | STOPPED
    role_arn      = string                       # IAM role ARN for the pipe
    tags          = optional(map(string), {})

    source     = string # Source ARN (SQS, Kinesis, DynamoDB, MSK, etc.)
    source_parameters = optional(object({
      # ── Filtering ──
      filter_criteria = optional(object({
        filters = optional(list(object({
          pattern = string # JSON filter pattern
        })), [])
      }))

      # ── SQS source ──
      sqs = optional(object({
        batch_size                         = optional(number, 10)
        maximum_batching_window_in_seconds = optional(number, 0)
      }))

      # ── Kinesis source ──
      kinesis_stream = optional(object({
        starting_position              = string # TRIM_HORIZON | AT_TIMESTAMP | LATEST
        batch_size                     = optional(number, 100)
        maximum_batching_window_in_seconds = optional(number, 0)
        dead_letter_config = optional(object({
          arn = string
        }))
        maximum_record_age_in_seconds       = optional(number, -1)
        maximum_retry_attempts              = optional(number, -1)
        on_partial_batch_item_failure       = optional(string) # AUTOMATIC_BISECT
        parallelization_factor              = optional(number, 1)
        starting_position_timestamp         = optional(string)
      }))

      # ── DynamoDB Streams source ──
      dynamodb_stream = optional(object({
        starting_position              = string # TRIM_HORIZON | LATEST
        batch_size                     = optional(number, 100)
        maximum_batching_window_in_seconds = optional(number, 0)
        dead_letter_config = optional(object({
          arn = string
        }))
        maximum_record_age_in_seconds       = optional(number, -1)
        maximum_retry_attempts              = optional(number, -1)
        on_partial_batch_item_failure       = optional(string) # AUTOMATIC_BISECT
        parallelization_factor              = optional(number, 1)
      }))

      # ── Managed Streaming for Kafka (MSK) source ──
      managed_streaming_kafka = optional(object({
        topic_name   = string
        consumer_group_id = optional(string)
        batch_size                         = optional(number, 100)
        maximum_batching_window_in_seconds = optional(number, 0)
        starting_position                  = optional(string) # TRIM_HORIZON | LATEST
      }))

      # ── Self-managed Kafka source ──
      self_managed_kafka = optional(object({
        topic_name    = string
        servers       = list(string)
        consumer_group_id = optional(string)
        batch_size                         = optional(number, 100)
        maximum_batching_window_in_seconds = optional(number, 0)
        starting_position                  = optional(string) # TRIM_HORIZON | LATEST
        vpc = optional(object({
          security_groups = optional(list(string), [])
          subnets         = optional(list(string), [])
        }))
      }))

      # ── ActiveMQ source ──
      activemq_broker = optional(object({
        queue_name                         = string
        credentials_arn                    = string # Secrets Manager ARN
        batch_size                         = optional(number, 10)
        maximum_batching_window_in_seconds = optional(number, 0)
      }))

      # ── RabbitMQ source ──
      rabbitmq_broker = optional(object({
        queue_name                         = string
        credentials_arn                    = string # Secrets Manager ARN
        virtual_host                       = optional(string, "/")
        batch_size                         = optional(number, 10)
        maximum_batching_window_in_seconds = optional(number, 0)
      }))
    }))

    target     = string # Target ARN (Lambda, Step Functions, SQS, etc.)
    target_parameters = optional(object({
      input_template = optional(string) # Jsonpath template

      # ── Lambda target ──
      lambda_function = optional(object({
        invocation_type = optional(string, "REQUEST_RESPONSE") # REQUEST_RESPONSE | FIRE_AND_FORGET
      }))

      # ── Step Functions target ──
      step_function = optional(object({
        invocation_type = optional(string, "REQUEST_RESPONSE") # REQUEST_RESPONSE | FIRE_AND_FORGET
      }))

      # ── SQS target ──
      sqs = optional(object({
        message_group_id         = optional(string)
        message_deduplication_id = optional(string)
      }))

      # ── Kinesis target ──
      kinesis_stream = optional(object({
        partition_key = string
      }))

      # ── EventBridge target ──
      eventbridge_event_bus = optional(object({
        detail_type = optional(string)
        endpoint_id = optional(string)
        resources   = optional(list(string), [])
        source      = optional(string)
        time        = optional(string)
      }))

      # ── ECS target ──
      ecs_task = optional(object({
        task_definition_arn = string
        task_count          = optional(number, 1)
        launch_type         = optional(string) # FARGATE | EC2 | EXTERNAL
        platform_version    = optional(string)
        group               = optional(string)
        enable_ecs_managed_tags = optional(bool, false)
        enable_execute_command  = optional(bool, false)
        propagate_tags          = optional(string) # TASK_DEFINITION
        reference_id            = optional(string)
        capacity_provider_strategy = optional(list(object({
          capacity_provider = string
          weight            = optional(number, 1)
          base              = optional(number, 0)
        })), [])
        network_configuration = optional(object({
          subnets          = list(string)
          security_groups  = optional(list(string), [])
          assign_public_ip = optional(string, "DISABLED") # ENABLED | DISABLED
        }))
        overrides = optional(object({
          cpu    = optional(string)
          memory = optional(string)
          ephemeral_storage_size_in_gib = optional(number)
          execution_role_arn            = optional(string)
          task_role_arn                 = optional(string)
          inference_accelerator_overrides = optional(list(object({
            device_name = string
            device_type = string
          })), [])
          container_overrides = optional(list(object({
            name    = string
            command = optional(list(string))
            cpu     = optional(number)
            memory  = optional(number)
            memory_reservation = optional(number)
            environment = optional(list(object({
              name  = string
              value = string
            })), [])
            environment_files = optional(list(object({
              type  = string
              value = string
            })), [])
            resource_requirements = optional(list(object({
              type  = string
              value = string
            })), [])
          })), [])
        }))
      }))

      # ── CloudWatch Logs target ──
      cloudwatch_logs = optional(object({
        log_stream_name = optional(string)
        timestamp       = optional(string)
      }))

      # ── HTTP (API Destination) target ──
      http = optional(object({
        header_parameters       = optional(map(string), {})
        query_string_parameters = optional(map(string), {})
        path_parameter_values   = optional(list(string), [])
      }))

      # ── SageMaker Pipeline target ──
      sagemaker_pipeline = optional(object({
        parameters = optional(list(object({
          name  = string
          value = string
        })), [])
      }))

      # ── Batch target ──
      batch_job = optional(object({
        job_definition = string
        job_name       = string
        retry_strategy = optional(object({
          attempts = optional(number, 1)
        }))
        array_properties = optional(object({
          size = optional(number)
        }))
        depends_on = optional(list(object({
          job_id = optional(string)
          type   = optional(string) # N_TO_N | SEQUENTIAL
        })), [])
        parameters = optional(map(string), {})
        container_overrides = optional(object({
          command              = optional(list(string))
          instance_type        = optional(string)
          environment = optional(list(object({
            name  = string
            value = string
          })), [])
          resource_requirements = optional(list(object({
            type  = string
            value = string
          })), [])
        }))
      }))

      # ── Redshift target ──
      redshift_data = optional(object({
        database          = string
        sql_statements    = list(string)
        db_user           = optional(string)
        secret_manager_arn = optional(string)
        statement_name     = optional(string)
        with_event         = optional(bool, false)
      }))
    }))

    # ── Enrichment (optional) ──
    enrichment     = optional(string) # Lambda / API Gateway / Step Functions / API Destination ARN
    enrichment_parameters = optional(object({
      input_template = optional(string)
      http = optional(object({
        header_parameters       = optional(map(string), {})
        query_string_parameters = optional(map(string), {})
        path_parameter_values   = optional(list(string), [])
      }))
    }))

    # ── Logging ──
    log_configuration = optional(object({
      level = optional(string, "ERROR") # OFF | ERROR | INFO | TRACE
      cloudwatch_logs_log_destination = optional(object({
        log_group_arn = string
      }))
      firehose_log_destination = optional(object({
        delivery_stream_arn = string
      }))
      s3_log_destination = optional(object({
        bucket_name   = string
        bucket_owner  = optional(string)
        output_format = optional(string, "json") # json | plain | w3c
        prefix        = optional(string)
      }))
    }))
  }))
  default = {}

  # ── Validations ──

  validation {
    condition     = alltrue([for k, v in var.pipes : contains(["RUNNING", "STOPPED"], v.desired_state)])
    error_message = "pipes[*].desired_state must be \"RUNNING\" or \"STOPPED\"."
  }

  validation {
    condition     = alltrue([for k, v in var.pipes : can(regex("^arn:", v.role_arn))])
    error_message = "pipes[*].role_arn must be a valid ARN (starts with 'arn:')."
  }

  validation {
    condition     = alltrue([for k, v in var.pipes : can(regex("^arn:", v.source))])
    error_message = "pipes[*].source must be a valid ARN (starts with 'arn:')."
  }

  validation {
    condition     = alltrue([for k, v in var.pipes : can(regex("^arn:", v.target))])
    error_message = "pipes[*].target must be a valid ARN (starts with 'arn:')."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes : v.enrichment == null ? true : can(regex("^arn:", v.enrichment))
    ])
    error_message = "pipes[*].enrichment must be a valid ARN (starts with 'arn:') when provided."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes :
        v.log_configuration == null ? true : contains(["OFF", "ERROR", "INFO", "TRACE"], try(v.log_configuration.level, "ERROR"))
    ])
    error_message = "pipes[*].log_configuration.level must be OFF, ERROR, INFO, or TRACE."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes : length(k) > 0 && length(k) <= 64 && can(regex("^[a-zA-Z0-9._\\-]+$", k))
    ])
    error_message = "Pipe map keys must be 1-64 characters, alphanumeric with dots, hyphens, and underscores only."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes :
        v.source_parameters == null ? true : (
          v.source_parameters.sqs != null ? (
            v.source_parameters.sqs.batch_size >= 1 && v.source_parameters.sqs.batch_size <= 10000
          ) : true
        )
    ])
    error_message = "pipes[*].source_parameters.sqs.batch_size must be 1–10000."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes :
        v.source_parameters == null ? true : (
          v.source_parameters.kinesis_stream != null ? (
            contains(["TRIM_HORIZON", "AT_TIMESTAMP", "LATEST"], v.source_parameters.kinesis_stream.starting_position)
          ) : true
        )
    ])
    error_message = "pipes[*].source_parameters.kinesis_stream.starting_position must be TRIM_HORIZON, AT_TIMESTAMP, or LATEST."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes :
        v.source_parameters == null ? true : (
          v.source_parameters.dynamodb_stream != null ? (
            contains(["TRIM_HORIZON", "LATEST"], v.source_parameters.dynamodb_stream.starting_position)
          ) : true
        )
    ])
    error_message = "pipes[*].source_parameters.dynamodb_stream.starting_position must be TRIM_HORIZON or LATEST."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes :
        v.target_parameters == null ? true : (
          v.target_parameters.lambda_function != null ? (
            contains(["REQUEST_RESPONSE", "FIRE_AND_FORGET"], v.target_parameters.lambda_function.invocation_type)
          ) : true
        )
    ])
    error_message = "pipes[*].target_parameters.lambda_function.invocation_type must be REQUEST_RESPONSE or FIRE_AND_FORGET."
  }

  validation {
    condition = alltrue([
      for k, v in var.pipes :
        v.target_parameters == null ? true : (
          v.target_parameters.step_function != null ? (
            contains(["REQUEST_RESPONSE", "FIRE_AND_FORGET"], v.target_parameters.step_function.invocation_type)
          ) : true
        )
    ])
    error_message = "pipes[*].target_parameters.step_function.invocation_type must be REQUEST_RESPONSE or FIRE_AND_FORGET."
  }
}
