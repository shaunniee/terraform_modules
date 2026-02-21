locals {
  all_parameters = concat(
    var.parameters,
    [
      for p in var.plain_parameters : merge(p, { key_id = null })
    ],
    [
      for p in var.secure_parameters : merge(p, { type = "SecureString", data_type = "text" })
    ]
  )
}

resource "aws_ssm_parameter" "this" {
  for_each    = { for p in local.all_parameters : p.name => p }
  name        = each.value.name
  value       = each.value.value
  description = try(each.value.description, null)
  type        = each.value.type
  key_id      = try(each.value.key_id, null)
  overwrite   = try(each.value.overwrite, false)
  tier        = try(each.value.tier, "Standard")
  data_type   = try(each.value.data_type, "text")

  # Note: allowed_pattern can be used to enforce parameter value format at write time.
  allowed_pattern = try(each.value.allowed_pattern, null)
  tags            = merge(var.tags, try(each.value.tags, {}))

  lifecycle {
    precondition {
      condition     = length(distinct([for p in local.all_parameters : p.name])) == length(local.all_parameters)
      error_message = "Parameter names must be unique across parameters, plain_parameters, and secure_parameters."
    }

    precondition {
      condition = alltrue([
        for p in local.all_parameters :
        trimspace(p.name) != "" &&
        can(regex("^[a-zA-Z0-9_.\\-/]+$", p.name)) &&
        length(p.name) <= 2048
      ])
      error_message = "Each parameter name must be non-empty, <= 2048 chars, and only contain letters, numbers, _, -, ., or /."
    }

    precondition {
      condition = alltrue([
        for p in local.all_parameters :
        try(p.description, null) == null || length(p.description) <= 1024
      ])
      error_message = "Parameter descriptions must be <= 1024 characters."
    }

    precondition {
      condition = alltrue([
        for p in local.all_parameters :
        contains(["Standard", "Advanced", "Intelligent-Tiering"], try(p.tier, "Standard"))
      ])
      error_message = "Parameter tier must be one of: Standard, Advanced, Intelligent-Tiering."
    }

    precondition {
      condition = alltrue([
        for p in local.all_parameters :
        contains(["text", "aws:ec2:image", "aws:ssm:integration"], try(p.data_type, "text"))
      ])
      error_message = "Parameter data_type must be one of: text, aws:ec2:image, aws:ssm:integration."
    }

    precondition {
      condition = alltrue([
        for p in local.all_parameters :
        try(p.type, "String") == "String" || try(p.data_type, "text") == "text"
      ])
      error_message = "data_type can only be customized for String parameters."
    }

    precondition {
      condition = alltrue([
        for p in local.all_parameters :
        try(p.allowed_pattern, null) == null || can(regex(p.allowed_pattern, p.value))
      ])
      error_message = "allowed_pattern must be a valid regex and match the provided parameter value."
    }

  }
}
