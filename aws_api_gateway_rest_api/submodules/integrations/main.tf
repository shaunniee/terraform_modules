resource "aws_api_gateway_integration" "this" {
  for_each = var.integrations

  rest_api_id             = var.rest_api_id
  resource_id             = var.methods_index[each.value.method_key].resource_id
  http_method             = var.methods_index[each.value.method_key].http_method
  type                    = each.value.type
  integration_http_method = try(each.value.integration_http_method, null)
  uri                     = try(each.value.uri, null)
  connection_type         = try(each.value.connection_type, null)
  connection_id           = try(each.value.connection_id, null)
  passthrough_behavior    = try(each.value.passthrough_behavior, null)
  request_templates       = try(each.value.request_templates, null)
  request_parameters      = try(each.value.request_parameters, null)
  content_handling        = try(each.value.content_handling, null)
  timeout_milliseconds    = try(each.value.timeout_milliseconds, null)
  cache_key_parameters    = try(each.value.cache_key_parameters, null)
  cache_namespace         = try(each.value.cache_namespace, null)
}
