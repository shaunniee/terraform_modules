variable "bucket_name" {
    description = "The name of the S3 bucket to create."
    type        = string

    validation {
      condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
      error_message = "Bucket name must be between 3-63 characters, contain only lowercase letters, numbers, hyphens, and periods, and must start and end with a letter or number."
    }

    validation {
      condition     = !can(regex("\\.\\.", var.bucket_name))
      error_message = "Bucket name cannot contain consecutive periods (..)."
    }

    validation {
      condition     = !can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.bucket_name))
      error_message = "Bucket name cannot be formatted as an IP address (e.g., 192.168.1.1)."
    }
}

variable "force_destroy" {
    description = "Whether to force destroy the S3 bucket."
    type        = bool
    default = false
}

variable "private_bucket" {
    description = "Whether to create a private S3 bucket."
    type        = bool
    default = true
}

variable "prevent_destroy" {
    description = "Whether to prevent destroy the S3 bucket."
    type        = bool
    default = true
}

variable "server_side_encryption" {
    description = "Define server side encryption"
    type =object({
      enabled = bool
      encryption_algorithm = string
      kms_master_key_id = optional(string)
    })
    default = {
      enabled = true
      encryption_algorithm = "AES256"
      kms_master_key_id = null
    }

    validation {
      condition     = contains(["AES256", "aws:kms"], var.server_side_encryption.encryption_algorithm)
      error_message = "encryption_algorithm must be either 'AES256' or 'aws:kms'."
    }

    validation {
      condition     = !var.server_side_encryption.enabled || (var.server_side_encryption.encryption_algorithm != "aws:kms" || var.server_side_encryption.kms_master_key_id != null)
      error_message = "kms_master_key_id is required when encryption_algorithm is 'aws:kms'."
    }
}


variable "lifecycle_rules" {
  description = "S3 bucket lifecycle rules. Leave empty to skip creating lifecycle configuration."
  type = list(object({
    id      = string
    enabled = optional(bool, true)
    filter = optional(object({
      prefix = optional(string)
      tag = optional(object({
        key   = string
        value = string
      }))
    }))
    transition = optional(list(object({
      days          = number
      storage_class = string
    })), [])
        noncurrent_version_transition = optional(list(object({
        noncurrent_days = number
        storage_class = string
        })), [])

        noncurrent_version_expiration = optional(list(object({
          noncurrent_days = number
        })), [])
    expiration = optional(object({
      days                         = optional(number)
      expired_object_delete_marker = optional(bool)
    }), null)
  }))
  default = []

  validation {
    condition = alltrue(flatten([
      for rule in var.lifecycle_rules : [
        for transition in rule.transition : contains(
          ["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR"],
          transition.storage_class
        )
      ]
    ]))
    error_message = "transition storage_class must be one of: STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER, GLACIER_IR, or DEEP_ARCHIVE."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.lifecycle_rules : [
        for transition in rule.noncurrent_version_transition : contains(
          ["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR"],
          transition.storage_class
        )
      ]
    ]))
    error_message = "noncurrent_version_transition storage_class must be one of: STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER, GLACIER_IR, or DEEP_ARCHIVE."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules : alltrue([
        for transition in rule.transition : transition.days >= 0
      ])
    ])
    error_message = "transition days must be a non-negative number."
  }
}


variable "cors_rules" {
  description = "Optional CORS rules for the bucket. Leave empty to disable CORS configuration."
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules : alltrue([
        for method in rule.allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], method)
      ])
    ])
    error_message = "allowed_methods must only contain valid HTTP methods: GET, PUT, POST, DELETE, or HEAD."
  }

  validation {
    condition = alltrue([
      for rule in var.cors_rules : rule.max_age_seconds >= 0 && rule.max_age_seconds <= 86400
    ])
    error_message = "max_age_seconds must be between 0 and 86400 (24 hours)."
  }
}

variable "logging" {
    description = "Logging configuration for the S3 bucket. Leave empty to disable logging."
    type = object({
        enabled = bool
        managed_bucket = bool
        target_bucket = optional(string, "")
        target_prefix = optional(string, "")
    })
    default = {
        enabled = false
        managed_bucket = true
        target_bucket = ""
        target_prefix = ""
     }

     validation {
       condition = !(var.logging.enabled && !var.logging.managed_bucket && var.logging.target_bucket == "")
       error_message = "If logging is enabled and not using a managed bucket, target_bucket must be provided."
     }
  
}

variable "replication" {
  description = "Replication configuration for the S3 bucket. Set to null to disable replication. If role_arn is not provided, a role will be created."
  type = object({
    role_arn = optional(string, "")
    rules = list(object({
      id     = string
      prefix = optional(string, "")
      status = string
      destination_bucket_arn = string
      storage_class = string
    }))
  })
  default = null

  validation {
    condition = var.replication == null || alltrue([
      for rule in var.replication.rules : rule.destination_bucket_arn != ""
    ])
    error_message = "All replication rules must have a valid destination_bucket_arn. Empty values are not allowed."
  }

  validation {
    condition = var.replication == null || alltrue([
      for rule in var.replication.rules : contains(["Enabled", "Disabled"], rule.status)
    ])
    error_message = "Replication rule status must be either 'Enabled' or 'Disabled'."
  }

  validation {
    condition = var.replication == null || alltrue([
      for rule in var.replication.rules : contains(
        ["STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR"],
        rule.storage_class
      )
    ])
    error_message = "Replication storage_class must be one of: STANDARD, REDUCED_REDUNDANCY, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER, GLACIER_IR, or DEEP_ARCHIVE."
  }

  validation {
    condition = var.replication == null || alltrue([
      for rule in var.replication.rules : can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", rule.destination_bucket_arn))
    ])
    error_message = "destination_bucket_arn must be a valid S3 bucket ARN in the format: arn:aws:s3:::bucket-name"
  }
}