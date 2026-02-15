output "methods_index" {
  value = {
    for k, v in aws_api_gateway_method.this :
    k => {
      resource_id = v.resource_id
      http_method = v.http_method
      id          = v.id
    }
  }
}
