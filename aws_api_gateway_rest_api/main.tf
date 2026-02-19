locals {
  resource_ids_with_root = merge({ "__root__" = module.api.root_resource_id }, module.resources.resource_ids)

  redeployment_hash = sha1(jsonencode({
    resources             = var.resources
    authorizers           = var.authorizers
    methods               = var.methods
    integrations          = var.integrations
    method_responses      = var.method_responses
    integration_responses = var.integration_responses
    stage_variables       = var.stage_variables
    stage_name            = var.stage_name
  }))

  enabled_cloudwatch_metric_alarms = {
    for alarm_key, alarm in var.cloudwatch_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }
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

  depends_on = [module.responses]
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
  statistic                 = each.value.statistic
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
  create_route53_record = var.create_route53_record
  hosted_zone_id        = var.hosted_zone_id
  record_name           = var.record_name
  tags                  = var.tags
}
