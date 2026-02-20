# =============================================================================
# Custom Event Buses
# =============================================================================

resource "aws_cloudwatch_event_bus" "this" {
  for_each = { for b in var.event_buses : b.name => b if b.name != "default" }

  name        = each.value.name
  description = try(each.value.description, null)
  tags        = merge(var.tags, try(each.value.tags, {}))

  lifecycle {
    prevent_destroy = false
  }
}

# Precondition: buses with prevent_destroy = true cannot be removed by plan
resource "terraform_data" "bus_prevent_destroy_guard" {
  for_each = { for b in var.event_buses : b.name => b if b.name != "default" && try(b.prevent_destroy, false) }

  lifecycle {
    precondition {
      condition     = contains([for b in var.event_buses : b.name], each.key)
      error_message = "Event bus '${each.key}' has prevent_destroy = true and must not be removed."
    }
  }
}

# =============================================================================
# Locals — flatten nested structures into for_each-friendly maps
# =============================================================================

locals {
  # Resolve bus name → bus reference (custom bus resource or "default" string)
  bus_name_map = merge(
    { for b in var.event_buses : b.name => b.name if b.name == "default" },
    { for k, v in aws_cloudwatch_event_bus.this : k => v.name }
  )

  # Flatten rules from all buses
  rules = {
    for r in flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : {
          key      = "${bus.name}:${rule.name}"
          bus_name = bus.name
          name     = rule.name
          desc     = try(rule.description, null)
          state    = try(rule.is_enabled, true) ? "ENABLED" : "DISABLED"
          pattern  = try(rule.event_pattern, null)
          schedule = try(rule.schedule_expression, null)
          tags     = try(rule.tags, {})
        }
      ]
    ]) : r.key => r
  }

  # Flatten targets from all rules
  targets = {
    for t in flatten([
      for bus in var.event_buses : [
        for rule in try(bus.rules, []) : [
          for target in coalesce(rule.targets, []) : {
            key                            = "${bus.name}:${rule.name}:${target.id}"
            rule_key                       = "${bus.name}:${rule.name}"
            bus_name                       = bus.name
            arn                            = target.arn
            id                             = target.id
            input                          = try(target.input, null)
            input_path                     = try(target.input_path, null)
            input_transformer              = try(target.input_transformer, null)
            role_arn                       = try(target.role_arn, null)
            dead_letter_arn                = try(target.dead_letter_arn, null)
            retry_policy                   = try(target.retry_policy, null)
            create_lambda_permission       = try(target.create_lambda_permission, true)
            lambda_permission_statement_id = try(target.lambda_permission_statement_id, null)
            lambda_function_name           = try(target.lambda_function_name, null)
            lambda_qualifier               = try(target.lambda_qualifier, null)
            ecs_target                     = try(target.ecs_target, null)
            kinesis_target                 = try(target.kinesis_target, null)
            sqs_target                     = try(target.sqs_target, null)
            http_target                    = try(target.http_target, null)
            batch_target                   = try(target.batch_target, null)
          }
        ]
      ]
    ]) : t.key => t
  }

  # Lambda targets: tighter regex matching :lambda: followed by :function:
  lambda_permission_targets = {
    for key, target in local.targets : key => target
    if target.create_lambda_permission && can(regex(":lambda:[a-z0-9-]+:[0-9]+:function:", target.arn))
  }

  # Lambda targets with DLQ configured
  lambda_targets_with_dlq = {
    for key, target in local.targets : key => target
    if can(regex(":lambda:[a-z0-9-]+:[0-9]+:function:", target.arn)) && try(target.dead_letter_arn, null) != null
  }

  # =========================================================================
  # Observability
  # =========================================================================

  observability_enabled = try(var.observability.enabled, false)

  # Default per-rule alarms (FailedInvocations) — auto-created when observability is enabled
  default_per_rule_alarms = local.observability_enabled && try(var.observability.enable_per_rule_failed_invocation_alarms, true) ? {
    for rule_key, rule in local.rules :
    "failed_invocations_${rule_key}" => {
      enabled             = true
      alarm_name          = null
      alarm_description   = "FailedInvocations alarm for rule ${rule.name} on bus ${rule.bus_name}"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 2
      datapoints_to_alarm = null
      metric_name         = "FailedInvocations"
      namespace           = "AWS/Events"
      period              = 60
      statistic           = "Sum"
      extended_statistic  = null
      threshold           = 1
      treat_missing_data  = "notBreaching"
      unit                = null
      actions_enabled     = true
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      rule_key            = rule_key
      event_bus_name      = null
      dimensions          = {}
      tags                = {}
    }
  } : {}

  # Default bus-level alarms — auto-created when observability is enabled
  default_bus_level_alarms = local.observability_enabled && try(var.observability.enable_default_alarms, true) ? merge([
    for bus in var.event_buses : {
      "throttled_rules_${bus.name}" = {
        enabled             = true
        alarm_name          = null
        alarm_description   = "ThrottledRules alarm for bus ${bus.name}"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 2
        datapoints_to_alarm = null
        metric_name         = "ThrottledRules"
        namespace           = "AWS/Events"
        period              = 60
        statistic           = "Sum"
        extended_statistic  = null
        threshold           = 1
        treat_missing_data  = "notBreaching"
        unit                = null
        actions_enabled     = true
        alarm_actions       = try(var.observability.default_alarm_actions, [])
        ok_actions          = try(var.observability.default_ok_actions, [])
        insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
        rule_key            = null
        event_bus_name      = bus.name
        dimensions          = {}
        tags                = {}
      }
      "dead_letter_invocations_${bus.name}" = {
        enabled             = true
        alarm_name          = null
        alarm_description   = "InvocationsSentToDLQ alarm for bus ${bus.name}"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 2
        datapoints_to_alarm = null
        metric_name         = "InvocationsSentToDLQ"
        namespace           = "AWS/Events"
        period              = 60
        statistic           = "Sum"
        extended_statistic  = null
        threshold           = 1
        treat_missing_data  = "notBreaching"
        unit                = null
        actions_enabled     = true
        alarm_actions       = try(var.observability.default_alarm_actions, [])
        ok_actions          = try(var.observability.default_ok_actions, [])
        insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
        rule_key            = null
        event_bus_name      = bus.name
        dimensions          = {}
        tags                = {}
      }
      "invocations_failed_to_dlq_${bus.name}" = {
        enabled             = true
        alarm_name          = null
        alarm_description   = "InvocationsFailedToBeSentToDLQ alarm for bus ${bus.name} — events silently dropped when DLQ unreachable"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 2
        datapoints_to_alarm = null
        metric_name         = "InvocationsFailedToBeSentToDLQ"
        namespace           = "AWS/Events"
        period              = 60
        statistic           = "Sum"
        extended_statistic  = null
        threshold           = 1
        treat_missing_data  = "notBreaching"
        unit                = null
        actions_enabled     = true
        alarm_actions       = try(var.observability.default_alarm_actions, [])
        ok_actions          = try(var.observability.default_ok_actions, [])
        insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
        rule_key            = null
        event_bus_name      = bus.name
        dimensions          = {}
        tags                = {}
      }
    }
  ]...) : {}

  # Default per-bus DroppedEvents alarm — events that matched no rule (opt-in)
  default_dropped_events_alarms = local.observability_enabled && try(var.observability.enable_dropped_events_alarm, true) ? merge([
    for bus in var.event_buses : {
      "dropped_events_${bus.name}" = {
        enabled             = true
        alarm_name          = null
        alarm_description   = "DroppedEvents alarm for bus ${bus.name} — events matching no rule"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        evaluation_periods  = 2
        datapoints_to_alarm = null
        metric_name         = "DroppedEvents"
        namespace           = "AWS/Events"
        period              = 300
        statistic           = "Sum"
        extended_statistic  = null
        threshold           = 1
        treat_missing_data  = "notBreaching"
        unit                = null
        actions_enabled     = true
        alarm_actions       = try(var.observability.default_alarm_actions, [])
        ok_actions          = try(var.observability.default_ok_actions, [])
        insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
        rule_key            = null
        event_bus_name      = bus.name
        dimensions          = {}
        tags                = {}
      }
    }
  ]...) : {}

  # Merge default + user alarms (user overrides defaults on same key)
  effective_cloudwatch_metric_alarms = merge(
    local.default_per_rule_alarms,
    local.default_bus_level_alarms,
    local.default_dropped_events_alarms,
    var.cloudwatch_metric_alarms
  )

  enabled_cloudwatch_metric_alarms = {
    for alarm_key, alarm in local.effective_cloudwatch_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  cloudwatch_metric_alarm_default_dimensions = {
    for alarm_key, alarm in local.enabled_cloudwatch_metric_alarms :
    alarm_key => merge(
      try(alarm.rule_key, null) != null && contains(keys(local.rules), alarm.rule_key) ? {
        EventBusName = local.rules[alarm.rule_key].bus_name
        RuleName     = local.rules[alarm.rule_key].name
      } : {},
      try(alarm.event_bus_name, null) != null ? {
        EventBusName = alarm.event_bus_name
      } : {}
    )
  }

  # DLQ alarms
  enabled_dlq_cloudwatch_metric_alarms = {
    for alarm_key, alarm in var.dlq_cloudwatch_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  dlq_cloudwatch_metric_alarm_resolved_queue_name = {
    for alarm_key, alarm in local.enabled_dlq_cloudwatch_metric_alarms :
    alarm_key => coalesce(
      try(alarm.queue_name, null),
      try(element(split(":", alarm.dead_letter_arn), 5), null),
      try(element(split(":", local.lambda_targets_with_dlq[alarm.target_key].dead_letter_arn), 5), null)
    )
  }

  dlq_cloudwatch_metric_alarm_default_dimensions = {
    for alarm_key, alarm in local.enabled_dlq_cloudwatch_metric_alarms :
    alarm_key => merge(
      local.dlq_cloudwatch_metric_alarm_resolved_queue_name[alarm_key] != null ? {
        QueueName = local.dlq_cloudwatch_metric_alarm_resolved_queue_name[alarm_key]
      } : {},
      try(alarm.dimensions, {})
    )
  }

  # Anomaly detection alarms
  enabled_anomaly_alarms = {
    for alarm_key, alarm in var.cloudwatch_metric_anomaly_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  anomaly_alarm_default_dimensions = {
    for alarm_key, alarm in local.enabled_anomaly_alarms :
    alarm_key => merge(
      try(alarm.rule_key, null) != null && contains(keys(local.rules), alarm.rule_key) ? {
        EventBusName = local.rules[alarm.rule_key].bus_name
        RuleName     = local.rules[alarm.rule_key].name
      } : {},
      try(alarm.event_bus_name, null) != null ? {
        EventBusName = alarm.event_bus_name
      } : {}
    )
  }

  # Event logging
  event_logging_enabled = local.observability_enabled && try(var.observability.enable_event_logging, false)
  event_logging_buses   = local.event_logging_enabled ? { for b in var.event_buses : b.name => b } : {}

  # Dashboard
  dashboard_enabled    = local.observability_enabled && try(var.observability.enable_dashboard, false)
  _dashboard_raw_name  = replace(join("-", [for b in var.event_buses : b.name]), ":", "-")
  _dashboard_safe_name = length(local._dashboard_raw_name) <= 243 ? local._dashboard_raw_name : "${substr(local._dashboard_raw_name, 0, 232)}-${substr(md5(local._dashboard_raw_name), 0, 8)}"
  dashboard_name       = "${local._dashboard_safe_name}-eventbridge"
}

# =============================================================================
# Event Rules
# =============================================================================

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name                = each.value.name
  description         = each.value.desc
  state               = each.value.state
  event_pattern       = each.value.pattern
  schedule_expression = each.value.schedule
  event_bus_name      = local.bus_name_map[each.value.bus_name]

  tags = merge(var.tags, each.value.tags)
}

# =============================================================================
# Event Targets
# =============================================================================

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.targets

  rule           = aws_cloudwatch_event_rule.this[each.value.rule_key].name
  target_id      = each.value.id
  arn            = each.value.arn
  input          = each.value.input
  input_path     = each.value.input_path
  role_arn       = each.value.role_arn
  event_bus_name = local.bus_name_map[each.value.bus_name]

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_arn == null ? [] : [each.value.dead_letter_arn]
    content {
      arn = dead_letter_config.value
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.retry_policy == null ? [] : [each.value.retry_policy]
    content {
      maximum_event_age_in_seconds = try(retry_policy.value.maximum_event_age_in_seconds, null)
      maximum_retry_attempts       = try(retry_policy.value.maximum_retry_attempts, null)
    }
  }

  dynamic "input_transformer" {
    for_each = each.value.input_transformer == null ? [] : [each.value.input_transformer]
    content {
      input_paths    = try(input_transformer.value.input_paths_map, null)
      input_template = input_transformer.value.input_template
    }
  }

  # --- Specialized target blocks ---

  dynamic "ecs_target" {
    for_each = each.value.ecs_target == null ? [] : [each.value.ecs_target]
    content {
      task_definition_arn     = ecs_target.value.task_definition_arn
      task_count              = try(ecs_target.value.task_count, 1)
      launch_type             = try(ecs_target.value.launch_type, null)
      platform_version        = try(ecs_target.value.platform_version, null)
      group                   = try(ecs_target.value.group, null)
      enable_execute_command  = try(ecs_target.value.enable_execute_command, false)
      enable_ecs_managed_tags = try(ecs_target.value.enable_ecs_managed_tags, false)
      propagate_tags          = try(ecs_target.value.propagate_tags, null)
      tags                    = try(ecs_target.value.tags, {})

      dynamic "network_configuration" {
        for_each = try(ecs_target.value.network_configuration, null) == null ? [] : [ecs_target.value.network_configuration]
        content {
          subnets          = network_configuration.value.subnets
          security_groups  = try(network_configuration.value.security_groups, [])
          assign_public_ip = try(network_configuration.value.assign_public_ip, false)
        }
      }

      dynamic "capacity_provider_strategy" {
        for_each = try(ecs_target.value.capacity_provider_strategy, [])
        content {
          capacity_provider = capacity_provider_strategy.value.capacity_provider
          weight            = try(capacity_provider_strategy.value.weight, 1)
          base              = try(capacity_provider_strategy.value.base, 0)
        }
      }

      dynamic "placement_constraint" {
        for_each = try(ecs_target.value.placement_constraint, [])
        content {
          type       = placement_constraint.value.type
          expression = try(placement_constraint.value.expression, null)
        }
      }
    }
  }

  dynamic "kinesis_target" {
    for_each = each.value.kinesis_target == null ? [] : [each.value.kinesis_target]
    content {
      partition_key_path = try(kinesis_target.value.partition_key_path, null)
    }
  }

  dynamic "sqs_target" {
    for_each = each.value.sqs_target == null ? [] : [each.value.sqs_target]
    content {
      message_group_id = try(sqs_target.value.message_group_id, null)
    }
  }

  dynamic "http_target" {
    for_each = each.value.http_target == null ? [] : [each.value.http_target]
    content {
      header_parameters       = try(http_target.value.header_parameters, {})
      query_string_parameters = try(http_target.value.query_string_parameters, {})
      path_parameter_values   = try(http_target.value.path_parameter_values, [])
    }
  }

  dynamic "batch_target" {
    for_each = each.value.batch_target == null ? [] : [each.value.batch_target]
    content {
      job_definition = batch_target.value.job_definition
      job_name       = batch_target.value.job_name
      array_size     = try(batch_target.value.array_size, null)
      job_attempts   = try(batch_target.value.job_attempts, null)
    }
  }
}

# =============================================================================
# Lambda Permissions
# =============================================================================

resource "aws_lambda_permission" "eventbridge_invoke" {
  for_each = local.lambda_permission_targets

  statement_id = coalesce(
    each.value.lambda_permission_statement_id,
    substr("${var.lambda_permission_statement_id_prefix}-${md5(each.key)}", 0, 100)
  )
  action        = "lambda:InvokeFunction"
  function_name = coalesce(each.value.lambda_function_name, each.value.arn)
  qualifier     = each.value.lambda_qualifier
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.value.rule_key].arn
}

# =============================================================================
# Event Archives
# =============================================================================

resource "aws_cloudwatch_event_archive" "this" {
  for_each = { for a in var.archives : a.name => a }

  name             = each.value.name
  description      = try(each.value.description, null)
  event_source_arn = coalesce(
    each.value.event_source_arn,
    each.value.bus_name != null && each.value.bus_name != "default"
    ? aws_cloudwatch_event_bus.this[each.value.bus_name].arn
    : "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
  )
  event_pattern    = try(each.value.event_pattern, null)
  retention_days   = try(each.value.retention_days, 0)
  kms_key_identifier = try(each.value.kms_key_identifier, null)
}

# =============================================================================
# Event Bus Policies (cross-account access)
# =============================================================================

resource "aws_cloudwatch_event_bus_policy" "this" {
  for_each = { for p in var.bus_policies : p.bus_name => p }

  policy         = each.value.policy
  event_bus_name = local.bus_name_map[each.value.bus_name]
}

# =============================================================================
# CloudWatch Metric Alarms — EventBridge Rules
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.enabled_cloudwatch_metric_alarms

  alarm_name                = coalesce(try(each.value.alarm_name, null), "eventbridge-${each.key}")
  alarm_description         = try(each.value.alarm_description, null)
  comparison_operator       = each.value.comparison_operator
  evaluation_periods        = each.value.evaluation_periods
  datapoints_to_alarm       = try(each.value.datapoints_to_alarm, null)
  metric_name               = each.value.metric_name
  namespace                 = try(each.value.namespace, "AWS/Events")
  period                    = each.value.period
  statistic                 = try(each.value.extended_statistic, null) != null ? null : try(each.value.statistic, "Sum")
  extended_statistic        = try(each.value.extended_statistic, null)
  threshold                 = each.value.threshold
  treat_missing_data        = try(each.value.treat_missing_data, null)
  unit                      = try(each.value.unit, null)
  actions_enabled           = try(each.value.actions_enabled, true)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])
  dimensions = merge(
    local.cloudwatch_metric_alarm_default_dimensions[each.key],
    try(each.value.dimensions, {})
  )
  tags = merge(
    var.tags,
    try(each.value.tags, {})
  )

  lifecycle {
    precondition {
      condition     = try(each.value.rule_key, null) == null || contains(keys(local.rules), each.value.rule_key)
      error_message = "cloudwatch_metric_alarms[\"${each.key}\"].rule_key must reference an existing module rule in '<bus_name>:<rule_name>' format."
    }
  }
}

# =============================================================================
# CloudWatch Metric Alarms — DLQ
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = local.enabled_dlq_cloudwatch_metric_alarms

  alarm_name                = coalesce(try(each.value.alarm_name, null), "eventbridge-dlq-${each.key}")
  alarm_description         = try(each.value.alarm_description, null)
  comparison_operator       = each.value.comparison_operator
  evaluation_periods        = each.value.evaluation_periods
  datapoints_to_alarm       = try(each.value.datapoints_to_alarm, null)
  metric_name               = each.value.metric_name
  namespace                 = try(each.value.namespace, "AWS/SQS")
  period                    = each.value.period
  statistic                 = try(each.value.extended_statistic, null) != null ? null : try(each.value.statistic, "Sum")
  extended_statistic        = try(each.value.extended_statistic, null)
  threshold                 = each.value.threshold
  treat_missing_data        = try(each.value.treat_missing_data, null)
  unit                      = try(each.value.unit, null)
  actions_enabled           = try(each.value.actions_enabled, true)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])
  dimensions                = local.dlq_cloudwatch_metric_alarm_default_dimensions[each.key]
  tags = merge(
    var.tags,
    try(each.value.tags, {})
  )

  lifecycle {
    precondition {
      condition = (
        try(each.value.target_key, null) == null ||
        contains(keys(local.lambda_targets_with_dlq), each.value.target_key)
      )
      error_message = "dlq_cloudwatch_metric_alarms[\"${each.key}\"].target_key must reference a Lambda target with dead_letter_arn in '<bus_name>:<rule_name>:<target_id>' format."
    }

    precondition {
      condition     = local.dlq_cloudwatch_metric_alarm_resolved_queue_name[each.key] != null
      error_message = "dlq_cloudwatch_metric_alarms[\"${each.key}\"] must set one of queue_name, dead_letter_arn, or target_key (pointing to a Lambda target with dead_letter_arn)."
    }
  }
}

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "anomaly" {
  for_each = local.enabled_anomaly_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "eventbridge-anomaly-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = each.value.evaluation_periods
  threshold_metric_id = "ad1"
  actions_enabled     = try(each.value.actions_enabled, true)
  alarm_actions       = try(each.value.alarm_actions, [])
  ok_actions          = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])
  tags = merge(var.tags, try(each.value.tags, {}))

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${try(each.value.band_width, 2)})"
    label       = "${each.value.metric_name} anomaly band"
    return_data = true
  }

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = each.value.metric_name
      namespace   = try(each.value.namespace, "AWS/Events")
      period      = each.value.period
      stat        = try(each.value.statistic, "Sum")
      dimensions  = merge(
        local.anomaly_alarm_default_dimensions[each.key],
        try(each.value.dimensions, {})
      )
    }
  }

  lifecycle {
    precondition {
      condition     = try(each.value.rule_key, null) == null || contains(keys(local.rules), each.value.rule_key)
      error_message = "cloudwatch_metric_anomaly_alarms[\"${each.key}\"].rule_key must reference an existing module rule in '<bus_name>:<rule_name>' format."
    }
  }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode({
    widgets = flatten([
      for bus_idx, bus in var.event_buses : [
        # ── Text header ──
        {
          type   = "text"
          x      = 0
          y      = bus_idx * 20
          width  = 24
          height = 1
          properties = {
            markdown = "## ${bus.name} Event Bus"
          }
        },
        # ── MatchedEvents per rule ──
        {
          type   = "metric"
          x      = 0
          y      = bus_idx * 20 + 1
          width  = 12
          height = 6
          properties = {
            title   = "${bus.name} — MatchedEvents"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 60
            view    = "timeSeries"
            stacked = false
            metrics = [
              for rule in try(bus.rules, []) : [
                "AWS/Events", "MatchedEvents", "RuleName", rule.name, "EventBusName", bus.name
              ]
            ]
          }
        },
        # ── Invocations per rule (target delivery) ──
        {
          type   = "metric"
          x      = 12
          y      = bus_idx * 20 + 1
          width  = 12
          height = 6
          properties = {
            title   = "${bus.name} — Invocations"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 60
            view    = "timeSeries"
            stacked = false
            metrics = [
              for rule in try(bus.rules, []) : [
                "AWS/Events", "Invocations", "RuleName", rule.name, "EventBusName", bus.name
              ]
            ]
          }
        },
        # ── FailedInvocations (bus + per-rule) + ThrottledRules ──
        {
          type   = "metric"
          x      = 0
          y      = bus_idx * 20 + 7
          width  = 12
          height = 6
          properties = {
            title   = "${bus.name} — Failures & Throttles"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 60
            view    = "timeSeries"
            stacked = false
            metrics = concat(
              [["AWS/Events", "FailedInvocations", "EventBusName", bus.name]],
              [["AWS/Events", "ThrottledRules", "EventBusName", bus.name]],
              [for rule in try(bus.rules, []) : [
                "AWS/Events", "FailedInvocations", "RuleName", rule.name, "EventBusName", bus.name
              ]]
            )
          }
        },
        # ── Dead-Letter & dropped events ──
        {
          type   = "metric"
          x      = 12
          y      = bus_idx * 20 + 7
          width  = 12
          height = 6
          properties = {
            title   = "${bus.name} — DLQ & Dropped Events"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 60
            view    = "timeSeries"
            stacked = false
            metrics = [
              ["AWS/Events", "InvocationsSentToDLQ", "EventBusName", bus.name],
              ["AWS/Events", "InvocationsFailedToBeSentToDLQ", "EventBusName", bus.name]
            ]
          }
        },
        # ── TriggeredRules (bus-wide) ──
        {
          type   = "metric"
          x      = 0
          y      = bus_idx * 20 + 13
          width  = 24
          height = 6
          properties = {
            title   = "${bus.name} — TriggeredRules"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            view    = "timeSeries"
            stacked = false
            metrics = [
              ["AWS/Events", "TriggeredRules", "EventBusName", bus.name]
            ]
          }
        }
      ]
    ])
  })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# =============================================================================
# Event Logging — per-bus catch-all rule → CloudWatch Logs
# =============================================================================

resource "aws_cloudwatch_log_group" "event_logs" {
  for_each = local.event_logging_buses

  name              = "/aws/events/${each.key}"
  retention_in_days = try(var.observability.event_log_retention_in_days, 14)
  kms_key_id        = try(var.observability.event_log_kms_key_arn, null)
  tags              = merge(var.tags, { EventBus = each.key })
}

resource "aws_cloudwatch_log_resource_policy" "event_logs" {
  count = local.event_logging_enabled ? 1 : 0

  policy_name     = "eventbridge-to-cloudwatch-logs-${substr(md5(join(",", keys(local.event_logging_buses))), 0, 8)}"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePutLogEvents"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = [for lg in aws_cloudwatch_log_group.event_logs : "${lg.arn}:*"]
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "event_logs" {
  for_each = local.event_logging_buses

  name           = "${each.key}-catch-all-log"
  description    = "Catch-all rule for event logging on bus ${each.key}"
  state          = "ENABLED"
  event_bus_name = local.bus_name_map[each.key]

  event_pattern = jsonencode({
    source = [{ "prefix" = "" }]
  })

  tags = merge(var.tags, { Purpose = "event-logging" })
}

resource "aws_cloudwatch_event_target" "event_logs" {
  for_each = local.event_logging_buses

  rule           = aws_cloudwatch_event_rule.event_logs[each.key].name
  target_id      = "cloudwatch-logs"
  arn            = aws_cloudwatch_log_group.event_logs[each.key].arn
  event_bus_name = local.bus_name_map[each.key]
}

# =============================================================================
# EventBridge Connections (for API Destinations / HTTP targets)
# =============================================================================

resource "aws_cloudwatch_event_connection" "this" {
  for_each = var.connections

  name               = each.key
  description        = try(each.value.description, null)
  authorization_type = each.value.authorization_type

  auth_parameters {
    dynamic "api_key" {
      for_each = try(each.value.auth_parameters.api_key, null) != null ? [each.value.auth_parameters.api_key] : []
      content {
        key   = api_key.value.key
        value = api_key.value.value
      }
    }

    dynamic "basic" {
      for_each = try(each.value.auth_parameters.basic, null) != null ? [each.value.auth_parameters.basic] : []
      content {
        username = basic.value.username
        password = basic.value.password
      }
    }

    dynamic "oauth" {
      for_each = try(each.value.auth_parameters.oauth, null) != null ? [each.value.auth_parameters.oauth] : []
      content {
        authorization_endpoint = oauth.value.authorization_endpoint
        http_method            = oauth.value.http_method

        client_parameters {
          client_id     = oauth.value.client_parameters.client_id
          client_secret = oauth.value.client_parameters.client_secret
        }

        dynamic "oauth_http_parameters" {
          for_each = length(try(oauth.value.body_parameters, {})) > 0 || length(try(oauth.value.header_parameters, {})) > 0 || length(try(oauth.value.query_string_parameters, {})) > 0 ? [1] : []
          content {
            dynamic "body" {
              for_each = try(oauth.value.body_parameters, {})
              content {
                key             = body.key
                value           = body.value
                is_value_secret = false
              }
            }
            dynamic "header" {
              for_each = try(oauth.value.header_parameters, {})
              content {
                key             = header.key
                value           = header.value
                is_value_secret = false
              }
            }
            dynamic "query_string" {
              for_each = try(oauth.value.query_string_parameters, {})
              content {
                key             = query_string.key
                value           = query_string.value
                is_value_secret = false
              }
            }
          }
        }
      }
    }

    dynamic "invocation_http_parameters" {
      for_each = try(each.value.auth_parameters.invocation_http_parameters, null) != null ? [each.value.auth_parameters.invocation_http_parameters] : []
      content {
        dynamic "body" {
          for_each = try(invocation_http_parameters.value.body, [])
          content {
            key             = body.value.key
            value           = body.value.value
            is_value_secret = try(body.value.is_value_secret, false)
          }
        }
        dynamic "header" {
          for_each = try(invocation_http_parameters.value.header, [])
          content {
            key             = header.value.key
            value           = header.value.value
            is_value_secret = try(header.value.is_value_secret, false)
          }
        }
        dynamic "query_string" {
          for_each = try(invocation_http_parameters.value.query_string, [])
          content {
            key             = query_string.value.key
            value           = query_string.value.value
            is_value_secret = try(query_string.value.is_value_secret, false)
          }
        }
      }
    }
  }
}

# =============================================================================
# EventBridge API Destinations
# =============================================================================

resource "aws_cloudwatch_event_api_destination" "this" {
  for_each = var.api_destinations

  name                             = each.key
  description                      = try(each.value.description, null)
  invocation_endpoint              = each.value.invocation_endpoint
  http_method                      = each.value.http_method
  invocation_rate_limit_per_second = try(each.value.invocation_rate_limit_per_second, 300)
  connection_arn                   = aws_cloudwatch_event_connection.this[each.value.connection_key].arn
}

# =============================================================================
# Schema Registries
# =============================================================================

resource "aws_schemas_registry" "this" {
  for_each = var.schema_registries

  name        = each.key
  description = try(each.value.description, null)
  tags        = merge(var.tags, try(each.value.tags, {}))
}

# =============================================================================
# Schemas
# =============================================================================

resource "aws_schemas_schema" "this" {
  for_each = var.schemas

  name          = each.key
  registry_name = aws_schemas_registry.this[each.value.registry_key].name
  type          = each.value.type
  description   = try(each.value.description, null)
  content       = each.value.content
  tags          = merge(var.tags, try(each.value.tags, {}))
}

# =============================================================================
# Schema Discoverers
# =============================================================================

resource "aws_schemas_discoverer" "this" {
  for_each = var.schema_discoverers

  source_arn  = each.value.bus_name == "default" ? "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default" : aws_cloudwatch_event_bus.this[each.value.bus_name].arn
  description = try(each.value.description, null)
  tags        = merge(var.tags, try(each.value.tags, {}))
}

# =============================================================================
# EventBridge Pipes
# =============================================================================

resource "aws_pipes_pipe" "this" {
  for_each = var.pipes

  name        = each.key
  description = try(each.value.description, null)
  role_arn    = each.value.role_arn
  source      = each.value.source
  target      = each.value.target
  enrichment  = try(each.value.enrichment, null)

  desired_state = each.value.desired_state

  tags = merge(var.tags, try(each.value.tags, {}))

  # ── Source Parameters ──
  dynamic "source_parameters" {
    for_each = each.value.source_parameters != null ? [each.value.source_parameters] : []

    content {
      # Filter criteria
      dynamic "filter_criteria" {
        for_each = try(source_parameters.value.filter_criteria, null) != null ? [source_parameters.value.filter_criteria] : []

        content {
          dynamic "filter" {
            for_each = try(filter_criteria.value.filters, [])

            content {
              pattern = filter.value.pattern
            }
          }
        }
      }

      # SQS source
      dynamic "sqs_queue_parameters" {
        for_each = try(source_parameters.value.sqs, null) != null ? [source_parameters.value.sqs] : []

        content {
          batch_size                         = sqs_queue_parameters.value.batch_size
          maximum_batching_window_in_seconds = sqs_queue_parameters.value.maximum_batching_window_in_seconds
        }
      }

      # Kinesis source
      dynamic "kinesis_stream_parameters" {
        for_each = try(source_parameters.value.kinesis_stream, null) != null ? [source_parameters.value.kinesis_stream] : []

        content {
          starting_position                  = kinesis_stream_parameters.value.starting_position
          batch_size                         = kinesis_stream_parameters.value.batch_size
          maximum_batching_window_in_seconds = kinesis_stream_parameters.value.maximum_batching_window_in_seconds
          maximum_record_age_in_seconds      = kinesis_stream_parameters.value.maximum_record_age_in_seconds
          maximum_retry_attempts             = kinesis_stream_parameters.value.maximum_retry_attempts
          on_partial_batch_item_failure      = kinesis_stream_parameters.value.on_partial_batch_item_failure
          parallelization_factor             = kinesis_stream_parameters.value.parallelization_factor
          starting_position_timestamp        = kinesis_stream_parameters.value.starting_position_timestamp

          dynamic "dead_letter_config" {
            for_each = try(kinesis_stream_parameters.value.dead_letter_config, null) != null ? [kinesis_stream_parameters.value.dead_letter_config] : []

            content {
              arn = dead_letter_config.value.arn
            }
          }
        }
      }

      # DynamoDB Streams source
      dynamic "dynamodb_stream_parameters" {
        for_each = try(source_parameters.value.dynamodb_stream, null) != null ? [source_parameters.value.dynamodb_stream] : []

        content {
          starting_position                  = dynamodb_stream_parameters.value.starting_position
          batch_size                         = dynamodb_stream_parameters.value.batch_size
          maximum_batching_window_in_seconds = dynamodb_stream_parameters.value.maximum_batching_window_in_seconds
          maximum_record_age_in_seconds      = dynamodb_stream_parameters.value.maximum_record_age_in_seconds
          maximum_retry_attempts             = dynamodb_stream_parameters.value.maximum_retry_attempts
          on_partial_batch_item_failure      = dynamodb_stream_parameters.value.on_partial_batch_item_failure
          parallelization_factor             = dynamodb_stream_parameters.value.parallelization_factor

          dynamic "dead_letter_config" {
            for_each = try(dynamodb_stream_parameters.value.dead_letter_config, null) != null ? [dynamodb_stream_parameters.value.dead_letter_config] : []

            content {
              arn = dead_letter_config.value.arn
            }
          }
        }
      }

      # Managed Streaming for Kafka (MSK) source
      dynamic "managed_streaming_kafka_parameters" {
        for_each = try(source_parameters.value.managed_streaming_kafka, null) != null ? [source_parameters.value.managed_streaming_kafka] : []

        content {
          topic_name                         = managed_streaming_kafka_parameters.value.topic_name
          consumer_group_id                  = managed_streaming_kafka_parameters.value.consumer_group_id
          batch_size                         = managed_streaming_kafka_parameters.value.batch_size
          maximum_batching_window_in_seconds = managed_streaming_kafka_parameters.value.maximum_batching_window_in_seconds
          starting_position                  = managed_streaming_kafka_parameters.value.starting_position
        }
      }

      # Self-managed Kafka source
      dynamic "self_managed_kafka_parameters" {
        for_each = try(source_parameters.value.self_managed_kafka, null) != null ? [source_parameters.value.self_managed_kafka] : []

        content {
          topic_name                         = self_managed_kafka_parameters.value.topic_name
          consumer_group_id                  = self_managed_kafka_parameters.value.consumer_group_id
          batch_size                         = self_managed_kafka_parameters.value.batch_size
          maximum_batching_window_in_seconds = self_managed_kafka_parameters.value.maximum_batching_window_in_seconds
          starting_position                  = self_managed_kafka_parameters.value.starting_position
          server_root_ca_certificate         = null

          dynamic "credentials" {
            for_each = []
            content {}
          }

          dynamic "vpc" {
            for_each = try(self_managed_kafka_parameters.value.vpc, null) != null ? [self_managed_kafka_parameters.value.vpc] : []

            content {
              security_groups = vpc.value.security_groups
              subnets         = vpc.value.subnets
            }
          }
        }
      }

      # ActiveMQ source
      dynamic "activemq_broker_parameters" {
        for_each = try(source_parameters.value.activemq_broker, null) != null ? [source_parameters.value.activemq_broker] : []

        content {
          queue_name                         = activemq_broker_parameters.value.queue_name
          batch_size                         = activemq_broker_parameters.value.batch_size
          maximum_batching_window_in_seconds = activemq_broker_parameters.value.maximum_batching_window_in_seconds

          credentials {
            basic_auth = activemq_broker_parameters.value.credentials_arn
          }
        }
      }

      # RabbitMQ source
      dynamic "rabbitmq_broker_parameters" {
        for_each = try(source_parameters.value.rabbitmq_broker, null) != null ? [source_parameters.value.rabbitmq_broker] : []

        content {
          queue_name                         = rabbitmq_broker_parameters.value.queue_name
          virtual_host                       = rabbitmq_broker_parameters.value.virtual_host
          batch_size                         = rabbitmq_broker_parameters.value.batch_size
          maximum_batching_window_in_seconds = rabbitmq_broker_parameters.value.maximum_batching_window_in_seconds

          credentials {
            basic_auth = rabbitmq_broker_parameters.value.credentials_arn
          }
        }
      }
    }
  }

  # ── Enrichment Parameters ──
  dynamic "enrichment_parameters" {
    for_each = each.value.enrichment_parameters != null ? [each.value.enrichment_parameters] : []

    content {
      input_template = enrichment_parameters.value.input_template

      dynamic "http_parameters" {
        for_each = try(enrichment_parameters.value.http, null) != null ? [enrichment_parameters.value.http] : []

        content {
          header_parameters       = http_parameters.value.header_parameters
          query_string_parameters = http_parameters.value.query_string_parameters
          path_parameter_values   = http_parameters.value.path_parameter_values
        }
      }
    }
  }

  # ── Target Parameters ──
  dynamic "target_parameters" {
    for_each = each.value.target_parameters != null ? [each.value.target_parameters] : []

    content {
      input_template = target_parameters.value.input_template

      # Lambda target
      dynamic "lambda_function_parameters" {
        for_each = try(target_parameters.value.lambda_function, null) != null ? [target_parameters.value.lambda_function] : []

        content {
          invocation_type = lambda_function_parameters.value.invocation_type
        }
      }

      # Step Functions target
      dynamic "step_function_state_machine_parameters" {
        for_each = try(target_parameters.value.step_function, null) != null ? [target_parameters.value.step_function] : []

        content {
          invocation_type = step_function_state_machine_parameters.value.invocation_type
        }
      }

      # SQS target
      dynamic "sqs_queue_parameters" {
        for_each = try(target_parameters.value.sqs, null) != null ? [target_parameters.value.sqs] : []

        content {
          message_group_id         = sqs_queue_parameters.value.message_group_id
          message_deduplication_id = sqs_queue_parameters.value.message_deduplication_id
        }
      }

      # Kinesis target
      dynamic "kinesis_stream_parameters" {
        for_each = try(target_parameters.value.kinesis_stream, null) != null ? [target_parameters.value.kinesis_stream] : []

        content {
          partition_key = kinesis_stream_parameters.value.partition_key
        }
      }

      # EventBridge target
      dynamic "eventbridge_event_bus_parameters" {
        for_each = try(target_parameters.value.eventbridge_event_bus, null) != null ? [target_parameters.value.eventbridge_event_bus] : []

        content {
          detail_type = eventbridge_event_bus_parameters.value.detail_type
          endpoint_id = eventbridge_event_bus_parameters.value.endpoint_id
          resources   = eventbridge_event_bus_parameters.value.resources
          source      = eventbridge_event_bus_parameters.value.source
          time        = eventbridge_event_bus_parameters.value.time
        }
      }

      # ECS target
      dynamic "ecs_task_parameters" {
        for_each = try(target_parameters.value.ecs_task, null) != null ? [target_parameters.value.ecs_task] : []

        content {
          task_definition_arn     = ecs_task_parameters.value.task_definition_arn
          task_count              = ecs_task_parameters.value.task_count
          launch_type             = ecs_task_parameters.value.launch_type
          platform_version        = ecs_task_parameters.value.platform_version
          group                   = ecs_task_parameters.value.group
          enable_ecs_managed_tags = ecs_task_parameters.value.enable_ecs_managed_tags
          enable_execute_command  = ecs_task_parameters.value.enable_execute_command
          propagate_tags          = ecs_task_parameters.value.propagate_tags
          reference_id            = ecs_task_parameters.value.reference_id

          dynamic "capacity_provider_strategy" {
            for_each = try(ecs_task_parameters.value.capacity_provider_strategy, [])

            content {
              capacity_provider = capacity_provider_strategy.value.capacity_provider
              weight            = capacity_provider_strategy.value.weight
              base              = capacity_provider_strategy.value.base
            }
          }

          dynamic "network_configuration" {
            for_each = try(ecs_task_parameters.value.network_configuration, null) != null ? [ecs_task_parameters.value.network_configuration] : []

            content {
              aws_vpc_configuration {
                subnets          = network_configuration.value.subnets
                security_groups  = network_configuration.value.security_groups
                assign_public_ip = network_configuration.value.assign_public_ip
              }
            }
          }

          dynamic "overrides" {
            for_each = try(ecs_task_parameters.value.overrides, null) != null ? [ecs_task_parameters.value.overrides] : []

            content {
              cpu    = overrides.value.cpu
              memory = overrides.value.memory

              dynamic "ephemeral_storage" {
                for_each = try(overrides.value.ephemeral_storage_size_in_gib, null) != null ? [overrides.value.ephemeral_storage_size_in_gib] : []

                content {
                  size_in_gib = ephemeral_storage.value
                }
              }

              execution_role_arn = overrides.value.execution_role_arn
              task_role_arn      = overrides.value.task_role_arn

              dynamic "inference_accelerator_override" {
                for_each = try(overrides.value.inference_accelerator_overrides, [])

                content {
                  device_name = inference_accelerator_override.value.device_name
                  device_type = inference_accelerator_override.value.device_type
                }
              }

              dynamic "container_override" {
                for_each = try(overrides.value.container_overrides, [])

                content {
                  name    = container_override.value.name
                  command = container_override.value.command
                  cpu     = container_override.value.cpu
                  memory  = container_override.value.memory
                  memory_reservation = container_override.value.memory_reservation

                  dynamic "environment" {
                    for_each = try(container_override.value.environment, [])

                    content {
                      name  = environment.value.name
                      value = environment.value.value
                    }
                  }

                  dynamic "environment_file" {
                    for_each = try(container_override.value.environment_files, [])

                    content {
                      type  = environment_file.value.type
                      value = environment_file.value.value
                    }
                  }

                  dynamic "resource_requirement" {
                    for_each = try(container_override.value.resource_requirements, [])

                    content {
                      type  = resource_requirement.value.type
                      value = resource_requirement.value.value
                    }
                  }
                }
              }
            }
          }
        }
      }

      # CloudWatch Logs target
      dynamic "cloudwatch_logs_parameters" {
        for_each = try(target_parameters.value.cloudwatch_logs, null) != null ? [target_parameters.value.cloudwatch_logs] : []

        content {
          log_stream_name = cloudwatch_logs_parameters.value.log_stream_name
          timestamp       = cloudwatch_logs_parameters.value.timestamp
        }
      }

      # HTTP (API Destination) target
      dynamic "http_parameters" {
        for_each = try(target_parameters.value.http, null) != null ? [target_parameters.value.http] : []

        content {
          header_parameters       = http_parameters.value.header_parameters
          query_string_parameters = http_parameters.value.query_string_parameters
          path_parameter_values   = http_parameters.value.path_parameter_values
        }
      }

      # SageMaker Pipeline target
      dynamic "sagemaker_pipeline_parameters" {
        for_each = try(target_parameters.value.sagemaker_pipeline, null) != null ? [target_parameters.value.sagemaker_pipeline] : []

        content {
          dynamic "pipeline_parameter" {
            for_each = try(sagemaker_pipeline_parameters.value.parameters, [])

            content {
              name  = pipeline_parameter.value.name
              value = pipeline_parameter.value.value
            }
          }
        }
      }

      # Batch target
      dynamic "batch_job_parameters" {
        for_each = try(target_parameters.value.batch_job, null) != null ? [target_parameters.value.batch_job] : []

        content {
          job_definition = batch_job_parameters.value.job_definition
          job_name       = batch_job_parameters.value.job_name

          dynamic "retry_strategy" {
            for_each = try(batch_job_parameters.value.retry_strategy, null) != null ? [batch_job_parameters.value.retry_strategy] : []

            content {
              attempts = retry_strategy.value.attempts
            }
          }

          dynamic "array_properties" {
            for_each = try(batch_job_parameters.value.array_properties, null) != null ? [batch_job_parameters.value.array_properties] : []

            content {
              size = array_properties.value.size
            }
          }

          dynamic "depends_on" {
            for_each = try(batch_job_parameters.value.depends_on, [])

            content {
              job_id = depends_on.value.job_id
              type   = depends_on.value.type
            }
          }

          parameters = batch_job_parameters.value.parameters

          dynamic "container_overrides" {
            for_each = try(batch_job_parameters.value.container_overrides, null) != null ? [batch_job_parameters.value.container_overrides] : []

            content {
              command       = container_overrides.value.command
              instance_type = container_overrides.value.instance_type

              dynamic "environment" {
                for_each = try(container_overrides.value.environment, [])

                content {
                  name  = environment.value.name
                  value = environment.value.value
                }
              }

              dynamic "resource_requirement" {
                for_each = try(container_overrides.value.resource_requirements, [])

                content {
                  type  = resource_requirement.value.type
                  value = resource_requirement.value.value
                }
              }
            }
          }
        }
      }

      # Redshift Data API target
      dynamic "redshift_data_parameters" {
        for_each = try(target_parameters.value.redshift_data, null) != null ? [target_parameters.value.redshift_data] : []

        content {
          database           = redshift_data_parameters.value.database
          sqls               = redshift_data_parameters.value.sql_statements
          db_user            = redshift_data_parameters.value.db_user
          secret_manager_arn = redshift_data_parameters.value.secret_manager_arn
          statement_name     = redshift_data_parameters.value.statement_name
          with_event         = redshift_data_parameters.value.with_event
        }
      }
    }
  }

  # ── Log Configuration ──
  dynamic "log_configuration" {
    for_each = each.value.log_configuration != null ? [each.value.log_configuration] : []

    content {
      level = log_configuration.value.level

      dynamic "cloudwatch_logs_log_destination" {
        for_each = try(log_configuration.value.cloudwatch_logs_log_destination, null) != null ? [log_configuration.value.cloudwatch_logs_log_destination] : []

        content {
          log_group_arn = cloudwatch_logs_log_destination.value.log_group_arn
        }
      }

      dynamic "firehose_log_destination" {
        for_each = try(log_configuration.value.firehose_log_destination, null) != null ? [log_configuration.value.firehose_log_destination] : []

        content {
          delivery_stream_arn = firehose_log_destination.value.delivery_stream_arn
        }
      }

      dynamic "s3_log_destination" {
        for_each = try(log_configuration.value.s3_log_destination, null) != null ? [log_configuration.value.s3_log_destination] : []

        content {
          bucket_name   = s3_log_destination.value.bucket_name
          bucket_owner  = s3_log_destination.value.bucket_owner
          output_format = s3_log_destination.value.output_format
          prefix        = s3_log_destination.value.prefix
        }
      }
    }
  }
}
