resource "aws_api_gateway_method" "this" {
  for_each = var.methods

  rest_api_id          = var.rest_api_id
  resource_id          = var.resource_ids[coalesce(try(each.value.resource_key, null), "__root__")]
  http_method          = upper(each.value.http_method)
  authorization        = upper(try(each.value.authorization, "NONE"))
  authorizer_id        = contains(["CUSTOM", "COGNITO_USER_POOLS"], upper(try(each.value.authorization, "NONE"))) ? try(each.value.authorizer_id, null) : null
  api_key_required     = try(each.value.api_key_required, false)
  request_models       = try(each.value.request_models, null)
  request_parameters   = try(each.value.request_parameters, null)
  request_validator_id = try(each.value.request_validator_id, null)
  operation_name       = try(each.value.operation_name, null)
}
