locals {
  attribute_names = [for a in var.attributes : a.name]
  used_attribute_names = distinct(compact(concat(
    [var.hash_key],
    var.range_key == null ? [] : [var.range_key],
    [for g in var.global_secondary_indexes : g.hash_key],
    [for g in var.global_secondary_indexes : try(g.range_key, null)],
    [for l in var.local_secondary_indexes : l.range_key]
  )))
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.value.name
      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }
      key_schema {
        attribute_name = try(global_secondary_index.value.range_key, null)
        key_type       = "RANGE"
      }

      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null
      read_capacity      = var.billing_mode == "PROVISIONED" ? try(global_secondary_index.value.read_capacity, null) : null
      write_capacity     = var.billing_mode == "PROVISIONED" ? try(global_secondary_index.value.write_capacity, null) : null
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes
    content {
      name               = local_secondary_index.value.name
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.projection_type == "INCLUDE" ? local_secondary_index.value.non_key_attributes : null
    }
  }

  dynamic "ttl" {
    for_each = var.ttl.enabled ? [1] : []
    content {
      enabled        = true
      attribute_name = var.ttl.attribute_name
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = var.server_side_encryption.enabled
    kms_key_arn = var.server_side_encryption.kms_key_arn
  }

  stream_enabled   = var.stream_enabled
  stream_view_type = var.stream_enabled ? var.stream_view_type : null

  deletion_protection_enabled = var.deletion_protection_enabled
  table_class                 = var.table_class
  tags                        = var.tags

  lifecycle {
    precondition {
      condition     = contains(local.attribute_names, var.hash_key)
      error_message = "hash_key must be defined in attributes."
    }

    precondition {
      condition     = var.range_key == null || contains(local.attribute_names, var.range_key)
      error_message = "range_key must be null or defined in attributes."
    }

    precondition {
      condition = alltrue([
        for g in var.global_secondary_indexes :
        contains(local.attribute_names, g.hash_key) && (try(g.range_key, null) == null || contains(local.attribute_names, g.range_key))
      ])
      error_message = "All global_secondary_indexes hash_key/range_key values must be defined in attributes."
    }

    precondition {
      condition = alltrue([
        for l in var.local_secondary_indexes : contains(local.attribute_names, l.range_key)
      ])
      error_message = "All local_secondary_indexes range_key values must be defined in attributes."
    }

    precondition {
      condition     = var.range_key != null || length(var.local_secondary_indexes) == 0
      error_message = "local_secondary_indexes require table range_key to be set."
    }

    precondition {
      condition     = length(setsubtract(local.attribute_names, local.used_attribute_names)) == 0
      error_message = "attributes must only include key attributes used by table, GSIs, or LSIs."
    }

    precondition {
      condition     = var.billing_mode == "PROVISIONED" ? (var.read_capacity != null && var.write_capacity != null) : (var.read_capacity == null && var.write_capacity == null)
      error_message = "For PROVISIONED billing_mode, read_capacity and write_capacity are required; for PAY_PER_REQUEST they must be null."
    }

    precondition {
      condition = var.billing_mode == "PROVISIONED" ? alltrue([
        for g in var.global_secondary_indexes :
        try(g.read_capacity, null) != null && try(g.write_capacity, null) != null
        ]) : alltrue([
        for g in var.global_secondary_indexes :
        try(g.read_capacity, null) == null && try(g.write_capacity, null) == null
      ])
      error_message = "GSI capacities must be set in PROVISIONED mode and omitted in PAY_PER_REQUEST mode."
    }

    precondition {
      condition     = !var.stream_enabled || var.stream_view_type != null
      error_message = "stream_view_type is required when stream_enabled = true."
    }

    precondition {
      condition     = var.stream_enabled || var.stream_view_type == null
      error_message = "stream_view_type must be null when stream_enabled = false."
    }

    precondition {
      condition     = !var.ttl.enabled || (try(var.ttl.attribute_name, null) != null && trim(var.ttl.attribute_name) != "")
      error_message = "ttl.attribute_name is required when ttl.enabled = true."
    }
  }
}
