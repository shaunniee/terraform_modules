# =============================================================================
# Locals
# =============================================================================

locals {
  queue_name = var.fifo_queue ? "${var.name}.fifo" : var.name
  dlq_name   = var.fifo_queue ? "${var.name}-dlq.fifo" : "${var.name}-dlq"

  # DLQ resolution: managed DLQ, external DLQ, or none
  has_dlq     = var.create_dlq || var.dlq_arn != null
  dlq_arn     = var.create_dlq ? aws_sqs_queue.dlq[0].arn : var.dlq_arn
  dlq_url     = var.create_dlq ? aws_sqs_queue.dlq[0].url : (var.dlq_arn != null ? data.aws_sqs_queue.external_dlq[0].url : null)
  dlq_name_resolved = var.create_dlq ? aws_sqs_queue.dlq[0].name : (
    var.dlq_arn != null ? data.aws_sqs_queue.external_dlq[0].name : null
  )

  # Observability
  observability_enabled = try(var.observability.enabled, false)
  dashboard_enabled     = local.observability_enabled && try(var.observability.enable_dashboard, true)

  # Default alarms (only when observability + defaults enabled)
  default_alarms_enabled  = local.observability_enabled && try(var.observability.enable_default_alarms, true)
  dlq_alarm_enabled          = local.observability_enabled && try(var.observability.enable_dlq_alarm, true) && local.has_dlq
  zero_sends_alarm_enabled    = local.observability_enabled && try(var.observability.enable_zero_sends_alarm, false)
  empty_receives_alarm_enabled = local.observability_enabled && try(var.observability.enable_empty_receives_alarm, false)
  anomaly_alarms_enabled       = local.observability_enabled && try(var.observability.enable_anomaly_detection_alarms, false)

  default_alarms = local.default_alarms_enabled ? {
    queue_depth = {
      queue               = "main"
      metric_name         = "ApproximateNumberOfMessagesVisible"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = try(var.observability.queue_depth_threshold, 1000)
      evaluation_periods  = 2
      period              = 300
      statistic           = "Maximum"
      extended_statistic  = null
      treat_missing_data  = "notBreaching"
      alarm_description   = "Queue depth exceeds ${try(var.observability.queue_depth_threshold, 1000)} messages on ${local.queue_name}."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
    oldest_message_age = {
      queue               = "main"
      metric_name         = "ApproximateAgeOfOldestMessage"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = try(var.observability.oldest_message_age_threshold, 3600)
      evaluation_periods  = 2
      period              = 300
      statistic           = "Maximum"
      extended_statistic  = null
      treat_missing_data  = "notBreaching"
      alarm_description   = "Oldest message age exceeds ${try(var.observability.oldest_message_age_threshold, 3600)}s on ${local.queue_name}."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
  } : {}

  zero_sends_alarm = local.zero_sends_alarm_enabled ? {
    zero_sends = {
      queue               = "main"
      metric_name         = "NumberOfMessagesSent"
      comparison_operator = "LessThanOrEqualToThreshold"
      threshold           = 0
      evaluation_periods  = try(var.observability.zero_sends_evaluation_periods, 3)
      period              = 300
      statistic           = "Sum"
      extended_statistic  = null
      treat_missing_data  = "breaching"
      alarm_description   = "No messages sent to ${local.queue_name} for ${try(var.observability.zero_sends_evaluation_periods, 3) * 5} minutes — producer may be down."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
  } : {}

  empty_receives_alarm = local.empty_receives_alarm_enabled ? {
    empty_receives = {
      queue               = "main"
      metric_name         = "NumberOfEmptyReceives"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = try(var.observability.empty_receives_threshold, 1000)
      evaluation_periods  = 2
      period              = 300
      statistic           = "Sum"
      extended_statistic  = null
      treat_missing_data  = "notBreaching"
      alarm_description   = "Queue ${local.queue_name} has >= ${try(var.observability.empty_receives_threshold, 1000)} empty receives in 5 minutes — consider enabling long polling."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
  } : {}

  dlq_default_alarm = local.dlq_alarm_enabled ? {
    dlq_depth = {
      queue               = "dlq"
      metric_name         = "ApproximateNumberOfMessagesVisible"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = try(var.observability.dlq_depth_threshold, 1)
      evaluation_periods  = 1
      period              = 300
      statistic           = "Maximum"
      extended_statistic  = null
      treat_missing_data  = "notBreaching"
      alarm_description   = "DLQ ${local.dlq_name} has messages — failed processing detected."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
  } : {}

  # Merge default alarms + user custom alarms (user overrides defaults on key collision)
  effective_alarms = merge(local.default_alarms, local.zero_sends_alarm, local.empty_receives_alarm, local.dlq_default_alarm, var.cloudwatch_metric_alarms)

  # Separate alarms by queue target for dimension resolution
  main_queue_alarms = { for k, v in local.effective_alarms : k => v if v.queue == "main" }
  dlq_alarms        = { for k, v in local.effective_alarms : k => v if v.queue == "dlq" && local.has_dlq }

  # Anomaly detection alarms
  default_anomaly_alarms = {
    queue_depth_anomaly = {
      metric_name              = "ApproximateNumberOfMessagesVisible"
      comparison_operator      = "GreaterThanUpperThreshold"
      statistic                = "Maximum"
      period                   = 300
      evaluation_periods       = 2
      treat_missing_data       = "notBreaching"
      anomaly_detection_stddev = 2
      alarm_description        = "Anomaly detected in queue depth for ${local.queue_name}."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
    message_age_anomaly = {
      metric_name              = "ApproximateAgeOfOldestMessage"
      comparison_operator      = "GreaterThanUpperThreshold"
      statistic                = "Maximum"
      period                   = 300
      evaluation_periods       = 2
      treat_missing_data       = "notBreaching"
      anomaly_detection_stddev = 2
      alarm_description        = "Anomaly detected in oldest message age for ${local.queue_name}."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
  }

  effective_anomaly_alarms = local.anomaly_alarms_enabled ? merge(local.default_anomaly_alarms, var.cloudwatch_metric_anomaly_alarms) : {}
  enabled_anomaly_alarms  = { for k, v in local.effective_anomaly_alarms : k => v if try(v.enabled, true) }
}

# =============================================================================
# Main Queue
# =============================================================================

resource "aws_sqs_queue" "this" {
  name = local.queue_name

  # Core settings
  fifo_queue                 = var.fifo_queue
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size

  # FIFO-specific
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null
  deduplication_scope         = var.fifo_queue ? var.deduplication_scope : null
  fifo_throughput_limit       = var.fifo_queue ? var.fifo_throughput_limit : null

  # Encryption
  sqs_managed_sse_enabled           = var.kms_master_key_id == null ? var.sqs_managed_sse_enabled : null
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? var.kms_data_key_reuse_period_seconds : null

  # Redrive policy (managed DLQ or external DLQ)
  redrive_policy = local.has_dlq ? jsonencode({
    deadLetterTargetArn = local.dlq_arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = var.tags
}

# =============================================================================
# Managed Dead-Letter Queue
# =============================================================================

resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name = local.dlq_name

  # Core settings
  fifo_queue                 = var.fifo_queue
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.dlq_message_retention_seconds

  # Encryption — mirror main queue
  sqs_managed_sse_enabled           = var.kms_master_key_id == null ? var.sqs_managed_sse_enabled : null
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? var.kms_data_key_reuse_period_seconds : null

  tags = merge(var.tags, var.dlq_tags, { Purpose = "dead-letter-queue" })
}

# =============================================================================
# Redrive Allow Policy (allows main queue to redrive from managed DLQ)
# =============================================================================

resource "aws_sqs_queue_redrive_allow_policy" "this" {
  count = var.create_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].url

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

# =============================================================================
# Queue Policies
# =============================================================================

resource "aws_sqs_queue_policy" "main" {
  count = var.queue_policy != null ? 1 : 0

  queue_url = aws_sqs_queue.this.url
  policy    = var.queue_policy
}

resource "aws_sqs_queue_policy" "dlq" {
  count = var.create_dlq && var.dlq_queue_policy != null ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].url
  policy    = var.dlq_queue_policy
}

# =============================================================================
# CloudWatch Alarms — Main Queue
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "main" {
  for_each = local.observability_enabled ? local.main_queue_alarms : {}

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = try(each.value.alarm_description, null)
  namespace         = "AWS/SQS"
  metric_name       = each.value.metric_name

  dimensions = {
    QueueName = local.queue_name
  }

  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  period              = each.value.period
  statistic           = each.value.extended_statistic == null ? each.value.statistic : null
  extended_statistic  = each.value.extended_statistic
  treat_missing_data  = each.value.treat_missing_data

  alarm_actions             = try(each.value.alarm_actions, try(var.observability.default_alarm_actions, []))
  ok_actions                = try(each.value.ok_actions, try(var.observability.default_ok_actions, []))
  insufficient_data_actions = try(each.value.insufficient_data_actions, try(var.observability.default_insufficient_data_actions, []))

  tags = merge(var.tags, try(each.value.tags, {}))
}

# =============================================================================
# CloudWatch Alarms — DLQ
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = local.observability_enabled ? local.dlq_alarms : {}

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = try(each.value.alarm_description, null)
  namespace         = "AWS/SQS"
  metric_name       = each.value.metric_name

  dimensions = {
    QueueName = local.dlq_name_resolved
  }

  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  period              = each.value.period
  statistic           = each.value.extended_statistic == null ? each.value.statistic : null
  extended_statistic  = each.value.extended_statistic
  treat_missing_data  = each.value.treat_missing_data

  alarm_actions             = try(each.value.alarm_actions, try(var.observability.default_alarm_actions, []))
  ok_actions                = try(each.value.ok_actions, try(var.observability.default_ok_actions, []))
  insufficient_data_actions = try(each.value.insufficient_data_actions, try(var.observability.default_insufficient_data_actions, []))

  tags = merge(var.tags, try(each.value.tags, {}))
}

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "anomaly" {
  for_each = local.enabled_anomaly_alarms

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  treat_missing_data  = each.value.treat_missing_data
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = each.value.metric_name
      namespace   = "AWS/SQS"
      period      = each.value.period
      stat        = each.value.statistic

      dimensions = {
        QueueName = local.queue_name
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${each.value.anomaly_detection_stddev})"
    label       = "${each.value.metric_name} Anomaly Band"
    return_data = true
  }

  alarm_actions             = try(each.value.alarm_actions, try(var.observability.default_alarm_actions, []))
  ok_actions                = try(each.value.ok_actions, try(var.observability.default_ok_actions, []))
  insufficient_data_actions = try(each.value.insufficient_data_actions, try(var.observability.default_insufficient_data_actions, []))

  tags = merge(var.tags, try(each.value.tags, {}))
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = substr("sqs-${var.name}", 0, 255)

  dashboard_body = jsonencode({
    widgets = concat(
      # Row 1: Queue depth & age
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title   = "Messages Visible"
            region  = data.aws_region.current.name
            stat    = "Maximum"
            period  = 300
            metrics = [
              ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.queue_name]
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
            title   = "Oldest Message Age (seconds)"
            region  = data.aws_region.current.name
            stat    = "Maximum"
            period  = 300
            metrics = [
              ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.queue_name]
            ]
          }
        }
      ],
      # Row 2: Messages sent/received/deleted
      [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 8
          height = 6
          properties = {
            title   = "Messages Sent"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.queue_name]
            ]
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = 6
          width  = 8
          height = 6
          properties = {
            title   = "Messages Received"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SQS", "NumberOfMessagesReceived", "QueueName", local.queue_name]
            ]
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = 6
          width  = 8
          height = 6
          properties = {
            title   = "Messages Deleted"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", local.queue_name]
            ]
          }
        }
      ],
      # Row 3: In-flight & not visible
      [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 12
          height = 6
          properties = {
            title   = "Messages In Flight"
            region  = data.aws_region.current.name
            stat    = "Maximum"
            period  = 300
            metrics = [
              ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", local.queue_name]
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
            title   = "Messages Delayed"
            region  = data.aws_region.current.name
            stat    = "Maximum"
            period  = 300
            metrics = [
              ["AWS/SQS", "ApproximateNumberOfMessagesDelayed", "QueueName", local.queue_name]
            ]
          }
        }
      ],
      # Row 4: Empty receives + DLQ depth (if DLQ exists)
      [
        {
          type   = "metric"
          x      = 0
          y      = 18
          width  = 12
          height = 6
          properties = {
            title   = "Empty Receives"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SQS", "NumberOfEmptyReceives", "QueueName", local.queue_name]
            ]
          }
        }
      ],
      local.has_dlq ? [
        {
          type   = "metric"
          x      = 12
          y      = 18
          width  = 12
          height = 6
          properties = {
            title   = "DLQ Depth"
            region  = data.aws_region.current.name
            stat    = "Maximum"
            period  = 300
            metrics = [
              ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.dlq_name_resolved]
            ]
          }
        }
      ] : [],
      # Row 5: Message size
      [
        {
          type   = "metric"
          x      = 0
          y      = 24
          width  = 12
          height = 6
          properties = {
            title   = "Sent Message Size (Avg)"
            region  = data.aws_region.current.name
            stat    = "Average"
            period  = 300
            metrics = [
              ["AWS/SQS", "SentMessageSize", "QueueName", local.queue_name]
            ]
          }
        }
      ]
    )
  })
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_region" "current" {}

# Look up external DLQ for robust name/URL resolution
data "aws_sqs_queue" "external_dlq" {
  count = var.dlq_arn != null && !var.create_dlq ? 1 : 0

  name = regex("[^:]+$", var.dlq_arn)
}