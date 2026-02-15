output "method_response_index" {
  value = {
    for k, v in var.method_responses :
    k => {
      method_key  = v.method_key
      status_code = v.status_code
    }
  }
}

output "method_response_ids" {
  value = { for k, v in aws_api_gateway_method_response.this : k => v.id }
}

output "integration_response_ids" {
  value = { for k, v in aws_api_gateway_integration_response.this : k => v.id }
}
