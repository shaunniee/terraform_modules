locals {
  level_1 = { for k, v in var.resources : k => v if try(v.parent_key, null) == null }

  level_2 = { for k, v in var.resources : k => v
    if try(v.parent_key, null) != null &&
    contains(keys(local.level_1), v.parent_key) }

  level_3 = { for k, v in var.resources : k => v
    if try(v.parent_key, null) != null &&
    contains(keys(local.level_2), v.parent_key) }

  level_4 = { for k, v in var.resources : k => v
    if try(v.parent_key, null) != null &&
    contains(keys(local.level_3), v.parent_key) }

  level_5 = { for k, v in var.resources : k => v
    if try(v.parent_key, null) != null &&
    contains(keys(local.level_4), v.parent_key) }

  all_placed_count = length(local.level_1) + length(local.level_2) + length(local.level_3) + length(local.level_4) + length(local.level_5)
}

resource "aws_api_gateway_resource" "level_1" {
  for_each    = local.level_1
  rest_api_id = var.rest_api_id
  parent_id   = var.root_resource_id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level_2" {
  for_each    = local.level_2
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.level_1[each.value.parent_key].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level_3" {
  for_each    = local.level_3
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.level_2[each.value.parent_key].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level_4" {
  for_each    = local.level_4
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.level_3[each.value.parent_key].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level_5" {
  for_each    = local.level_5
  rest_api_id = var.rest_api_id
  parent_id   = aws_api_gateway_resource.level_4[each.value.parent_key].id
  path_part   = each.value.path_part
}

resource "terraform_data" "depth_check" {
  count = local.all_placed_count < length(var.resources) ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.all_placed_count >= length(var.resources)
      error_message = "Resource nesting exceeds maximum depth of 5 levels. Some resources could not be placed. Flatten your path hierarchy or split into separate APIs."
    }
  }
}