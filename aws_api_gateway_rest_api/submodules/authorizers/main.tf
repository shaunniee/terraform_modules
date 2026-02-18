resource "aws_api_gateway_authorizer" "this" {
  for_each = var.authorizers

  rest_api_id = var.rest_api_id
  name        = each.value.name
  type        = upper(each.value.type)

  authorizer_uri                    = contains(["TOKEN", "REQUEST"], upper(each.value.type)) ? try(each.value.authorizer_uri, null) : null
  authorizer_credentials            = try(each.value.authorizer_credentials, null)
  identity_source                   = contains(["TOKEN", "REQUEST"], upper(each.value.type)) ? coalesce(try(each.value.identity_source, null), "method.request.header.Authorization") : null
  identity_validation_expression    = upper(each.value.type) == "TOKEN" ? try(each.value.identity_validation_expression, null) : null
  provider_arns                     = upper(each.value.type) == "COGNITO_USER_POOLS" ? try(each.value.provider_arns, []) : []
  authorizer_result_ttl_in_seconds  = try(each.value.authorizer_result_ttl_in_seconds, null)
}
