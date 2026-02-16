resource "aws_api_gateway_resource" "this" {
  for_each = var.resources

  rest_api_id = var.rest_api_id
  parent_id   = local.resource_ids_with_root[each.value.parent_key]
  path_part   = each.value.path_part
}


locals {
  resource_ids_with_root = merge(
    { "__root__" = var.root_resource_id },
    aws_api_gateway_resource.this != null
    ? { for k, r in aws_api_gateway_resource.this : k => r.id }
    : {}
  )
}
