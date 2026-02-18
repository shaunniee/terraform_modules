output "authorizer_ids" {
  value = {
    for k, v in aws_api_gateway_authorizer.this :
    k => v.id
  }
}
