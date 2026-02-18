variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "function_name" {
  description = "The name of the Lambda function"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "execution_role_arn" {
  description = "Existing IAM role ARN for Lambda execution. If null, module creates and manages a role."
  type        = string
  default     = null

  validation {
    condition     = var.execution_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role\\/.+$", var.execution_role_arn))
    error_message = "execution_role_arn must be a valid IAM role ARN."
  }
}

variable "handler" {
  description = "The handler for the Lambda function"
  type        = string

  validation {
    condition     = trimspace(var.handler) != ""
    error_message = "handler must be non-empty."
  }
}

variable "runtime" {
  description = "The runtime for the Lambda function"
  type        = string

  validation {
    condition     = trimspace(var.runtime) != ""
    error_message = "runtime must be non-empty."
  }
}

variable "filename" {
  description = "Local path to Lambda deployment package zip. Mutually exclusive with s3_bucket/s3_key."
  type        = string
  default     = null

  validation {
    condition     = var.filename == null || can(filebase64sha256(var.filename))
    error_message = "filename must point to an existing readable file."
  }

  validation {
    condition     = var.filename == null || can(regex("\\.zip$", var.filename))
    error_message = "filename must point to a .zip file."
  }
}

variable "source_code_hash" {
  description = "Optional deployment package hash. If null and filename is used, it is computed automatically."
  type        = string
  default     = null
}

variable "s3_bucket" {
  description = "S3 bucket containing Lambda deployment package zip. Use with s3_key."
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 key for Lambda deployment package zip. Use with s3_bucket."
  type        = string
  default     = null
}

variable "s3_object_version" {
  description = "Optional S3 object version for Lambda deployment package."
  type        = string
  default     = null
}

variable "dead_letter_target_arn" {
  description = "The ARN of the target to send failed events to"
  type        = string
  default     = null

  validation {
    condition     = var.dead_letter_target_arn == null || can(regex("^arn:aws[a-zA-Z-]*:(sqs|sns):[a-z0-9-]+:[0-9]{12}:.+$", var.dead_letter_target_arn))
    error_message = "dead_letter_target_arn must be a valid SQS or SNS ARN."
  }
}

variable "environment_variables" {
  description = "A map of environment variables to set for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "description" {
  description = "Description of the Lambda function."
  type        = string
  default     = null
}

variable "timeout" {
  description = "Lambda function timeout in seconds."
  type        = number
  default     = 3

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}

variable "memory_size" {
  description = "Amount of memory in MB allocated to the Lambda function."
  type        = number
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}

variable "publish" {
  description = "Whether to publish creation/change as a new Lambda function version."
  type        = bool
  default     = false
}

variable "architectures" {
  description = "Instruction set architecture for Lambda. Lambda supports a single value."
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition     = length(var.architectures) == 1 && contains(["x86_64", "arm64"], var.architectures[0])
    error_message = "architectures must contain exactly one value: x86_64 or arm64."
  }
}

variable "layers" {
  description = "List of Lambda layer ARNs."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for layer in var.layers :
      can(regex("^arn:aws[a-zA-Z-]*:lambda:[a-z0-9-]+:[0-9]{12}:layer:.+:[0-9]+$", layer))
    ])
    error_message = "Each layer in layers must be a valid Lambda layer version ARN."
  }
}

variable "ephemeral_storage_size" {
  description = "Size of /tmp directory in MB."
  type        = number
  default     = 512

  validation {
    condition     = var.ephemeral_storage_size >= 512 && var.ephemeral_storage_size <= 10240
    error_message = "ephemeral_storage_size must be between 512 and 10240 MB."
  }
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrency for the Lambda function. Use -1 for unreserved."
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions >= -1
    error_message = "reserved_concurrent_executions must be -1 or greater."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt Lambda environment variables."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS key ARN."
  }
}

variable "create_cloudwatch_log_group" {
  description = "Whether to create a dedicated CloudWatch log group for the Lambda function."
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days for the Lambda log group."
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365,
      400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a valid CloudWatch retention value."
  }
}

variable "log_group_kms_key_arn" {
  description = "Optional KMS key ARN for encrypting CloudWatch logs."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key\\/.+$", var.log_group_kms_key_arn))
    error_message = "log_group_kms_key_arn must be a valid KMS key ARN."
  }
}

variable "aliases" {
  description = "Lambda aliases keyed by alias name."
  type = map(object({
    description                        = optional(string)
    function_version                   = optional(string)
    routing_additional_version_weights = optional(map(number), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alias_name in keys(var.aliases) :
      can(regex("^[a-zA-Z0-9_-]{1,128}$", alias_name)) && !can(regex("^[0-9]+$", alias_name))
    ])
    error_message = "Alias names must be 1-128 characters, use letters/numbers/hyphens/underscores, and cannot be only digits."
  }

  validation {
    condition = alltrue([
      for cfg in values(var.aliases) :
      try(cfg.function_version, null) == null || can(regex("^[0-9]+$", cfg.function_version))
    ])
    error_message = "aliases[*].function_version must be null or a published numeric Lambda version."
  }

  validation {
    condition = alltrue(flatten([
      for cfg in values(var.aliases) : [
        for weight in values(try(cfg.routing_additional_version_weights, {})) :
        weight > 0 && weight < 1
      ]
    ]))
    error_message = "aliases[*].routing_additional_version_weights values must be between 0 and 1 (exclusive)."
  }
}

variable "tracing_mode" {
  description = "Lambda X-Ray tracing mode. Valid values are PassThrough or Active."
  type        = string
  default     = "PassThrough"

  validation {
    condition     = contains(["PassThrough", "Active"], var.tracing_mode)
    error_message = "tracing_mode must be one of: PassThrough, Active."
  }
}

variable "metric_alarms" {
  description = "Map of CloudWatch metric alarms keyed by logical alarm key."
  type = map(object({
    alarm_name               = optional(string)
    alarm_description        = optional(string)
    comparison_operator      = string
    evaluation_periods       = number
    metric_name              = string
    namespace                = optional(string, "AWS/Lambda")
    period                   = number
    statistic                = optional(string)
    extended_statistic       = optional(string)
    threshold                = number
    datapoints_to_alarm      = optional(number)
    treat_missing_data       = optional(string)
    alarm_actions            = optional(list(string), [])
    ok_actions               = optional(list(string), [])
    insufficient_data_actions = optional(list(string), [])
    dimensions               = optional(map(string), {})
    tags                     = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for alarm in values(var.metric_alarms) :
      ((try(alarm.statistic, null) != null) != (try(alarm.extended_statistic, null) != null))
    ])
    error_message = "Each metric_alarms entry must set exactly one of statistic or extended_statistic."
  }
}
