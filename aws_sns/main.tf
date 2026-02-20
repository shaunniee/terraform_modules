# =============================================================================
# Locals
# =============================================================================

locals {
  topic_name = var.fifo_topic ? "${var.name}.fifo" : var.name

  # Observability
  observability_enabled  = try(var.observability.enabled, false)
  dashboard_enabled      = local.observability_enabled && try(var.observability.enable_dashboard, true)
  default_alarms_enabled = local.observability_enabled && try(var.observability.enable_default_alarms, true)

  # Check if any subscription uses SMS (for SMS-specific alarm)
  has_sms_subscriptions = anytrue([for k, v in var.subscriptions : v.protocol == "sms"])

  # Opt-in zero-publishes alarm
  zero_publishes_alarm_enabled = local.observability_enabled && try(var.observability.enable_zero_publishes_alarm, false)

  # Default alarms
  default_alarms = local.default_alarms_enabled ? merge(
    {
      failed_notifications = {
        metric_name         = "NumberOfNotificationsFailed"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        threshold           = try(var.observability.failed_notifications_threshold, 1)
        evaluation_periods  = 1
        period              = 300
        statistic           = "Sum"
        extended_statistic  = null
        treat_missing_data  = "notBreaching"
        alarm_description   = "SNS topic ${local.topic_name} has >= ${try(var.observability.failed_notifications_threshold, 1)} failed notification(s) in 5 minutes."
        alarm_actions             = try(var.observability.default_alarm_actions, [])
        ok_actions                = try(var.observability.default_ok_actions, [])
        insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
        tags                      = {}
      }
    },
    local.has_sms_subscriptions ? {
      sms_success_rate = {
        metric_name         = "SMSSuccessRate"
        comparison_operator = "LessThanThreshold"
        threshold           = try(var.observability.sms_success_rate_threshold, 0.9)
        evaluation_periods  = 2
        period              = 300
        statistic           = "Average"
        extended_statistic  = null
        treat_missing_data  = "notBreaching"
        alarm_description   = "SNS topic ${local.topic_name} SMS success rate below ${try(var.observability.sms_success_rate_threshold, 0.9) * 100}%."
        alarm_actions             = try(var.observability.default_alarm_actions, [])
        ok_actions                = try(var.observability.default_ok_actions, [])
        insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
        tags                      = {}
      }
    } : {}
  ) : {}

  # Opt-in zero-publishes alarm (detects dead producers)
  zero_publishes_alarm = local.zero_publishes_alarm_enabled ? {
    zero_publishes = {
      metric_name         = "NumberOfMessagesPublished"
      comparison_operator = "LessThanOrEqualToThreshold"
      threshold           = 0
      evaluation_periods  = try(var.observability.zero_publishes_evaluation_periods, 6)
      period              = 300
      statistic           = "Sum"
      extended_statistic  = null
      treat_missing_data  = "breaching"
      alarm_description   = "No messages published to ${local.topic_name} for ${try(var.observability.zero_publishes_evaluation_periods, 6) * 5} minutes — producer may be down."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
  } : {}

  # Merge: defaults + zero-publishes + user custom alarms (user wins on key collision)
  effective_alarms = merge(local.default_alarms, local.zero_publishes_alarm, var.cloudwatch_metric_alarms)

  # Delivery status logging
  delivery_status_logging_enabled = local.observability_enabled && try(var.observability.enable_delivery_status_logging, false)
  delivery_status_role_arn = local.delivery_status_logging_enabled ? (
    try(var.observability.delivery_status_iam_role_arn, null) != null
    ? var.observability.delivery_status_iam_role_arn
    : aws_iam_role.delivery_status[0].arn
  ) : null
  delivery_status_sample_rate = try(var.observability.delivery_status_success_sample_rate, 100)

  # Anomaly detection alarms
  anomaly_alarms_enabled = local.observability_enabled && try(var.observability.enable_anomaly_detection_alarms, false)

  default_anomaly_alarms = {
    publishes_anomaly = {
      metric_name              = "NumberOfMessagesPublished"
      comparison_operator      = "LessThanLowerOrGreaterThanUpperThreshold"
      statistic                = "Sum"
      period                   = 300
      evaluation_periods       = 2
      treat_missing_data       = "notBreaching"
      anomaly_detection_stddev = 2
      alarm_description        = "Anomaly detected in publish volume for ${local.topic_name}."
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      tags                      = {}
    }
    failed_anomaly = {
      metric_name              = "NumberOfNotificationsFailed"
      comparison_operator      = "GreaterThanUpperThreshold"
      statistic                = "Sum"
      period                   = 300
      evaluation_periods       = 2
      treat_missing_data       = "notBreaching"
      anomaly_detection_stddev = 2
      alarm_description        = "Anomaly detected in notification failures for ${local.topic_name}."
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
# SNS Topic
# =============================================================================

resource "aws_sns_topic" "this" {
  name         = local.topic_name
  display_name = var.display_name

  # FIFO
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.fifo_topic ? var.content_based_deduplication : null
  archive_policy              = var.fifo_topic ? var.archive_policy : null

  # Encryption
  kms_master_key_id = var.kms_master_key_id

  # Policies
  delivery_policy = var.delivery_policy
  policy          = var.topic_policy

  # Delivery status logging (CloudWatch Logs)
  lambda_success_feedback_role_arn      = local.delivery_status_role_arn
  lambda_failure_feedback_role_arn      = local.delivery_status_role_arn
  lambda_success_feedback_sample_rate   = local.delivery_status_logging_enabled ? local.delivery_status_sample_rate : null

  sqs_success_feedback_role_arn         = local.delivery_status_role_arn
  sqs_failure_feedback_role_arn         = local.delivery_status_role_arn
  sqs_success_feedback_sample_rate      = local.delivery_status_logging_enabled ? local.delivery_status_sample_rate : null

  http_success_feedback_role_arn        = local.delivery_status_role_arn
  http_failure_feedback_role_arn        = local.delivery_status_role_arn
  http_success_feedback_sample_rate     = local.delivery_status_logging_enabled ? local.delivery_status_sample_rate : null

  application_success_feedback_role_arn    = local.delivery_status_role_arn
  application_failure_feedback_role_arn    = local.delivery_status_role_arn
  application_success_feedback_sample_rate = local.delivery_status_logging_enabled ? local.delivery_status_sample_rate : null

  firehose_success_feedback_role_arn    = local.delivery_status_role_arn
  firehose_failure_feedback_role_arn    = local.delivery_status_role_arn
  firehose_success_feedback_sample_rate = local.delivery_status_logging_enabled ? local.delivery_status_sample_rate : null

  tags = var.tags

  lifecycle {
    precondition {
      condition = var.fifo_topic ? true : (
        var.content_based_deduplication == false &&
        var.archive_policy == null
      )
      error_message = "content_based_deduplication and archive_policy require fifo_topic = true."
    }
  }
}

# =============================================================================
# Data Protection Policy
# =============================================================================

resource "aws_sns_topic_data_protection_policy" "this" {
  count = var.data_protection_policy != null ? 1 : 0

  arn    = aws_sns_topic.this.arn
  policy = var.data_protection_policy
}

# =============================================================================
# Delivery Status Logging — IAM Role
# =============================================================================

resource "aws_iam_role" "delivery_status" {
  count = local.delivery_status_logging_enabled && try(var.observability.delivery_status_iam_role_arn, null) == null ? 1 : 0

  name = "${var.name}-sns-delivery-status"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "delivery_status" {
  count = local.delivery_status_logging_enabled && try(var.observability.delivery_status_iam_role_arn, null) == null ? 1 : 0

  name = "sns-delivery-status-logging"
  role = aws_iam_role.delivery_status[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:PutMetricFilter",
        "logs:PutRetentionPolicy"
      ]
      Resource = "*"
    }]
  })
}

# =============================================================================
# Subscriptions
# =============================================================================

resource "aws_sns_topic_subscription" "this" {
  for_each = var.subscriptions

  topic_arn = aws_sns_topic.this.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  # Delivery options
  raw_message_delivery = each.value.raw_message_delivery
  filter_policy        = each.value.filter_policy
  filter_policy_scope  = each.value.filter_policy != null ? each.value.filter_policy_scope : null

  # Redrive (DLQ)
  redrive_policy = each.value.redrive_policy

  # Firehose
  subscription_role_arn = each.value.subscription_role_arn

  # Per-subscription delivery policy (HTTP/S)
  delivery_policy = each.value.delivery_policy

  # Confirmation
  confirmation_timeout_in_minutes = each.value.confirmation_timeout_in_minutes

  # Auto-confirm (useful for HTTP/S endpoints)
  endpoint_auto_confirms = each.value.endpoint_auto_confirms

  lifecycle {
    precondition {
      condition     = each.value.raw_message_delivery ? contains(["sqs", "http", "https", "firehose"], each.value.protocol) : true
      error_message = "Subscription '${each.key}': raw_message_delivery is only supported for sqs, http, https, and firehose protocols."
    }
  }
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.observability_enabled ? local.effective_alarms : {}

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = try(each.value.alarm_description, null)
  namespace         = "AWS/SNS"
  metric_name       = each.value.metric_name

  dimensions = {
    TopicName = local.topic_name
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
      namespace   = "AWS/SNS"
      period      = each.value.period
      stat        = each.value.statistic

      dimensions = {
        TopicName = local.topic_name
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

  dashboard_name = substr("sns-${var.name}", 0, 255)

  dashboard_body = jsonencode({
    widgets = concat(
      # Row 1: Publish volume & failed deliveries
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title   = "Messages Published"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", local.topic_name]
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
            title   = "Notifications Failed"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", local.topic_name]
            ]
          }
        }
      ],
      # Row 2: Notifications delivered & filtered out
      [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title   = "Notifications Delivered"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsDelivered", "TopicName", local.topic_name]
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
            title   = "Notifications Filtered Out"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsFilteredOut", "TopicName", local.topic_name]
            ]
          }
        }
      ],
      # Row 3: Publish size & SMS metrics
      [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 12
          height = 6
          properties = {
            title   = "Publish Size (average bytes)"
            region  = data.aws_region.current.name
            stat    = "Average"
            period  = 300
            metrics = [
              ["AWS/SNS", "PublishSize", "TopicName", local.topic_name]
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
            title  = "SMS Success Rate"
            region = data.aws_region.current.name
            stat   = "Average"
            period = 300
            metrics = [
              ["AWS/SNS", "SMSSuccessRate", "TopicName", local.topic_name]
            ]
          }
        }
      ],
      # Row 4: Filtered out by reason
      [
        {
          type   = "metric"
          x      = 0
          y      = 18
          width  = 8
          height = 6
          properties = {
            title   = "Filtered Out — No Message Attributes"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsFilteredOut-NoMessageAttributes", "TopicName", local.topic_name]
            ]
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = 18
          width  = 8
          height = 6
          properties = {
            title   = "Filtered Out — Invalid Attributes"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsFilteredOut-InvalidAttributes", "TopicName", local.topic_name]
            ]
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = 18
          width  = 8
          height = 6
          properties = {
            title   = "Filtered Out — Invalid Message Body"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsFilteredOut-InvalidMessageBody", "TopicName", local.topic_name]
            ]
          }
        }
      ],
      # Row 5: DLQ redrive metrics
      [
        {
          type   = "metric"
          x      = 0
          y      = 24
          width  = 12
          height = 6
          properties = {
            title   = "Notifications Redriven to DLQ"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsRedrivenToDlq", "TopicName", local.topic_name]
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
            title   = "Notifications Failed to Redrive"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/SNS", "NumberOfNotificationsFailedToRedriveToDlq", "TopicName", local.topic_name]
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