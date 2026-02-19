variable "event_buses" {
  description = "List of EventBridge event buses to create"
  type = list(object({
    name = string
    tags = optional(map(string), {})
    rules = optional(list(object({
      name                = string
      description         = optional(string)
      is_enabled          = optional(bool, true)
      event_pattern       = optional(string) # JSON pattern as string
      schedule_expression = optional(string)
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
        create_lambda_permission       = optional(bool, true)
        lambda_permission_statement_id = optional(string)
        lambda_function_name           = optional(string)
        lambda_qualifier               = optional(string)
      })), [])
    })), [])
  }))
  default = []

  validation {
    condition     = length(var.event_buses) == length(distinct([for bus in var.event_buses : bus.name]))
    error_message = "Each event bus name must be unique."
  }

  validation {
    condition     = alltrue([for bus in var.event_buses : length(trimspace(bus.name)) > 0])
    error_message = "Event bus names must be non-empty."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : (
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
        for rule in bus.rules : (
          rule.event_pattern == null || trimspace(rule.event_pattern) == "" || can(jsondecode(rule.event_pattern))
        )
      ]
    ]))
    error_message = "When set, event_pattern must be valid JSON."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : (
          rule.schedule_expression == null || trimspace(rule.schedule_expression) == "" || can(regex("^(rate|cron)\\(.+\\)$", trimspace(rule.schedule_expression)))
        )
      ]
    ]))
    error_message = "When set, schedule_expression must look like rate(...) or cron(...)."
  }

  validation {
    condition = alltrue([
      for bus in var.event_buses : (
        length(bus.rules) == length(distinct([for rule in bus.rules : rule.name]))
      )
    ])
    error_message = "Rule names must be unique within each event bus."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : length(trimspace(rule.name)) > 0
      ]
    ]))
    error_message = "Rule names must be non-empty."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : (
          length(coalesce(rule.targets, [])) == length(distinct([for target in coalesce(rule.targets, []) : target.id]))
        )
      ]
    ]))
    error_message = "Target ids must be unique within each rule."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : alltrue([
          for target in coalesce(rule.targets, []) : length(trimspace(target.id)) > 0
        ])
      ]
    ]))
    error_message = "Target ids must be non-empty."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : alltrue([
          for target in coalesce(rule.targets, []) : (
            !(try(target.input, null) != null && try(target.input_path, null) != null)
          )
        ])
      ]
    ]))
    error_message = "A target cannot set both input and input_path at the same time."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : alltrue([
          for target in coalesce(rule.targets, []) : can(regex("^arn:", target.arn))
        ])
      ]
    ]))
    error_message = "Each target arn must be a valid ARN string starting with 'arn:'."
  }

  validation {
    condition = alltrue(flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : alltrue([
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
        for rule in bus.rules : alltrue([
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
        for rule in bus.rules : alltrue([
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
        for rule in bus.rules : alltrue([
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
    statistic                 = string
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
    statistic                 = string
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
}
