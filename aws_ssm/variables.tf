variable "tags" {
  description = "Common tags applied to all SSM parameters."
  type        = map(string)
  default     = {}
}

variable "parameters" {
  description = "DEPRECATED generic list of SSM parameters. Prefer plain_parameters and secure_parameters."
  type = list(object({
    name            = string
    value           = string
    description     = optional(string, null)
    type            = optional(string, "String") # String | StringList | SecureString
    key_id          = optional(string, null)     # KMS key for SecureString
    overwrite       = optional(bool, false)
    tier            = optional(string, "Standard") # Standard | Advanced | Intelligent-Tiering
    data_type       = optional(string, "text")     # text | aws:ec2:image | aws:ssm:integration
    allowed_pattern = optional(string, null)
    policies        = optional(string, null) # JSON policy string
    tags            = optional(map(string), {})
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.parameters :
      contains(["String", "StringList", "SecureString"], p.type)
    ])
    error_message = "parameters[*].type must be one of: String, StringList, SecureString."
  }

  validation {
    condition = alltrue([
      for p in var.parameters :
      contains(["Standard", "Advanced", "Intelligent-Tiering"], p.tier)
    ])
    error_message = "parameters[*].tier must be one of: Standard, Advanced, Intelligent-Tiering."
  }

  validation {
    condition = alltrue([
      for p in var.parameters :
      p.type == "SecureString" || p.key_id == null
    ])
    error_message = "parameters[*].key_id can only be set when type is SecureString."
  }

  validation {
    condition = alltrue([
      for p in var.parameters :
      p.type == "String" || (try(p.data_type, "text") == "text")
    ])
    error_message = "parameters[*].data_type can only be set for type String."
  }
}

variable "plain_parameters" {
  description = "Preferred list for non-secure parameters (String/StringList)."
  type = list(object({
    name            = string
    value           = string
    description     = optional(string, null)
    type            = optional(string, "String") # String | StringList
    overwrite       = optional(bool, false)
    tier            = optional(string, "Standard")
    data_type       = optional(string, "text")
    allowed_pattern = optional(string, null)
    policies        = optional(string, null)
    tags            = optional(map(string), {})
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.plain_parameters :
      contains(["String", "StringList"], p.type)
    ])
    error_message = "plain_parameters[*].type must be String or StringList."
  }
}

variable "secure_parameters" {
  description = "Preferred list for secure parameters (SecureString)."
  type = list(object({
    name            = string
    value           = string
    description     = optional(string, null)
    key_id          = optional(string, null)
    overwrite       = optional(bool, false)
    tier            = optional(string, "Standard")
    allowed_pattern = optional(string, null)
    policies        = optional(string, null)
    tags            = optional(map(string), {})
  }))
  default = []
}
