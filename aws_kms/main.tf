resource "aws_kms_key" "this" {
  for_each = { for k, v in var.keys : k => v }

  description             = each.value.description
  deletion_window_in_days = lookup(each.value, "deletion_window_in_days", 30)
  enable_key_rotation     = lookup(each.value, "enable_key_rotation", true)
  policy                  = lookup(each.value, "policy", null)
  tags                    = lookup(each.value, "tags", {})
}

resource "aws_kms_alias" "this" {
  for_each = { for k, v in var.keys : k => v }

  name          = "alias/${each.value.alias}"
  target_key_id = aws_kms_key.this[each.key].id
}