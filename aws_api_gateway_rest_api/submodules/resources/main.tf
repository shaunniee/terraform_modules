resource "aws_api_gateway_resource" "this" {
  for_each = var.resources

  rest_api_id = var.rest_api_id
   parent_id = try(
    aws_api_gateway_resource.this[each.value.parent_key].id,
    var.root_resource_id
  )
  path_part   = each.value.path_part
}
