# =============================================================================
# Locals
# =============================================================================

locals {
  create_role     = var.execution_role_arn == null
  role_arn        = local.create_role ? aws_iam_role.sfn_role[0].arn : var.execution_role_arn
  role_name       = local.create_role ? aws_iam_role.sfn_role[0].name : null
  logging_enabled = var.logging_level != "OFF"
  log_group_name  = "/aws/states/${var.name}"

  create_log_group = var.create_cloudwatch_log_group && local.logging_enabled

  observability_enabled = try(var.observability.enabled, false)
  dashboard_enabled     = local.observability_enabled && try(var.observability.enable_dashboard, false)

  # ---------------------------------------------------------------------------
  # Default metric alarms (Step Functions)
  # These fire when observability.enabled = true and enable_default_alarms = true
  # ---------------------------------------------------------------------------

  default_metric_alarms = { for k, v in {
    executions_failed = {
      enabled                   = true
      comparison_operator       = "GreaterThanOrEqualToThreshold"
      evaluation_periods        = 1
      metric_name               = "ExecutionsFailed"
      namespace                 = "AWS/States"
      period                    = 60
      statistic                 = "Sum"
      threshold                 = 1
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
    executions_timed_out = {
      enabled                   = true
      comparison_operator       = "GreaterThanOrEqualToThreshold"
      evaluation_periods        = 1
      metric_name               = "ExecutionsTimedOut"
      namespace                 = "AWS/States"
      period                    = 60
      statistic                 = "Sum"
      threshold                 = 1
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
    executions_aborted = {
      enabled                   = true
      comparison_operator       = "GreaterThanOrEqualToThreshold"
      evaluation_periods        = 1
      metric_name               = "ExecutionsAborted"
      namespace                 = "AWS/States"
      period                    = 60
      statistic                 = "Sum"
      threshold                 = 1
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
    execution_throttled = {
      enabled                   = true
      comparison_operator       = "GreaterThanThreshold"
      evaluation_periods        = 1
      metric_name               = "ExecutionThrottled"
      namespace                 = "AWS/States"
      period                    = 60
      statistic                 = "Sum"
      threshold                 = 0
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
    execution_time_p95 = {
      enabled                   = true
      comparison_operator       = "GreaterThanThreshold"
      evaluation_periods        = 3
      metric_name               = "ExecutionTime"
      namespace                 = "AWS/States"
      period                    = 300
      extended_statistic        = "p95"
      threshold                 = 300000
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
  } : k => v if local.observability_enabled && try(var.observability.enable_default_alarms, true) }

  effective_metric_alarms = merge(local.default_metric_alarms, var.metric_alarms)

  enabled_metric_alarms = {
    for alarm_key, alarm in local.effective_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  # ---------------------------------------------------------------------------
  # Default anomaly detection alarms
  # ---------------------------------------------------------------------------

  default_metric_anomaly_alarms = { for k, v in {
    executions_started_anomaly = {
      enabled                   = true
      comparison_operator       = "GreaterThanUpperThreshold"
      evaluation_periods        = 2
      metric_name               = "ExecutionsStarted"
      namespace                 = "AWS/States"
      period                    = 300
      statistic                 = "Sum"
      anomaly_detection_stddev  = 2
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
    execution_time_anomaly = {
      enabled                   = true
      comparison_operator       = "GreaterThanUpperThreshold"
      evaluation_periods        = 2
      metric_name               = "ExecutionTime"
      namespace                 = "AWS/States"
      period                    = 300
      statistic                 = "Average"
      anomaly_detection_stddev  = 2
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
  } : k => v if local.observability_enabled && try(var.observability.enable_anomaly_detection_alarms, false) }

  effective_metric_anomaly_alarms = merge(local.default_metric_anomaly_alarms, var.metric_anomaly_alarms)

  enabled_metric_anomaly_alarms = {
    for alarm_key, alarm in local.effective_metric_anomaly_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  # ---------------------------------------------------------------------------
  # Log metric filters
  # ---------------------------------------------------------------------------

  enabled_log_metric_filters = {
    for filter_key, filter in var.log_metric_filters :
    filter_key => filter
    if try(filter.enabled, true)
  }
}

# =============================================================================
# Data sources
# =============================================================================

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_cloudwatch_log_group" "existing" {
  count = !var.create_cloudwatch_log_group && local.logging_enabled && length(local.enabled_log_metric_filters) > 0 ? 1 : 0

  name = local.log_group_name
}

# =============================================================================
# IAM Role
# =============================================================================

resource "aws_iam_role" "sfn_role" {
  count = local.create_role ? 1 : 0

  name                 = "${var.name}-sfn-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-sfn-role"
  })
}

# CloudWatch Logs write permissions for the state machine
resource "aws_iam_role_policy" "logging" {
  count = local.create_role && local.logging_enabled && var.enable_logging_permissions ? 1 : 0

  name = "${var.name}-sfn-logging"
  role = aws_iam_role.sfn_role[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:CreateLogStream",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# X-Ray tracing permissions
resource "aws_iam_role_policy_attachment" "xray_tracing" {
  count = local.create_role && var.tracing_enabled && var.enable_tracing_permissions ? 1 : 0

  role       = aws_iam_role.sfn_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Additional managed policy attachments
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.create_role ? toset(var.additional_policy_arns) : toset([])

  role       = aws_iam_role.sfn_role[0].name
  policy_arn = each.value
}

# Inline policy attachments
resource "aws_iam_role_policy" "inline" {
  for_each = local.create_role ? var.inline_policies : {}

  name   = each.key
  role   = aws_iam_role.sfn_role[0].name
  policy = each.value
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "sfn" {
  count = local.create_log_group ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.name}-log-group"
  })
}

# =============================================================================
# State Machine
# =============================================================================

resource "aws_sfn_state_machine" "this" {
  name       = var.name
  role_arn   = local.role_arn
  definition = var.definition
  type       = var.type
  publish    = var.publish

  dynamic "logging_configuration" {
    for_each = local.logging_enabled ? [1] : []
    content {
      log_destination        = local.create_log_group ? "${aws_cloudwatch_log_group.sfn[0].arn}:*" : "${local.log_group_name}:*"
      include_execution_data = var.logging_include_execution_data
      level                  = var.logging_level
    }
  }

  dynamic "tracing_configuration" {
    for_each = var.tracing_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "encryption_configuration" {
    for_each = var.encryption_type == "CUSTOMER_MANAGED_KMS_KEY" ? [1] : []
    content {
      type       = var.encryption_type
      kms_key_id = var.kms_key_id
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  depends_on = [
    aws_iam_role_policy.logging,
    aws_iam_role_policy_attachment.xray_tracing,
    aws_cloudwatch_log_group.sfn
  ]

  lifecycle {
    precondition {
      condition     = var.encryption_type != "CUSTOMER_MANAGED_KMS_KEY" || var.kms_key_id != null
      error_message = "kms_key_id is required when encryption_type is CUSTOMER_MANAGED_KMS_KEY."
    }

    precondition {
      condition     = !local.logging_enabled || var.create_cloudwatch_log_group || var.execution_role_arn != null
      error_message = "When logging is enabled and create_cloudwatch_log_group is false, ensure the log group exists and an appropriate role is provided."
    }
  }
}

# =============================================================================
# State Machine Aliases
# =============================================================================

resource "aws_sfn_alias" "this" {
  for_each = var.aliases

  name        = each.key
  description = try(each.value.description, null)

  dynamic "routing_configuration" {
    for_each = length(try(each.value.routing_configuration, [])) > 0 ? each.value.routing_configuration : [{
      state_machine_version_arn = aws_sfn_state_machine.this.state_machine_version_arn
      weight                    = 100
    }]
    content {
      state_machine_version_arn = routing_configuration.value.state_machine_version_arn
      weight                    = routing_configuration.value.weight
    }
  }

  lifecycle {
    precondition {
      condition     = var.publish || length(try(each.value.routing_configuration, [])) > 0
      error_message = "When publish = false, each alias must provide explicit routing_configuration with version ARNs."
    }
  }
}

# =============================================================================
# CloudWatch Metric Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "sfn" {
  for_each = local.enabled_metric_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/States")
  period              = each.value.period
  statistic           = try(each.value.statistic, null)
  extended_statistic  = try(each.value.extended_statistic, null)
  threshold           = each.value.threshold

  datapoints_to_alarm       = try(each.value.datapoints_to_alarm, null)
  treat_missing_data        = try(each.value.treat_missing_data, null)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])

  dimensions = merge(
    try(each.value.dimensions, {}),
    { StateMachineArn = aws_sfn_state_machine.this.arn }
  )

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")
  })
}

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "sfn_anomaly" {
  for_each = local.enabled_metric_anomaly_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = try(each.value.comparison_operator, "GreaterThanUpperThreshold")
  evaluation_periods  = each.value.evaluation_periods
  threshold_metric_id = "ad1"

  datapoints_to_alarm       = try(each.value.datapoints_to_alarm, null)
  treat_missing_data        = try(each.value.treat_missing_data, null)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = each.value.metric_name
      namespace   = try(each.value.namespace, "AWS/States")
      period      = each.value.period
      stat        = each.value.statistic
      dimensions = merge(
        try(each.value.dimensions, {}),
        { StateMachineArn = aws_sfn_state_machine.this.arn }
      )
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${try(each.value.anomaly_detection_stddev, 2)})"
    label       = "${coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")}-band"
    return_data = true
  }

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")
  })
}

# =============================================================================
# CloudWatch Log Metric Filters
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each = local.enabled_log_metric_filters

  name           = "${var.name}-${each.key}"
  log_group_name = local.create_log_group ? aws_cloudwatch_log_group.sfn[0].name : local.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    namespace     = each.value.metric_namespace
    name          = each.value.metric_name
    value         = try(each.value.metric_value, "1")
    default_value = try(each.value.default_value, null)
  }

  lifecycle {
    precondition {
      condition     = local.logging_enabled
      error_message = "logging_level must not be OFF when log_metric_filters are configured."
    }

    precondition {
      condition     = var.create_cloudwatch_log_group || try(data.aws_cloudwatch_log_group.existing[0].name, null) != null
      error_message = "When create_cloudwatch_log_group=false and log_metric_filters are configured, the log group /aws/states/<name> must already exist."
    }
  }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = substr("sfn-${var.name}", 0, 255)

  dashboard_body = jsonencode({
    widgets = concat(
      # Row 1: Executions Started & Succeeded
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Executions Started"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ExecutionsStarted", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Executions Succeeded"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        }
      ],
      # Row 2: Executions Failed & Timed Out
      [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "Executions Failed"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "Executions Timed Out"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        }
      ],
      # Row 3: Execution Time & Throttled
      [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 12
          height = 6
          properties = {
            title  = "Execution Time (ms)"
            region = data.aws_region.current.id
            period = 300
            metrics = [
              ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.this.arn, { stat = "Average", label = "Average" }],
              ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.this.arn, { stat = "p95", label = "p95" }],
              ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.this.arn, { stat = "Maximum", label = "Max" }]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 12
          width  = 12
          height = 6
          properties = {
            title  = "Execution Throttled"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ExecutionThrottled", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        }
      ],
      # Row 4: Aborted & Lambda Function Errors (service integration visibility)
      [
        {
          type   = "metric"
          x      = 0
          y      = 18
          width  = 12
          height = 6
          properties = {
            title  = "Executions Aborted"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ExecutionsAborted", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 18
          width  = 12
          height = 6
          properties = {
            title  = "Lambda Functions Failed"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "LambdaFunctionsFailed", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        }
      ],
      # Row 5: Service Integration Failures & Service Integration Time
      [
        {
          type   = "metric"
          x      = 0
          y      = 24
          width  = 12
          height = 6
          properties = {
            title  = "Service Integrations Failed"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ServiceIntegrationsFailed", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 24
          width  = 12
          height = 6
          properties = {
            title  = "Service Integrations Timed Out"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/States", "ServiceIntegrationsTimedOut", "StateMachineArn", aws_sfn_state_machine.this.arn]
            ]
          }
        }
      ]
    )
  })
}
