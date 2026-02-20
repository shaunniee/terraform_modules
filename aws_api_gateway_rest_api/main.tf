locals {
  create_role = var.execution_role_arn == null
  role_arn    = local.create_role ? aws_iam_role.apigw_execution_role[0].arn : var.execution_role_arn
  role_name   = local.create_role ? aws_iam_role.apigw_execution_role[0].name : null

  resource_ids_with_root = merge({ "__root__" = module.api.root_resource_id }, module.resources.resource_ids)

  redeployment_hash = sha1(jsonencode({
    resources             = var.resources
    authorizers           = var.authorizers
    methods               = var.methods
    integrations          = var.integrations
    method_responses      = var.method_responses
    integration_responses = var.integration_responses
    gateway_responses     = var.gateway_responses
    request_validators    = var.request_validators
    stage_variables       = var.stage_variables
    stage_name            = var.stage_name
  }))

  observability_enabled = try(var.observability.enabled, false)
  dashboard_enabled     = local.observability_enabled && try(var.observability.enable_dashboard, false)

  default_metric_alarms = local.observability_enabled && try(var.observability.enable_default_alarms, true) ? {
    high_5xx_errors = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "5XXError"
      namespace           = "AWS/ApiGateway"
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
    high_4xx_errors = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 3
      metric_name         = "4XXError"
      namespace           = "AWS/ApiGateway"
      period              = 60
      statistic           = "Sum"
      threshold           = 50
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
    high_latency_p95 = {
      enabled             = true
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      metric_name         = "Latency"
      namespace           = "AWS/ApiGateway"
      period              = 60
      extended_statistic  = "p95"
      threshold           = 3000
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
    high_integration_latency = {
      enabled             = true
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      metric_name         = "IntegrationLatency"
      namespace           = "AWS/ApiGateway"
      period              = 60
      statistic           = "Average"
      threshold           = 2000
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions          = {}
      tags                = {}
    }
  } : {}

  effective_metric_alarms = merge(local.default_metric_alarms, var.cloudwatch_metric_alarms)

  enabled_cloudwatch_metric_alarms = {
    for alarm_key, alarm in local.effective_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }

  # Anomaly detection alarms
  default_metric_anomaly_alarms = local.observability_enabled && try(var.observability.enable_anomaly_detection_alarms, false) ? {
    count_anomaly = {
      enabled                  = true
      comparison_operator      = "GreaterThanUpperThreshold"
      evaluation_periods       = 2
      metric_name              = "Count"
      namespace                = "AWS/ApiGateway"
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
    latency_anomaly = {
      enabled                  = true
      comparison_operator      = "GreaterThanUpperThreshold"
      evaluation_periods       = 2
      metric_name              = "Latency"
      namespace                = "AWS/ApiGateway"
      period                   = 300
      statistic                = "Average"
      anomaly_detection_stddev = 2
      treat_missing_data       = "notBreaching"
      alarm_actions            = try(var.observability.default_alarm_actions, [])
      ok_actions               = try(var.observability.default_ok_actions, [])
      insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])
      dimensions               = {}
      tags                     = {}
    }
  } : {}

  effective_metric_anomaly_alarms = merge(local.default_metric_anomaly_alarms, var.cloudwatch_metric_anomaly_alarms)

  enabled_metric_anomaly_alarms = {
    for alarm_key, alarm in local.effective_metric_anomaly_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }
}

resource "aws_iam_role" "apigw_execution_role" {
  count = local.create_role ? 1 : 0

  name                 = "${var.name}-apigw-execution-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-apigw-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  count = local.create_role && var.enable_logging_permissions ? 1 : 0

  role       = aws_iam_role.apigw_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = local.create_role && var.enable_monitoring_permissions ? 1 : 0

  role       = aws_iam_role.apigw_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "xray_tracing" {
  count = local.create_role && var.xray_tracing_enabled && var.enable_tracing_permissions ? 1 : 0

  role       = aws_iam_role.apigw_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.create_role ? toset(var.additional_policy_arns) : toset([])

  role       = aws_iam_role.apigw_execution_role[0].name
  policy_arn = each.value
}

resource "aws_api_gateway_account" "this" {
  count = var.manage_account_cloudwatch_role ? 1 : 0

  cloudwatch_role_arn = local.role_arn

  lifecycle {
    precondition {
      condition     = local.role_arn != null
      error_message = "execution_role_arn must be provided or module role creation must be enabled to manage account CloudWatch role."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy_attachment.monitoring,
    aws_iam_role_policy_attachment.xray_tracing
  ]
}

module "api" {
  source = "./submodules/api"

  name                         = var.name
  description                  = var.description
  binary_media_types           = var.binary_media_types
  minimum_compression_size     = var.minimum_compression_size
  api_key_source               = var.api_key_source
  disable_execute_api_endpoint = var.disable_execute_api_endpoint
  endpoint_configuration_types = var.endpoint_configuration_types
  tags                         = var.tags
}

resource "aws_api_gateway_gateway_response" "this" {
  for_each = var.gateway_responses

  rest_api_id   = module.api.id
  response_type = each.value.response_type
  status_code   = try(each.value.status_code, null)

  response_templates  = length(try(each.value.response_templates, {})) > 0 ? each.value.response_templates : null
  response_parameters = length(try(each.value.response_parameters, {})) > 0 ? each.value.response_parameters : null
}

resource "aws_api_gateway_request_validator" "this" {
  for_each = var.request_validators

  rest_api_id                 = module.api.id
  name                        = each.value.name
  validate_request_body       = try(each.value.validate_request_body, false)
  validate_request_parameters = try(each.value.validate_request_parameters, false)
}

module "resources" {
  source = "./submodules/resources"

  rest_api_id      = module.api.id
  root_resource_id = module.api.root_resource_id
  resources        = var.resources
}

module "authorizers" {
  source = "./submodules/authorizers"

  rest_api_id  = module.api.id
  authorizers  = var.authorizers
}

module "methods" {
  source = "./submodules/methods"

  rest_api_id  = module.api.id
  resource_ids = local.resource_ids_with_root
  methods = {
    for method_key, method in var.methods :
    method_key => merge(method, {
      authorizer_id = contains(["CUSTOM", "COGNITO_USER_POOLS"], upper(try(method.authorization, "NONE"))) ? coalesce(try(module.authorizers.authorizer_ids[try(method.authorizer_key, "")], null), try(method.authorizer_id, null)) : null
    })
  }
}

module "integrations" {
  source = "./submodules/integrations"

  rest_api_id   = module.api.id
  methods_index = module.methods.methods_index
  integrations  = var.integrations
}

module "responses" {
  source = "./submodules/responses"

  rest_api_id           = module.api.id
  methods_index         = module.methods.methods_index
  method_responses      = var.method_responses
  integration_responses = var.integration_responses

  depends_on = [module.integrations]
}

module "stage" {
  source = "./submodules/stage"

  rest_api_id                  = module.api.id
  rest_api_name                = module.api.name
  stage_name                   = var.stage_name
  stage_description            = var.stage_description
  deployment_description       = var.deployment_description
  redeployment_hash            = local.redeployment_hash
  stage_variables              = var.stage_variables
  xray_tracing_enabled         = var.xray_tracing_enabled
  cache_cluster_enabled        = var.cache_cluster_enabled
  cache_cluster_size           = var.cache_cluster_size
  access_log_enabled           = var.access_log_enabled
  create_access_log_group      = var.create_access_log_group
  access_log_group_name        = var.access_log_group_name
  access_log_retention_in_days = var.access_log_retention_in_days
  access_log_kms_key_arn       = var.access_log_kms_key_arn
  access_log_destination_arn   = var.access_log_destination_arn
  access_log_format            = var.access_log_format
  method_settings              = var.method_settings
  tags                         = var.tags

  depends_on = [
    module.responses,
    aws_api_gateway_account.this
  ]
}

resource "aws_cloudwatch_metric_alarm" "apigw" {
  for_each = local.enabled_cloudwatch_metric_alarms

  alarm_name                = coalesce(try(each.value.alarm_name, null), "${module.api.name}-${module.stage.stage_name}-${each.key}")
  alarm_description         = try(each.value.alarm_description, null)
  comparison_operator       = each.value.comparison_operator
  evaluation_periods        = each.value.evaluation_periods
  datapoints_to_alarm       = try(each.value.datapoints_to_alarm, null)
  metric_name               = each.value.metric_name
  namespace                 = try(each.value.namespace, "AWS/ApiGateway")
  period                    = each.value.period
  statistic                 = try(each.value.statistic, null)
  extended_statistic        = try(each.value.extended_statistic, null)
  threshold                 = each.value.threshold
  treat_missing_data        = try(each.value.treat_missing_data, null)
  unit                      = try(each.value.unit, null)
  actions_enabled           = try(each.value.actions_enabled, true)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])
  dimensions = merge({
    ApiName = module.api.name
    Stage   = module.stage.stage_name
  }, try(each.value.dimensions, {}))
  tags = merge(var.tags, try(each.value.tags, {}))
}

module "domain" {
  count  = var.create_domain_name ? 1 : 0
  source = "./submodules/domain"

  rest_api_id           = module.api.id
  stage_name            = module.stage.stage_name
  domain_name           = var.domain_name
  certificate_arn       = var.certificate_arn
  base_path             = var.base_path
  security_policy       = var.security_policy
  endpoint_type         = var.endpoint_configuration_types[0]
  create_route53_record = var.create_route53_record
  hosted_zone_id        = var.hosted_zone_id
  record_name           = var.record_name
  tags                  = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.web_acl_arn != null ? 1 : 0

  resource_arn = module.stage.stage_arn
  web_acl_arn  = var.web_acl_arn
}

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "apigw_anomaly" {
  for_each = local.enabled_metric_anomaly_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${module.api.name}-${module.stage.stage_name}-${each.key}")
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
      namespace   = try(each.value.namespace, "AWS/ApiGateway")
      period      = each.value.period
      stat        = each.value.statistic
      dimensions = merge(
        {
          ApiName = module.api.name
          Stage   = module.stage.stage_name
        },
        try(each.value.dimensions, {})
      )
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${try(each.value.anomaly_detection_stddev, 2)})"
    label       = "${coalesce(try(each.value.alarm_name, null), "${module.api.name}-${module.stage.stage_name}-${each.key}")}-band"
    return_data = true
  }

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${module.api.name}-${module.stage.stage_name}-${each.key}")
  })
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = substr("apigw-${module.api.name}", 0, 255)

  dashboard_body = jsonencode({
    widgets = concat(
      # Row 1: Request count & errors
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title   = "Request Count"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/ApiGateway", "Count", "ApiName", module.api.name, "Stage", module.stage.stage_name]
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
            title   = "Error Rates"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/ApiGateway", "4XXError", "ApiName", module.api.name, "Stage", module.stage.stage_name, { label = "4XX" }],
              ["AWS/ApiGateway", "5XXError", "ApiName", module.api.name, "Stage", module.stage.stage_name, { label = "5XX" }]
            ]
          }
        }
      ],
      # Row 2: Latency
      [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title   = "Latency (ms)"
            region  = data.aws_region.current.name
            period  = 300
            metrics = [
              ["AWS/ApiGateway", "Latency", "ApiName", module.api.name, "Stage", module.stage.stage_name, { stat = "Average", label = "Average" }],
              ["AWS/ApiGateway", "Latency", "ApiName", module.api.name, "Stage", module.stage.stage_name, { stat = "p95", label = "p95" }],
              ["AWS/ApiGateway", "Latency", "ApiName", module.api.name, "Stage", module.stage.stage_name, { stat = "p99", label = "p99" }]
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
            title   = "Integration Latency (ms)"
            region  = data.aws_region.current.name
            period  = 300
            metrics = [
              ["AWS/ApiGateway", "IntegrationLatency", "ApiName", module.api.name, "Stage", module.stage.stage_name, { stat = "Average", label = "Average" }],
              ["AWS/ApiGateway", "IntegrationLatency", "ApiName", module.api.name, "Stage", module.stage.stage_name, { stat = "p95", label = "p95" }],
              ["AWS/ApiGateway", "IntegrationLatency", "ApiName", module.api.name, "Stage", module.stage.stage_name, { stat = "p99", label = "p99" }]
            ]
          }
        }
      ],
      # Row 3: Cache hits/misses
      [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 12
          height = 6
          properties = {
            title   = "Cache Hit / Miss"
            region  = data.aws_region.current.name
            stat    = "Sum"
            period  = 300
            metrics = [
              ["AWS/ApiGateway", "CacheHitCount", "ApiName", module.api.name, "Stage", module.stage.stage_name, { label = "Hits" }],
              ["AWS/ApiGateway", "CacheMissCount", "ApiName", module.api.name, "Stage", module.stage.stage_name, { label = "Misses" }]
            ]
          }
        }
      ]
    )
  })
}

data "aws_region" "current" {}
