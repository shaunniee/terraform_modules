locals {
  create_role      = var.execution_role_arn == null
  lambda_role_arn  = local.create_role ? aws_iam_role.lambda_role[0].arn : var.execution_role_arn
  lambda_role_name = local.create_role ? aws_iam_role.lambda_role[0].name : null
  create_log_group = var.create_cloudwatch_log_group
  log_group_name   = "/aws/lambda/${var.function_name}"
  use_file_source  = var.filename != null
  use_s3_source    = var.s3_bucket != null || var.s3_key != null
  package_hash     = var.source_code_hash != null ? var.source_code_hash : (var.filename != null ? filebase64sha256(var.filename) : null)

  dlq_type = var.dead_letter_target_arn == null ? null : try(element(split(":", var.dead_letter_target_arn), 2), null)
  dlq_name = var.dead_letter_target_arn == null ? null : try(element(split(":", var.dead_letter_target_arn), 5), null)

  enabled_dlq_cloudwatch_metric_alarms = {
    for alarm_key, alarm in var.dlq_cloudwatch_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  enabled_dlq_log_metric_filters = {
    for filter_key, filter in var.dlq_log_metric_filters :
    filter_key => filter
    if try(filter.enabled, true)
  }
}

resource "aws_iam_role" "lambda_role" {
  count = local.create_role ? 1 : 0

  name = "${var.function_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.function_name}-lambda-role"
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  count = local.create_role ? 1 : 0

  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_tracing" {
  count = local.create_role && var.tracing_mode == "Active" ? 1 : 0

  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_cloudwatch_log_group" "lambda" {
  count = local.create_log_group ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.function_name}-log-group"
  })
}

resource "aws_lambda_function" "this" {
  function_name     = var.function_name
  role              = local.lambda_role_arn
  description       = var.description
  handler           = var.handler
  runtime           = var.runtime
  filename          = var.filename
  s3_bucket         = var.s3_bucket
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version

  timeout                        = var.timeout
  memory_size                    = var.memory_size
  publish                        = var.publish
  architectures                  = var.architectures
  layers                         = var.layers
  reserved_concurrent_executions = var.reserved_concurrent_executions
  kms_key_arn                    = var.kms_key_arn
  source_code_hash               = local.package_hash

  environment {
    variables = var.environment_variables
  }

  ephemeral_storage {
    size = var.ephemeral_storage_size
  }

  tracing_config {
    mode = var.tracing_mode
  }

  tags = merge(var.tags, {
    Name = "${var.function_name}-function"
  })

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy_attachment.xray_tracing,
    aws_cloudwatch_log_group.lambda
  ]

  lifecycle {
    precondition {
      condition     = local.use_file_source != local.use_s3_source
      error_message = "Set exactly one package source: filename OR s3_bucket+s3_key."
    }

    precondition {
      condition     = !local.use_s3_source || (var.s3_bucket != null && var.s3_key != null)
      error_message = "When using S3 source, both s3_bucket and s3_key are required."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda" {
  for_each = var.metric_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.function_name}-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/Lambda")
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
    { FunctionName = aws_lambda_function.this.function_name },
    try(each.value.dimensions, {})
  )

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.function_name}-${each.key}")
  })
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = local.enabled_dlq_cloudwatch_metric_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.function_name}-dlq-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = coalesce(try(each.value.namespace, null), local.dlq_type == "sqs" ? "AWS/SQS" : local.dlq_type == "sns" ? "AWS/SNS" : null)
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
    local.dlq_type == "sqs" ? { QueueName = local.dlq_name } : local.dlq_type == "sns" ? { TopicName = local.dlq_name } : {},
    try(each.value.dimensions, {})
  )

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.function_name}-dlq-${each.key}")
  })

  lifecycle {
    precondition {
      condition     = var.dead_letter_target_arn != null
      error_message = "dead_letter_target_arn must be set when using dlq_cloudwatch_metric_alarms."
    }

    precondition {
      condition     = local.dlq_type == "sqs" || local.dlq_type == "sns"
      error_message = "dead_letter_target_arn must be an SQS or SNS ARN when using dlq_cloudwatch_metric_alarms."
    }

    precondition {
      condition     = local.dlq_name != null
      error_message = "Could not resolve DLQ resource name from dead_letter_target_arn."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "dlq" {
  for_each = local.enabled_dlq_log_metric_filters

  name           = "${var.function_name}-dlq-${each.key}"
  log_group_name = local.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    namespace     = each.value.metric_namespace
    name          = each.value.metric_name
    value         = try(each.value.metric_value, "1")
    default_value = try(each.value.default_value, null)
  }

  lifecycle {
    precondition {
      condition     = var.dead_letter_target_arn != null
      error_message = "dead_letter_target_arn must be set when using dlq_log_metric_filters."
    }
  }
}

resource "aws_lambda_alias" "this" {
  for_each = var.aliases

  name             = each.key
  description      = try(each.value.description, null)
  function_name    = aws_lambda_function.this.function_name
  function_version = coalesce(try(each.value.function_version, null), aws_lambda_function.this.version)

  dynamic "routing_config" {
    for_each = length(try(each.value.routing_additional_version_weights, {})) > 0 ? [1] : []
    content {
      additional_version_weights = each.value.routing_additional_version_weights
    }
  }

  lifecycle {
    precondition {
      condition     = var.publish || try(each.value.function_version, null) != null
      error_message = "When publish = false, each alias must set function_version explicitly."
    }
  }
}
