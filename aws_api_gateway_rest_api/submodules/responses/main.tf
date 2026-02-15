resource "aws_api_gateway_method_response" "this" {
  for_each = var.method_responses

  rest_api_id         = var.rest_api_id
  resource_id         = var.methods_index[each.value.method_key].resource_id
  http_method         = var.methods_index[each.value.method_key].http_method
  status_code         = each.value.status_code
  response_models     = try(each.value.response_models, null)
  response_parameters = try(each.value.response_parameters, null)
}

resource "aws_api_gateway_integration_response" "this" {
  for_each = var.integration_responses

  rest_api_id         = var.rest_api_id
  resource_id         = var.methods_index[var.method_responses[each.value.method_response_key].method_key].resource_id
  http_method         = var.methods_index[var.method_responses[each.value.method_response_key].method_key].http_method
  status_code         = coalesce(try(each.value.status_code, null), var.method_responses[each.value.method_response_key].status_code)
  selection_pattern   = try(each.value.selection_pattern, null)
  response_templates  = try(each.value.response_templates, null)
  response_parameters = try(each.value.response_parameters, null)
  content_handling    = try(each.value.content_handling, null)

  depends_on = [aws_api_gateway_method_response.this]
}
