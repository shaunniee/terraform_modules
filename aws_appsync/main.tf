# =============================================================================
# Locals
# =============================================================================

locals {
  create_logging_role = var.logging_enabled && var.logging_role_arn == null
  logging_role_arn    = local.create_logging_role ? aws_iam_role.logging[0].arn : var.logging_role_arn
  log_group_name      = "/aws/appsync/apis/${var.name}"

  create_log_group = var.create_cloudwatch_log_group && var.logging_enabled

  observability_enabled = try(var.observability.enabled, false)
  dashboard_enabled     = local.observability_enabled && try(var.observability.enable_dashboard, false)

  # Resolve function keys → function IDs for pipeline resolvers
  function_id_map = { for k, v in aws_appsync_function.this : k => v.function_id }

  # ---------------------------------------------------------------------------
  # Default metric alarms (AppSync)
  # ---------------------------------------------------------------------------

  default_metric_alarms = { for k, v in {
    "5xx_errors" = {
      enabled                   = true
      comparison_operator       = "GreaterThanOrEqualToThreshold"
      evaluation_periods        = 1
      metric_name               = "5XXError"
      namespace                 = "AWS/AppSync"
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
    "4xx_errors" = {
      enabled                   = true
      comparison_operator       = "GreaterThanThreshold"
      evaluation_periods        = 3
      metric_name               = "4XXError"
      namespace                 = "AWS/AppSync"
      period                    = 60
      statistic                 = "Sum"
      threshold                 = 10
      treat_missing_data        = "notBreaching"
      alarm_actions             = try(var.observability.default_alarm_actions, [])
      ok_actions                = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions                = {}
      tags                      = {}
    }
    latency_p95 = {
      enabled                   = true
      comparison_operator       = "GreaterThanThreshold"
      evaluation_periods        = 3
      metric_name               = "Latency"
      namespace                 = "AWS/AppSync"
      period                    = 300
      extended_statistic        = "p95"
      threshold                 = 5000
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
    requests_anomaly = {
      enabled                   = true
      comparison_operator       = "GreaterThanUpperThreshold"
      evaluation_periods        = 2
      metric_name               = "Latency"
      namespace                 = "AWS/AppSync"
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

# =============================================================================
# IAM Role for CloudWatch Logging
# =============================================================================

resource "aws_iam_role" "logging" {
  count = local.create_logging_role ? 1 : 0

  name                 = "${var.name}-appsync-logging-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
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
    Name = "${var.name}-appsync-logging-role"
  })
}

resource "aws_iam_role_policy" "logging" {
  count = local.create_logging_role ? 1 : 0

  name = "${var.name}-appsync-logging"
  role = aws_iam_role.logging[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/appsync/apis/*"
      }
    ]
  })
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "appsync" {
  count = local.create_log_group ? 1 : 0

  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.this.id}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.name}-appsync-log-group"
  })
}

# =============================================================================
# GraphQL API
# =============================================================================

resource "aws_appsync_graphql_api" "this" {
  name                 = var.name
  authentication_type  = var.authentication_type
  api_type             = var.api_type
  schema               = var.schema
  visibility           = var.visibility
  introspection_config = var.introspection_config
  query_depth_limit    = var.query_depth_limit > 0 ? var.query_depth_limit : null
  resolver_count_limit = var.resolver_count_limit > 0 ? var.resolver_count_limit : null
  xray_enabled         = var.xray_enabled

  # Merged API
  merged_api_execution_role_arn = var.api_type == "MERGED" ? var.merged_api_execution_role_arn : null

  # Default Cognito auth
  dynamic "user_pool_config" {
    for_each = var.authentication_type == "AMAZON_COGNITO_USER_POOLS" && var.user_pool_config != null ? [var.user_pool_config] : []
    content {
      user_pool_id        = user_pool_config.value.user_pool_id
      aws_region          = try(user_pool_config.value.aws_region, null)
      app_id_client_regex = try(user_pool_config.value.app_id_client_regex, null)
      default_action      = try(user_pool_config.value.default_action, "ALLOW")
    }
  }

  # Default OIDC auth
  dynamic "openid_connect_config" {
    for_each = var.authentication_type == "OPENID_CONNECT" && var.openid_connect_config != null ? [var.openid_connect_config] : []
    content {
      issuer    = openid_connect_config.value.issuer
      client_id = try(openid_connect_config.value.client_id, null)
      auth_ttl  = try(openid_connect_config.value.auth_ttl, null)
      iat_ttl   = try(openid_connect_config.value.iat_ttl, null)
    }
  }

  # Default Lambda authorizer
  dynamic "lambda_authorizer_config" {
    for_each = var.authentication_type == "AWS_LAMBDA" && var.lambda_authorizer_config != null ? [var.lambda_authorizer_config] : []
    content {
      authorizer_uri                   = lambda_authorizer_config.value.authorizer_uri
      authorizer_result_ttl_in_seconds = try(lambda_authorizer_config.value.authorizer_result_ttl_in_seconds, 300)
      identity_validation_expression   = try(lambda_authorizer_config.value.identity_validation_expression, null)
    }
  }

  # Additional authentication providers
  dynamic "additional_authentication_provider" {
    for_each = var.additional_authentication_providers
    content {
      authentication_type = additional_authentication_provider.value.authentication_type

      dynamic "user_pool_config" {
        for_each = additional_authentication_provider.value.authentication_type == "AMAZON_COGNITO_USER_POOLS" && try(additional_authentication_provider.value.user_pool_config, null) != null ? [additional_authentication_provider.value.user_pool_config] : []
        content {
          user_pool_id        = user_pool_config.value.user_pool_id
          aws_region          = try(user_pool_config.value.aws_region, null)
          app_id_client_regex = try(user_pool_config.value.app_id_client_regex, null)
        }
      }

      dynamic "openid_connect_config" {
        for_each = additional_authentication_provider.value.authentication_type == "OPENID_CONNECT" && try(additional_authentication_provider.value.openid_connect_config, null) != null ? [additional_authentication_provider.value.openid_connect_config] : []
        content {
          issuer    = openid_connect_config.value.issuer
          client_id = try(openid_connect_config.value.client_id, null)
          auth_ttl  = try(openid_connect_config.value.auth_ttl, null)
          iat_ttl   = try(openid_connect_config.value.iat_ttl, null)
        }
      }

      dynamic "lambda_authorizer_config" {
        for_each = additional_authentication_provider.value.authentication_type == "AWS_LAMBDA" && try(additional_authentication_provider.value.lambda_authorizer_config, null) != null ? [additional_authentication_provider.value.lambda_authorizer_config] : []
        content {
          authorizer_uri                   = lambda_authorizer_config.value.authorizer_uri
          authorizer_result_ttl_in_seconds = try(lambda_authorizer_config.value.authorizer_result_ttl_in_seconds, 300)
          identity_validation_expression   = try(lambda_authorizer_config.value.identity_validation_expression, null)
        }
      }
    }
  }

  # Logging
  dynamic "log_config" {
    for_each = var.logging_enabled ? [1] : []
    content {
      cloudwatch_logs_role_arn = local.logging_role_arn
      field_log_level          = var.log_field_log_level
      exclude_verbose_content  = var.log_exclude_verbose_content
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  depends_on = [
    aws_iam_role_policy.logging,
  ]

  lifecycle {
    precondition {
      condition     = var.api_type != "GRAPHQL" || var.schema != null
      error_message = "schema is required when api_type is GRAPHQL."
    }

    precondition {
      condition     = var.authentication_type != "AMAZON_COGNITO_USER_POOLS" || var.user_pool_config != null
      error_message = "user_pool_config is required when authentication_type is AMAZON_COGNITO_USER_POOLS."
    }

    precondition {
      condition     = var.authentication_type != "OPENID_CONNECT" || var.openid_connect_config != null
      error_message = "openid_connect_config is required when authentication_type is OPENID_CONNECT."
    }

    precondition {
      condition     = var.authentication_type != "AWS_LAMBDA" || var.lambda_authorizer_config != null
      error_message = "lambda_authorizer_config is required when authentication_type is AWS_LAMBDA."
    }

    precondition {
      condition     = var.api_type != "MERGED" || var.merged_api_execution_role_arn != null
      error_message = "merged_api_execution_role_arn is required when api_type is MERGED."
    }
  }
}

# =============================================================================
# API Caching
# =============================================================================

resource "aws_appsync_api_cache" "this" {
  count = var.caching_enabled ? 1 : 0

  api_id                     = aws_appsync_graphql_api.this.id
  type                       = var.caching_config.type
  ttl                        = var.caching_config.ttl
  at_rest_encryption_enabled = var.caching_config.at_rest_encryption_enabled
  transit_encryption_enabled = var.caching_config.transit_encryption_enabled
  api_caching_behavior       = "PER_RESOLVER_CACHING"
}

# =============================================================================
# API Keys
# =============================================================================

resource "aws_appsync_api_key" "this" {
  for_each = var.api_keys

  api_id      = aws_appsync_graphql_api.this.id
  description = try(each.value.description, null)
  expires     = try(each.value.expires, null)
}

# =============================================================================
# Data Sources
# =============================================================================

resource "aws_appsync_datasource" "this" {
  for_each = var.datasources

  api_id           = aws_appsync_graphql_api.this.id
  name             = each.key
  type             = each.value.type
  description      = try(each.value.description, null)
  service_role_arn = try(each.value.service_role_arn, null)

  # DynamoDB
  dynamic "dynamodb_config" {
    for_each = each.value.type == "AMAZON_DYNAMODB" && try(each.value.dynamodb_config, null) != null ? [each.value.dynamodb_config] : []
    content {
      table_name             = dynamodb_config.value.table_name
      region                 = try(dynamodb_config.value.region, null)
      use_caller_credentials = try(dynamodb_config.value.use_caller_credentials, false)
      versioned              = try(dynamodb_config.value.versioned, false)

      dynamic "delta_sync_config" {
        for_each = try(dynamodb_config.value.delta_sync_config, null) != null ? [dynamodb_config.value.delta_sync_config] : []
        content {
          base_table_ttl        = try(delta_sync_config.value.base_table_ttl, null)
          delta_sync_table_name = delta_sync_config.value.delta_sync_table_name
          delta_sync_table_ttl  = try(delta_sync_config.value.delta_sync_table_ttl, null)
        }
      }
    }
  }

  # Lambda
  dynamic "lambda_config" {
    for_each = each.value.type == "AWS_LAMBDA" && try(each.value.lambda_config, null) != null ? [each.value.lambda_config] : []
    content {
      function_arn = lambda_config.value.function_arn
    }
  }

  # HTTP
  dynamic "http_config" {
    for_each = each.value.type == "HTTP" && try(each.value.http_config, null) != null ? [each.value.http_config] : []
    content {
      endpoint = http_config.value.endpoint

      dynamic "authorization_config" {
        for_each = try(http_config.value.authorization_config, null) != null ? [http_config.value.authorization_config] : []
        content {
          authorization_type = try(authorization_config.value.authorization_type, "AWS_IAM")

          dynamic "aws_iam_config" {
            for_each = try(authorization_config.value.aws_iam_config, null) != null ? [authorization_config.value.aws_iam_config] : []
            content {
              signing_region       = try(aws_iam_config.value.signing_region, null)
              signing_service_name = try(aws_iam_config.value.signing_service_name, null)
            }
          }
        }
      }
    }
  }

  # Elasticsearch
  dynamic "elasticsearch_config" {
    for_each = each.value.type == "AMAZON_ELASTICSEARCH" && try(each.value.elasticsearch_config, null) != null ? [each.value.elasticsearch_config] : []
    content {
      endpoint = elasticsearch_config.value.endpoint
      region   = try(elasticsearch_config.value.region, null)
    }
  }

  # OpenSearch Service
  dynamic "opensearchservice_config" {
    for_each = each.value.type == "AMAZON_OPENSEARCH_SERVICE" && try(each.value.opensearchservice_config, null) != null ? [each.value.opensearchservice_config] : []
    content {
      endpoint = opensearchservice_config.value.endpoint
      region   = try(opensearchservice_config.value.region, null)
    }
  }

  # Relational Database
  dynamic "relational_database_config" {
    for_each = each.value.type == "RELATIONAL_DATABASE" && try(each.value.relational_database_config, null) != null ? [each.value.relational_database_config] : []
    content {
      source_type = try(relational_database_config.value.source_type, "RDS_HTTP_ENDPOINT")

      dynamic "http_endpoint_config" {
        for_each = try(relational_database_config.value.http_endpoint_config, null) != null ? [relational_database_config.value.http_endpoint_config] : []
        content {
          db_cluster_identifier = http_endpoint_config.value.db_cluster_identifier
          aws_secret_store_arn  = http_endpoint_config.value.aws_secret_store_arn
          database_name         = try(http_endpoint_config.value.database_name, null)
          schema                = try(http_endpoint_config.value.schema, null)
          region                = try(http_endpoint_config.value.region, null)
        }
      }
    }
  }

  # EventBridge
  dynamic "event_bridge_config" {
    for_each = each.value.type == "AMAZON_EVENTBRIDGE" && try(each.value.event_bridge_config, null) != null ? [each.value.event_bridge_config] : []
    content {
      event_bus_arn = event_bridge_config.value.event_bus_arn
    }
  }
}

# =============================================================================
# Functions (for pipeline resolvers)
# =============================================================================

resource "aws_appsync_function" "this" {
  for_each = var.functions

  api_id      = aws_appsync_graphql_api.this.id
  name        = coalesce(try(each.value.name, null), each.key)
  description = try(each.value.description, null)
  data_source = aws_appsync_datasource.this[each.value.data_source].name

  code           = each.value.code
  max_batch_size = try(each.value.max_batch_size, 0)

  runtime {
    name            = try(each.value.runtime_name, "APPSYNC_JS")
    runtime_version = try(each.value.runtime_version, "1.0.0")
  }

  dynamic "sync_config" {
    for_each = try(each.value.sync_config, null) != null ? [each.value.sync_config] : []
    content {
      conflict_detection = try(sync_config.value.conflict_detection, "VERSION")
      conflict_handler   = try(sync_config.value.conflict_handler, "OPTIMISTIC_CONCURRENCY")

      dynamic "lambda_conflict_handler_config" {
        for_each = try(sync_config.value.lambda_conflict_handler_config, null) != null ? [sync_config.value.lambda_conflict_handler_config] : []
        content {
          lambda_conflict_handler_arn = lambda_conflict_handler_config.value.lambda_conflict_handler_arn
        }
      }
    }
  }
}

# =============================================================================
# Resolvers
# =============================================================================

resource "aws_appsync_resolver" "this" {
  for_each = var.resolvers

  api_id = aws_appsync_graphql_api.this.id
  type   = each.value.type
  field  = each.value.field
  kind   = try(each.value.kind, "UNIT")

  data_source    = try(each.value.kind, "UNIT") == "UNIT" ? try(aws_appsync_datasource.this[each.value.data_source].name, each.value.data_source) : null
  code           = each.value.code
  max_batch_size = try(each.value.max_batch_size, 0)

  runtime {
    name            = try(each.value.runtime_name, "APPSYNC_JS")
    runtime_version = try(each.value.runtime_version, "1.0.0")
  }

  dynamic "pipeline_config" {
    for_each = try(each.value.kind, "UNIT") == "PIPELINE" && try(each.value.pipeline_config, null) != null ? [each.value.pipeline_config] : []
    content {
      functions = [for fn_key in pipeline_config.value.functions : local.function_id_map[fn_key]]
    }
  }

  dynamic "caching_config" {
    for_each = try(each.value.caching_config, null) != null ? [each.value.caching_config] : []
    content {
      ttl          = try(caching_config.value.ttl, null)
      caching_keys = try(caching_config.value.caching_keys, [])
    }
  }

  dynamic "sync_config" {
    for_each = try(each.value.sync_config, null) != null ? [each.value.sync_config] : []
    content {
      conflict_detection = try(sync_config.value.conflict_detection, "VERSION")
      conflict_handler   = try(sync_config.value.conflict_handler, "OPTIMISTIC_CONCURRENCY")

      dynamic "lambda_conflict_handler_config" {
        for_each = try(sync_config.value.lambda_conflict_handler_config, null) != null ? [sync_config.value.lambda_conflict_handler_config] : []
        content {
          lambda_conflict_handler_arn = lambda_conflict_handler_config.value.lambda_conflict_handler_arn
        }
      }
    }
  }
}

# =============================================================================
# Custom Domain
# =============================================================================

resource "aws_appsync_domain_name" "this" {
  count = var.domain_name != null ? 1 : 0

  domain_name     = var.domain_name.domain_name
  certificate_arn = var.domain_name.certificate_arn
  description     = try(var.domain_name.description, null)
}

resource "aws_appsync_domain_name_api_association" "this" {
  count = var.domain_name != null ? 1 : 0

  api_id      = aws_appsync_graphql_api.this.id
  domain_name = aws_appsync_domain_name.this[0].domain_name
}

# =============================================================================
# WAF Association
# =============================================================================

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf_web_acl_arn != null ? 1 : 0

  resource_arn = aws_appsync_graphql_api.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}

# =============================================================================
# Source API Associations (Merged API)
# =============================================================================

resource "aws_appsync_source_api_association" "this" {
  for_each = var.source_api_associations

  merged_api_id = aws_appsync_graphql_api.this.id
  source_api_id = each.value.source_api_id
  description   = try(each.value.description, null)

  source_api_association_config {
    merge_type = try(each.value.source_api_association_config_merge_type, "AUTO_MERGE")
  }
}

# =============================================================================
# CloudWatch Metric Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "appsync" {
  for_each = local.enabled_metric_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/AppSync")
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
    { GraphQLAPIId = aws_appsync_graphql_api.this.id }
  )

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.name}-${each.key}")
  })
}

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "appsync_anomaly" {
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
      namespace   = try(each.value.namespace, "AWS/AppSync")
      period      = each.value.period
      stat        = each.value.statistic
      dimensions = merge(
        try(each.value.dimensions, {}),
        { GraphQLAPIId = aws_appsync_graphql_api.this.id }
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
  log_group_name = local.create_log_group ? aws_cloudwatch_log_group.appsync[0].name : "/aws/appsync/apis/${aws_appsync_graphql_api.this.id}"
  pattern        = each.value.pattern

  metric_transformation {
    namespace     = each.value.metric_namespace
    name          = each.value.metric_name
    value         = try(each.value.metric_value, "1")
    default_value = try(each.value.default_value, null)
  }

  lifecycle {
    precondition {
      condition     = var.logging_enabled
      error_message = "logging_enabled must be true when log_metric_filters are configured."
    }
  }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = substr("appsync-${var.name}", 0, 255)

  dashboard_body = jsonencode({
    widgets = concat(
      # Row 1: Requests & Latency
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "GraphQL Requests"
            region = data.aws_region.current.id
            period = 300
            metrics = [
              ["AWS/AppSync", "Latency", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { stat = "SampleCount", label = "Request Count" }]
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
            title  = "Latency (ms)"
            region = data.aws_region.current.id
            period = 300
            metrics = [
              ["AWS/AppSync", "Latency", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { stat = "Average", label = "Average" }],
              ["AWS/AppSync", "Latency", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { stat = "p95", label = "p95" }],
              ["AWS/AppSync", "Latency", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { stat = "Maximum", label = "Max" }]
            ]
          }
        }
      ],
      # Row 2: 4XX & 5XX Errors
      [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "4XX Errors"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/AppSync", "4XXError", "GraphQLAPIId", aws_appsync_graphql_api.this.id]
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
            title  = "5XX Errors"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/AppSync", "5XXError", "GraphQLAPIId", aws_appsync_graphql_api.this.id]
            ]
          }
        }
      ],
      # Row 3: Connect & Disconnect (Subscriptions)
      [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 12
          height = 6
          properties = {
            title  = "WebSocket Connections"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/AppSync", "ConnectSuccess", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Connect Success" }],
              ["AWS/AppSync", "ConnectClientError", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Connect Client Error" }],
              ["AWS/AppSync", "ConnectServerError", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Connect Server Error" }]
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
            title  = "Subscriptions"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/AppSync", "SubscribeSuccess", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Subscribe Success" }],
              ["AWS/AppSync", "SubscribeClientError", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Subscribe Client Error" }],
              ["AWS/AppSync", "SubscribeServerError", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Subscribe Server Error" }]
            ]
          }
        }
      ],
      # Row 4: Publish & Active Connections
      [
        {
          type   = "metric"
          x      = 0
          y      = 18
          width  = 12
          height = 6
          properties = {
            title  = "Publish (Subscription Delivery)"
            region = data.aws_region.current.id
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/AppSync", "PublishDataMessageSuccess", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Publish Success" }],
              ["AWS/AppSync", "PublishDataMessageClientError", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Publish Client Error" }],
              ["AWS/AppSync", "PublishDataMessageServerError", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { label = "Publish Server Error" }]
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
            title  = "Active Connections & Subscriptions"
            region = data.aws_region.current.id
            period = 300
            metrics = [
              ["AWS/AppSync", "ActiveConnection", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { stat = "Maximum", label = "Active Connections" }],
              ["AWS/AppSync", "ActiveSubscription", "GraphQLAPIId", aws_appsync_graphql_api.this.id, { stat = "Maximum", label = "Active Subscriptions" }]
            ]
          }
        }
      ]
    )
  })
}
