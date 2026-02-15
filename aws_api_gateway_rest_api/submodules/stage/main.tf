resource "aws_cloudwatch_log_group" "apigw_access" {
  count = var.create_access_log_group ? 1 : 0

  name              = coalesce(var.access_log_group_name, "/aws/apigateway/${var.rest_api_name}/${var.stage_name}")
  retention_in_days = var.access_log_retention_in_days
  kms_key_id        = var.access_log_kms_key_arn
  tags              = var.tags
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = var.rest_api_id
  description = var.deployment_description

  triggers = {
    redeployment = var.redeployment_hash
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id           = var.rest_api_id
  stage_name            = var.stage_name
  description           = var.stage_description
  deployment_id         = aws_api_gateway_deployment.this.id
  variables             = var.stage_variables
  xray_tracing_enabled  = var.xray_tracing_enabled
  cache_cluster_enabled = var.cache_cluster_enabled
  cache_cluster_size    = var.cache_cluster_size
  tags                  = var.tags

  dynamic "access_log_settings" {
    for_each = var.access_log_enabled ? [1] : []
    content {
      destination_arn = var.create_access_log_group ? aws_cloudwatch_log_group.apigw_access[0].arn : var.access_log_destination_arn
      format          = var.access_log_format
    }
  }
}

resource "aws_api_gateway_method_settings" "all" {
  count = var.method_settings == null ? 0 : 1

  rest_api_id = var.rest_api_id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled                            = try(var.method_settings.metrics_enabled, null)
    logging_level                              = try(var.method_settings.logging_level, null)
    data_trace_enabled                         = try(var.method_settings.data_trace_enabled, null)
    throttling_burst_limit                     = try(var.method_settings.throttling_burst_limit, null)
    throttling_rate_limit                      = try(var.method_settings.throttling_rate_limit, null)
    caching_enabled                            = try(var.method_settings.caching_enabled, null)
    cache_ttl_in_seconds                       = try(var.method_settings.cache_ttl_in_seconds, null)
    cache_data_encrypted                       = try(var.method_settings.cache_data_encrypted, null)
    require_authorization_for_cache_control    = try(var.method_settings.require_authorization_for_cache_control, null)
    unauthorized_cache_control_header_strategy = try(var.method_settings.unauthorized_cache_control_header_strategy, null)
  }
}
