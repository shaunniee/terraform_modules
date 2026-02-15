resource "aws_api_gateway_resource" "this" {
  for_each = var.resources

  rest_api_id = var.rest_api_id
  parent_id   = each.value.parent_key == null ? var.root_resource_id : aws_api_gateway_resource.this[each.value.parent_key].id
  path_part   = each.value.path_part
}
