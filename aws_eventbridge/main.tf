resource "aws_cloudwatch_event_bus" "this" {
  for_each = { for b in var.event_buses : b.name => b }

  name = each.value.name
  tags = lookup(each.value, "tags", {})
}

locals {
  rules = {
    for r in flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : {
          key      = "${bus.name}:${rule.name}"
          bus_name = bus.name
          name     = rule.name
          desc     = lookup(rule, "description", null)
          enabled  = lookup(rule, "is_enabled", true)
          pattern  = lookup(rule, "event_pattern", null)
          schedule = lookup(rule, "schedule_expression", null)
        }
      ]
    ]) : r.key => r
  }

  targets = {
    for t in flatten([
      for bus in var.event_buses : [
        for rule in bus.rules : [
          for target in coalesce(rule.targets, []) : {
            key                            = "${bus.name}:${rule.name}:${target.id}"
            rule_key                       = "${bus.name}:${rule.name}"
            bus_name                       = bus.name
            arn                            = target.arn
            id                             = target.id
            input                          = lookup(target, "input", null)
            input_path                     = lookup(target, "input_path", null)
            role_arn                       = lookup(target, "role_arn", null)
            dead_letter_arn                = lookup(target, "dead_letter_arn", null)
            retry_policy                   = lookup(target, "retry_policy", null)
            create_lambda_permission       = lookup(target, "create_lambda_permission", true)
            lambda_permission_statement_id = lookup(target, "lambda_permission_statement_id", null)
            lambda_function_name           = lookup(target, "lambda_function_name", null)
            lambda_qualifier               = lookup(target, "lambda_qualifier", null)
          }
        ]
      ]
    ]) : t.key => t
  }

  lambda_permission_targets = {
    for key, target in local.targets : key => target
    if target.create_lambda_permission && can(regex(":lambda:", target.arn))
  }

  enabled_cloudwatch_metric_alarms = {
    for alarm_key, alarm in var.cloudwatch_metric_alarms :
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

  lambda_targets_with_dlq = {
    for key, target in local.targets : key => target
    if can(regex(":lambda:", target.arn)) && try(target.dead_letter_arn, null) != null
  }

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
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name                = each.value.name
  description         = each.value.desc
  is_enabled          = each.value.enabled
  event_pattern       = each.value.pattern
  schedule_expression = each.value.schedule
  event_bus_name      = aws_cloudwatch_event_bus.this[each.value.bus_name].name
}


resource "aws_cloudwatch_event_target" "this" {
  for_each = local.targets

  rule           = aws_cloudwatch_event_rule.this[each.value.rule_key].name
  target_id      = each.value.id
  arn            = each.value.arn
  input          = each.value.input
  input_path     = each.value.input_path
  role_arn       = each.value.role_arn
  event_bus_name = aws_cloudwatch_event_bus.this[each.value.bus_name].name

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_arn == null ? [] : [each.value.dead_letter_arn]
    content {
      arn = dead_letter_config.value
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.retry_policy == null ? [] : [each.value.retry_policy]
    content {
      maximum_event_age_in_seconds = lookup(retry_policy.value, "maximum_event_age_in_seconds", null)
      maximum_retry_attempts       = lookup(retry_policy.value, "maximum_retry_attempts", null)
    }
  }
}

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
  statistic                 = each.value.statistic
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
    try(
      try(each.value.rule_key, null) != null && contains(keys(local.rules), each.value.rule_key)
      ? try(aws_cloudwatch_event_bus.this[local.rules[each.value.rule_key].bus_name].tags, {})
      : {},
      {}
    ),
    try(each.value.tags, {})
  )

  lifecycle {
    precondition {
      condition     = try(each.value.rule_key, null) == null || contains(keys(local.rules), each.value.rule_key)
      error_message = "cloudwatch_metric_alarms[\"${each.key}\"].rule_key must reference an existing module rule in '<bus_name>:<rule_name>' format."
    }
  }
}

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
  statistic                 = each.value.statistic
  threshold                 = each.value.threshold
  treat_missing_data        = try(each.value.treat_missing_data, null)
  unit                      = try(each.value.unit, null)
  actions_enabled           = try(each.value.actions_enabled, true)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])
  dimensions                = local.dlq_cloudwatch_metric_alarm_default_dimensions[each.key]
  tags = merge(
    try(
      try(each.value.target_key, null) != null && contains(keys(local.lambda_targets_with_dlq), each.value.target_key)
      ? try(aws_cloudwatch_event_bus.this[local.lambda_targets_with_dlq[each.value.target_key].bus_name].tags, {})
      : {},
      {}
    ),
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
