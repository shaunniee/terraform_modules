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
