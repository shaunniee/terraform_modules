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