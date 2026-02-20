locals {
  attribute_names = [for a in var.attributes : a.name]
  used_attribute_names = distinct(compact(concat(
    [var.hash_key],
    var.range_key == null ? [] : [var.range_key],
    [for g in var.global_secondary_indexes : g.hash_key],
    [for g in var.global_secondary_indexes : try(g.range_key, null)],
    [for l in var.local_secondary_indexes : l.range_key]
  )))

  observability_enabled = try(var.observability.enabled, false)

  default_cloudwatch_metric_alarms = local.observability_enabled && try(var.observability.enable_default_alarms, true) ? {
    throttled_requests = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "ThrottledRequests"
      namespace           = "AWS/DynamoDB"
      period              = 60
      statistic           = "Sum"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
    user_errors = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "UserErrors"
      namespace           = "AWS/DynamoDB"
      period              = 60
      statistic           = "Sum"
      threshold           = 5
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
    system_errors = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "SystemErrors"
      namespace           = "AWS/DynamoDB"
      period              = 60
      statistic           = "Sum"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
    successful_request_latency_p95 = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "SuccessfulRequestLatency"
      namespace           = "AWS/DynamoDB"
      period              = 60
      extended_statistic  = "p95"
      threshold           = 50
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
  } : {}

  effective_cloudwatch_metric_alarms = merge(local.default_cloudwatch_metric_alarms, var.cloudwatch_metric_alarms)

  enabled_cloudwatch_metric_alarms = {
    for alarm_key, alarm in local.effective_cloudwatch_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  default_cloudwatch_metric_anomaly_alarms = local.observability_enabled && try(var.observability.enable_anomaly_detection_alarms, false) ? {
    consumed_read_capacity_units_anomaly = {
      enabled                  = true
      comparison_operator      = "GreaterThanUpperThreshold"
      evaluation_periods       = 2
      metric_name              = "ConsumedReadCapacityUnits"
      namespace                = "AWS/DynamoDB"
      period                   = 300
      statistic                = "Sum"
      anomaly_detection_stddev = 2
      treat_missing_data       = "notBreaching"
      alarm_actions            = try(var.observability.default_alarm_actions, [])
      ok_actions               = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions               = {}
      tags                     = {}
    }
    consumed_write_capacity_units_anomaly = {
      enabled                  = true
      comparison_operator      = "GreaterThanUpperThreshold"
      evaluation_periods       = 2
      metric_name              = "ConsumedWriteCapacityUnits"
      namespace                = "AWS/DynamoDB"
      period                   = 300
      statistic                = "Sum"
      anomaly_detection_stddev = 2
      treat_missing_data       = "notBreaching"
      alarm_actions            = try(var.observability.default_alarm_actions, [])
      ok_actions               = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions               = {}
      tags                     = {}
    }
  } : {}

  effective_cloudwatch_metric_anomaly_alarms = merge(local.default_cloudwatch_metric_anomaly_alarms, var.cloudwatch_metric_anomaly_alarms)

  enabled_cloudwatch_metric_anomaly_alarms = {
    for alarm_key, alarm in local.effective_cloudwatch_metric_anomaly_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  contributor_insights_config_explicit = (
    try(var.contributor_insights.table_enabled, false) ||
    try(var.contributor_insights.all_global_secondary_indexes_enabled, false) ||
    length(try(var.contributor_insights.global_secondary_index_names, [])) > 0
  )

  effective_contributor_insights = local.observability_enabled && !local.contributor_insights_config_explicit ? merge(
    var.contributor_insights,
    {
      table_enabled                         = try(var.observability.enable_contributor_insights_table, true)
      all_global_secondary_indexes_enabled = try(var.observability.enable_contributor_insights_all_global_secondary_indexes, true)
    }
  ) : var.contributor_insights

  effective_cloudtrail_data_events = local.observability_enabled ? merge(
    var.cloudtrail_data_events,
    {
      enabled        = try(var.cloudtrail_data_events.enabled, false) || try(var.observability.enable_cloudtrail_data_events, false)
      s3_bucket_name = coalesce(try(var.cloudtrail_data_events.s3_bucket_name, null), try(var.observability.cloudtrail_s3_bucket_name, null))
    }
  ) : var.cloudtrail_data_events

  cloudtrail_enabled           = try(local.effective_cloudtrail_data_events.enabled, false)
  cloudtrail_logs_enabled      = local.cloudtrail_enabled && try(local.effective_cloudtrail_data_events.cloud_watch_logs_enabled, false)
  create_cloudtrail_cwlogs_role = local.cloudtrail_logs_enabled && try(local.effective_cloudtrail_data_events.create_cloud_watch_logs_role, false)
  cloudtrail_log_group_name    = coalesce(try(local.effective_cloudtrail_data_events.cloud_watch_logs_group_name, null), "/aws/cloudtrail/${var.table_name}-data-events")
  use_existing_cloudtrail_log_group = local.cloudtrail_logs_enabled && try(local.effective_cloudtrail_data_events.cloud_watch_logs_group_name, null) != null
  need_cloudtrail_identity_context = local.use_existing_cloudtrail_log_group
  cloudtrail_log_group_base_arn = (
    local.use_existing_cloudtrail_log_group
    ? format("arn:%s:logs:%s:%s:log-group:%s", data.aws_partition.current[0].partition, data.aws_region.current[0].name, data.aws_caller_identity.current[0].account_id, local.cloudtrail_log_group_name)
    : try(aws_cloudwatch_log_group.cloudtrail_data_events[0].arn, null)
  )
  cloudtrail_log_group_arn = local.cloudtrail_log_group_base_arn == null ? null : format("%s:*", local.cloudtrail_log_group_base_arn)

  contributor_insights_enabled_gsi_names = (
    try(local.effective_contributor_insights.all_global_secondary_indexes_enabled, false)
    ? [for g in var.global_secondary_indexes : g.name]
    : try(local.effective_contributor_insights.global_secondary_index_names, [])
  )
}

data "aws_partition" "current" {
  count = local.need_cloudtrail_identity_context ? 1 : 0
}

data "aws_region" "current" {
  count = local.need_cloudtrail_identity_context ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.need_cloudtrail_identity_context ? 1 : 0
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name = global_secondary_index.value.name

        hash_key = global_secondary_index.value.hash_key
        range_key = try(global_secondary_index.value.range_key, null)
    

      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null
      read_capacity      = var.billing_mode == "PROVISIONED" ? try(global_secondary_index.value.read_capacity, null) : null
      write_capacity     = var.billing_mode == "PROVISIONED" ? try(global_secondary_index.value.write_capacity, null) : null
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes
    content {
      name               = local_secondary_index.value.name
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.projection_type == "INCLUDE" ? local_secondary_index.value.non_key_attributes : null
    }
  }

  dynamic "replica" {
    for_each = var.replicas
    content {
      region_name = replica.value.region_name
      kms_key_arn = try(replica.value.kms_key_arn, null)
    }
  }

  dynamic "ttl" {
    for_each = var.ttl.enabled ? [1] : []
    content {
      enabled        = true
      attribute_name = var.ttl.attribute_name
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = var.server_side_encryption.enabled
    kms_key_arn = var.server_side_encryption.kms_key_arn
  }

  stream_enabled   = var.stream_enabled
  stream_view_type = var.stream_enabled ? var.stream_view_type : null

  deletion_protection_enabled = var.deletion_protection_enabled
  table_class                 = var.table_class
  tags                        = var.tags

  lifecycle {
    precondition {
      condition     = contains(local.attribute_names, var.hash_key)
      error_message = "hash_key must be defined in attributes."
    }

    precondition {
      condition     = var.range_key == null || contains(local.attribute_names, var.range_key)
      error_message = "range_key must be null or defined in attributes."
    }

    precondition {
      condition = alltrue([
        for g in var.global_secondary_indexes :
        contains(local.attribute_names, g.hash_key) && (try(g.range_key, null) == null || contains(local.attribute_names, g.range_key))
      ])
      error_message = "All global_secondary_indexes hash_key/range_key values must be defined in attributes."
    }

    precondition {
      condition = alltrue([
        for l in var.local_secondary_indexes : contains(local.attribute_names, l.range_key)
      ])
      error_message = "All local_secondary_indexes range_key values must be defined in attributes."
    }

    precondition {
      condition     = var.range_key != null || length(var.local_secondary_indexes) == 0
      error_message = "local_secondary_indexes require table range_key to be set."
    }

    precondition {
      condition     = length(setsubtract(local.attribute_names, local.used_attribute_names)) == 0
      error_message = "attributes must only include key attributes used by table, GSIs, or LSIs."
    }

    precondition {
      condition     = var.billing_mode == "PROVISIONED" ? (var.read_capacity != null && var.write_capacity != null) : (var.read_capacity == null && var.write_capacity == null)
      error_message = "For PROVISIONED billing_mode, read_capacity and write_capacity are required; for PAY_PER_REQUEST they must be null."
    }

    precondition {
      condition = var.billing_mode == "PROVISIONED" ? alltrue([
        for g in var.global_secondary_indexes :
        try(g.read_capacity, null) != null && try(g.write_capacity, null) != null
        ]) : alltrue([
        for g in var.global_secondary_indexes :
        try(g.read_capacity, null) == null && try(g.write_capacity, null) == null
      ])
      error_message = "GSI capacities must be set in PROVISIONED mode and omitted in PAY_PER_REQUEST mode."
    }

    precondition {
      condition     = !var.stream_enabled || var.stream_view_type != null
      error_message = "stream_view_type is required when stream_enabled = true."
    }

    precondition {
      condition     = var.stream_enabled || var.stream_view_type == null
      error_message = "stream_view_type must be null when stream_enabled = false."
    }

    precondition {
      condition     = length(var.replicas) == 0 || var.stream_enabled
      error_message = "DynamoDB global tables require stream_enabled = true when replicas are configured."
    }

    precondition {
      condition     = length(var.replicas) == 0 || var.stream_view_type == "NEW_AND_OLD_IMAGES"
      error_message = "DynamoDB global tables require stream_view_type = NEW_AND_OLD_IMAGES when replicas are configured."
    }

    precondition {
      condition     = !var.ttl.enabled || (try(var.ttl.attribute_name, null) != null && trimspace(var.ttl.attribute_name) != "")
      error_message = "ttl.attribute_name is required when ttl.enabled = true."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb" {
  for_each = local.enabled_cloudwatch_metric_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.table_name}-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/DynamoDB")
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
    { TableName = aws_dynamodb_table.this.name },
    try(each.value.dimensions, {})
  )

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.table_name}-${each.key}")
  })
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_anomaly" {
  for_each = local.enabled_cloudwatch_metric_anomaly_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.table_name}-${each.key}")
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
      namespace   = try(each.value.namespace, "AWS/DynamoDB")
      period      = each.value.period
      stat        = each.value.statistic
      dimensions = merge(
        { TableName = aws_dynamodb_table.this.name },
        try(each.value.dimensions, {})
      )
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${try(each.value.anomaly_detection_stddev, 2)})"
    label       = "${coalesce(try(each.value.alarm_name, null), "${var.table_name}-${each.key}")}-band"
    return_data = true
  }

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.table_name}-${each.key}")
  })
}

resource "aws_dynamodb_contributor_insights" "table" {
  count = try(local.effective_contributor_insights.table_enabled, false) ? 1 : 0

  table_name = aws_dynamodb_table.this.name
}

resource "aws_dynamodb_contributor_insights" "gsi" {
  for_each = toset(local.contributor_insights_enabled_gsi_names)

  table_name = aws_dynamodb_table.this.name
  index_name = each.value
}

resource "aws_cloudtrail" "dynamodb_data_events" {
  count = local.cloudtrail_enabled ? 1 : 0

  depends_on = [
    aws_iam_role_policy.cloudtrail_to_cwlogs,
    aws_cloudwatch_log_group.cloudtrail_data_events
  ]

  name                          = coalesce(try(local.effective_cloudtrail_data_events.trail_name, null), "${var.table_name}-data-events")
  s3_bucket_name                = local.effective_cloudtrail_data_events.s3_bucket_name
  kms_key_id                    = try(local.effective_cloudtrail_data_events.kms_key_id, null)
  enable_log_file_validation    = try(local.effective_cloudtrail_data_events.enable_log_file_validation, true)
  cloud_watch_logs_group_arn    = local.cloudtrail_logs_enabled ? local.cloudtrail_log_group_arn : null
  cloud_watch_logs_role_arn     = local.cloudtrail_logs_enabled ? coalesce(try(local.effective_cloudtrail_data_events.cloud_watch_logs_role_arn, null), try(aws_iam_role.cloudtrail_to_cwlogs[0].arn, null)) : null
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    include_management_events = try(local.effective_cloudtrail_data_events.include_management_events, false)
    read_write_type           = try(local.effective_cloudtrail_data_events.read_write_type, "All")

    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = [aws_dynamodb_table.this.arn]
    }
  }

  tags = merge(var.tags, try(local.effective_cloudtrail_data_events.tags, {}))
}

resource "aws_cloudwatch_log_group" "cloudtrail_data_events" {
  count = local.cloudtrail_logs_enabled && try(local.effective_cloudtrail_data_events.cloud_watch_logs_group_name, null) == null ? 1 : 0

  name              = local.cloudtrail_log_group_name
  retention_in_days = try(local.effective_cloudtrail_data_events.cloud_watch_logs_retention_in_days, 90)
  kms_key_id        = try(local.effective_cloudtrail_data_events.kms_key_id, null)
  tags              = merge(var.tags, try(local.effective_cloudtrail_data_events.tags, {}))
}

data "aws_iam_policy_document" "cloudtrail_to_cwlogs_assume" {
  count = local.create_cloudtrail_cwlogs_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cloudtrail_to_cwlogs" {
  count = local.create_cloudtrail_cwlogs_role ? 1 : 0

  name               = "${var.table_name}-cloudtrail-cwlogs"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_to_cwlogs_assume[0].json
  tags               = merge(var.tags, try(local.effective_cloudtrail_data_events.tags, {}))
}

data "aws_iam_policy_document" "cloudtrail_to_cwlogs" {
  count = local.create_cloudtrail_cwlogs_role ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      local.cloudtrail_log_group_arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogStreams"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy" "cloudtrail_to_cwlogs" {
  count = local.create_cloudtrail_cwlogs_role ? 1 : 0

  name   = "${var.table_name}-cloudtrail-cwlogs"
  role   = aws_iam_role.cloudtrail_to_cwlogs[0].id
  policy = data.aws_iam_policy_document.cloudtrail_to_cwlogs[0].json
}
