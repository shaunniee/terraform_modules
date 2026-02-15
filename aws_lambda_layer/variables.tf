variable "layer_name" {
  description = "Lambda layer name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,140}$", var.layer_name))
    error_message = "layer_name must be 1-140 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "description" {
  description = "Layer description."
  type        = string
  default     = null
}

variable "license_info" {
  description = "Layer license info string."
  type        = string
  default     = null
}

variable "compatible_runtimes" {
  description = "Compatible Lambda runtimes for this layer."
  type        = list(string)
  default     = []
}

variable "compatible_architectures" {
  description = "Compatible architectures for this layer."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for a in var.compatible_architectures : contains(["x86_64", "arm64"], a)
    ])
    error_message = "compatible_architectures may only contain x86_64 or arm64."
  }
}

variable "filename" {
  description = "Local path to layer zip file. Mutually exclusive with s3_bucket/s3_key."
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Optional source code hash. If null and filename is set, computed automatically."
  type        = string
  default     = null
}

variable "s3_bucket" {
  description = "S3 bucket containing layer zip. Use with s3_key. Mutually exclusive with filename."
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 key for layer zip. Use with s3_bucket."
  type        = string
  default     = null
}

variable "s3_object_version" {
  description = "Optional S3 object version for layer zip."
  type        = string
  default     = null
}

variable "permissions" {
  description = "Optional layer version permissions."
  type = list(object({
    statement_id    = string
    action          = optional(string, "lambda:GetLayerVersion")
    principal       = string
    organization_id = optional(string)
    skip_destroy    = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.permissions :
      trimspace(p.statement_id) != "" && trimspace(p.principal) != ""
    ])
    error_message = "permissions[*].statement_id and permissions[*].principal must be non-empty."
  }

  validation {
    condition = alltrue([
      for p in var.permissions :
      contains(["lambda:GetLayerVersion"], p.action)
    ])
    error_message = "permissions[*].action must be lambda:GetLayerVersion."
  }

  validation {
    condition = alltrue([
      for p in var.permissions :
      try(p.organization_id, null) == null || can(regex("^o-[a-z0-9]{10,32}$", p.organization_id))
    ])
    error_message = "permissions[*].organization_id must be a valid AWS Organizations ID when provided."
  }
}
