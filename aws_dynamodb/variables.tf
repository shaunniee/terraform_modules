variable "table_name" {
  description = "DynamoDB table name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.table_name))
    error_message = "table_name must be 3-255 chars and only include letters, numbers, underscore, hyphen, or dot."
  }
}

variable "hash_key" {
  description = "Partition key attribute name."
  type        = string

  validation {
    condition     = trim(var.hash_key) != ""
    error_message = "hash_key must be non-empty."
  }
}

variable "range_key" {
  description = "Sort key attribute name (optional)."
  type        = string
  default     = null
}

variable "billing_mode" {
  description = "DynamoDB billing mode."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Read capacity units for PROVISIONED mode."
  type        = number
  default     = null

  validation {
    condition     = var.read_capacity == null || var.read_capacity >= 1
    error_message = "read_capacity must be null or >= 1."
  }
}

variable "write_capacity" {
  description = "Write capacity units for PROVISIONED mode."
  type        = number
  default     = null

  validation {
    condition     = var.write_capacity == null || var.write_capacity >= 1
    error_message = "write_capacity must be null or >= 1."
  }
}

variable "attributes" {
  description = "Attribute definitions used by table/index key schemas."
  type = list(object({
    name = string
    type = string # S | N | B
  }))

  validation {
    condition     = length(var.attributes) > 0
    error_message = "attributes must contain at least one attribute definition."
  }

  validation {
    condition     = length(distinct([for a in var.attributes : a.name])) == length(var.attributes)
    error_message = "attributes names must be unique."
  }

  validation {
    condition = alltrue([
      for a in var.attributes : contains(["S", "N", "B"], a.type)
    ])
    error_message = "attributes[*].type must be one of: S, N, B."
  }
}

variable "global_secondary_indexes" {
  description = "Global secondary indexes."
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string), [])
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default = []

  validation {
    condition     = length(distinct([for g in var.global_secondary_indexes : g.name])) == length(var.global_secondary_indexes)
    error_message = "global_secondary_indexes names must be unique."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], g.projection_type)
    ])
    error_message = "global_secondary_indexes[*].projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes :
      g.projection_type == "INCLUDE" ? length(g.non_key_attributes) > 0 : true
    ])
    error_message = "global_secondary_indexes[*].non_key_attributes must be non-empty when projection_type is INCLUDE."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes :
      try(g.read_capacity, null) == null || g.read_capacity >= 1
    ])
    error_message = "global_secondary_indexes[*].read_capacity must be null or >= 1."
  }

  validation {
    condition = alltrue([
      for g in var.global_secondary_indexes :
      try(g.write_capacity, null) == null || g.write_capacity >= 1
    ])
    error_message = "global_secondary_indexes[*].write_capacity must be null or >= 1."
  }
}

variable "local_secondary_indexes" {
  description = "Local secondary indexes."
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for l in var.local_secondary_indexes : l.name])) == length(var.local_secondary_indexes)
    error_message = "local_secondary_indexes names must be unique."
  }

  validation {
    condition = alltrue([
      for l in var.local_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], l.projection_type)
    ])
    error_message = "local_secondary_indexes[*].projection_type must be ALL, KEYS_ONLY, or INCLUDE."
  }

  validation {
    condition = alltrue([
      for l in var.local_secondary_indexes :
      l.projection_type == "INCLUDE" ? length(l.non_key_attributes) > 0 : true
    ])
    error_message = "local_secondary_indexes[*].non_key_attributes must be non-empty when projection_type is INCLUDE."
  }
}

variable "ttl" {
  description = "TTL configuration for the table."
  type = object({
    enabled        = bool
    attribute_name = optional(string)
  })
  default = {
    enabled        = false
    attribute_name = null
  }
}

variable "stream_enabled" {
  description = "Whether DynamoDB streams are enabled."
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "When stream_enabled=true, one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  type        = string
  default     = null

  validation {
    condition     = var.stream_view_type == null || contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be null or one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Enable point-in-time recovery."
  type        = bool
  default     = true
}

variable "server_side_encryption" {
  description = "Server-side encryption configuration."
  type = object({
    enabled     = bool
    kms_key_arn = optional(string)
  })
  default = {
    enabled     = true
    kms_key_arn = null
  }

  validation {
    condition     = var.server_side_encryption.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.server_side_encryption.kms_key_arn))
    error_message = "server_side_encryption.kms_key_arn must be a valid KMS key ARN when provided."
  }
}

variable "deletion_protection_enabled" {
  description = "Enable deletion protection for the table."
  type        = bool
  default     = false
}

variable "table_class" {
  description = "DynamoDB table class."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "tags" {
  description = "Tags to apply to the table."
  type        = map(string)
  default     = {}
}
