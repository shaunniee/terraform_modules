locals {
  use_file_source = var.filename != null
  use_s3_source   = var.s3_bucket != null || var.s3_key != null

  resolved_source_code_hash = var.source_code_hash != null ? var.source_code_hash : (
    var.filename != null ? filebase64sha256(var.filename) : null
  )
}

resource "aws_lambda_layer_version" "this" {
  layer_name               = var.layer_name
  description              = var.description
  license_info             = var.license_info
  compatible_runtimes      = var.compatible_runtimes
  compatible_architectures = var.compatible_architectures

  filename          = var.filename
  source_code_hash  = local.resolved_source_code_hash
  s3_bucket         = var.s3_bucket
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version

  lifecycle {
    precondition {
      condition     = local.use_file_source != local.use_s3_source
      error_message = "Set exactly one source type: filename OR s3_bucket+s3_key."
    }

    precondition {
      condition     = var.filename == null || can(filebase64sha256(var.filename))
      error_message = "filename must point to an existing readable file."
    }

    precondition {
      condition     = var.filename == null || can(regex("\\.zip$", var.filename))
      error_message = "filename must point to a .zip file."
    }

    precondition {
      condition     = !local.use_s3_source || (var.s3_bucket != null && var.s3_key != null)
      error_message = "When using S3 source, both s3_bucket and s3_key are required."
    }
  }
}

resource "aws_lambda_layer_version_permission" "this" {
  for_each = {
    for p in var.permissions : p.statement_id => p
  }

  layer_name      = aws_lambda_layer_version.this.layer_name
  version_number  = aws_lambda_layer_version.this.version
  statement_id    = each.value.statement_id
  action          = each.value.action
  principal       = each.value.principal
  organization_id = try(each.value.organization_id, null)
  skip_destroy    = try(each.value.skip_destroy, false)
}
