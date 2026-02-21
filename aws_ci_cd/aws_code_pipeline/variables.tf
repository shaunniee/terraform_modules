# =============================================================================
# CodePipeline - Variables
# =============================================================================

variable "name" {
  description = "The name of the CodePipeline."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{1,254}$", var.name))
    error_message = "Pipeline name must be 2-255 characters, start with alphanumeric, and contain only alphanumeric, periods, hyphens, and underscores."
  }
}

variable "pipeline_type" {
  description = "The type of the pipeline (V1 or V2). V2 supports triggers, variables, and additional execution modes."
  type        = string
  default     = "V2"

  validation {
    condition     = contains(["V1", "V2"], var.pipeline_type)
    error_message = "pipeline_type must be V1 or V2."
  }
}

variable "execution_mode" {
  description = "The execution mode of the pipeline (QUEUED, SUPERSEDED, PARALLEL). Only SUPERSEDED is valid for V1 pipelines."
  type        = string
  default     = "QUEUED"

  validation {
    condition     = contains(["QUEUED", "SUPERSEDED", "PARALLEL"], var.execution_mode)
    error_message = "execution_mode must be QUEUED, SUPERSEDED, or PARALLEL."
  }
}

# =============================================================================
# Artifact Store
# =============================================================================

variable "artifact_store" {
  description = <<-EOT
    Artifact store configuration for the pipeline.
    - location:             S3 bucket name for storing pipeline artifacts.
    - type:                 Artifact store type (only S3 is supported).
    - encryption_key_id:    KMS key ARN or ID for encrypting artifacts.
    - encryption_key_type:  Encryption key type (KMS).
    - region:               Region for cross-region artifact store (null for default region).
  EOT
  type = object({
    location            = string
    type                = optional(string, "S3")
    encryption_key_id   = optional(string)
    encryption_key_type = optional(string, "KMS")
    region              = optional(string)
  })
}

variable "additional_artifact_stores" {
  description = "Additional artifact stores for cross-region pipelines. Map of region to artifact store configuration."
  type = map(object({
    location            = string
    type                = optional(string, "S3")
    encryption_key_id   = optional(string)
    encryption_key_type = optional(string, "KMS")
  }))
  default = {}
}

# =============================================================================
# Stages Configuration
# =============================================================================

variable "stages" {
  description = <<-EOT
    List of pipeline stages. Each stage contains one or more actions.
    Minimum 2 stages required (source + at least one other).

    Stage object:
    - name:    Stage name.
    - actions: List of actions in the stage.

    Action object:
    - name:             Action name.
    - category:         Action category (Source, Build, Deploy, Test, Approval, Invoke).
    - owner:            Action owner (AWS, ThirdParty, Custom).
    - provider:         Action provider (e.g., CodeCommit, CodeBuild, CodeDeploy, S3, GitHub, Manual, CodeStarSourceConnection).
    - version:          Action version (typically "1").
    - input_artifacts:  List of input artifact names.
    - output_artifacts: List of output artifact names.
    - configuration:    Map of action-specific configuration key-value pairs.
    - run_order:        Order in which the action runs within the stage (default: 1).
    - region:           Region for cross-region actions.
    - namespace:        Variable namespace for the action's output variables.
    - role_arn:         IAM role ARN for cross-account actions.
  EOT
  type = list(object({
    name = string
    actions = list(object({
      name             = string
      category         = string
      owner            = string
      provider         = string
      version          = optional(string, "1")
      input_artifacts  = optional(list(string), [])
      output_artifacts = optional(list(string), [])
      configuration    = optional(map(string), {})
      run_order        = optional(number, 1)
      region           = optional(string)
      namespace        = optional(string)
      role_arn         = optional(string)
    }))
  }))

  validation {
    condition     = length(var.stages) >= 2
    error_message = "Pipeline must have at least 2 stages (source + one other)."
  }

  validation {
    condition = alltrue([
      for stage in var.stages : alltrue([
        for action in stage.actions :
        contains(["Source", "Build", "Deploy", "Test", "Approval", "Invoke"], action.category)
      ])
    ])
    error_message = "Action category must be one of: Source, Build, Deploy, Test, Approval, Invoke."
  }

  validation {
    condition = alltrue([
      for stage in var.stages : alltrue([
        for action in stage.actions :
        contains(["AWS", "ThirdParty", "Custom"], action.owner)
      ])
    ])
    error_message = "Action owner must be one of: AWS, ThirdParty, Custom."
  }
}

# =============================================================================
# V2 Pipeline Triggers
# =============================================================================

variable "triggers" {
  description = <<-EOT
    Trigger configurations for V2 pipelines. Allows filtering which events trigger the pipeline.
    - provider_type:     Trigger provider (CodeStarSourceConnection).
    - git_configuration: Git-based trigger filters.
      - source_action_name: Name of the source action this trigger applies to.
      - push:              List of push event filters ({ tags, branches, file_paths } with includes/excludes).
      - pull_request:      List of pull request event filters ({ events, branches, file_paths }).
  EOT
  type = list(object({
    provider_type = optional(string, "CodeStarSourceConnection")
    git_configuration = object({
      source_action_name = string
      push = optional(list(object({
        tags = optional(object({
          includes = optional(list(string), [])
          excludes = optional(list(string), [])
        }))
        branches = optional(object({
          includes = optional(list(string), [])
          excludes = optional(list(string), [])
        }))
        file_paths = optional(object({
          includes = optional(list(string), [])
          excludes = optional(list(string), [])
        }))
      })), [])
      pull_request = optional(list(object({
        events = optional(list(string), ["OPEN", "UPDATED"])
        branches = optional(object({
          includes = optional(list(string), [])
          excludes = optional(list(string), [])
        }))
        file_paths = optional(object({
          includes = optional(list(string), [])
          excludes = optional(list(string), [])
        }))
      })), [])
    })
  }))
  default = []
}

# =============================================================================
# Pipeline Variables
# =============================================================================

variable "variables" {
  description = <<-EOT
    Pipeline-level variables (V2 only).
    - name:          Variable name.
    - default_value: Default value for the variable.
    - description:   Variable description.
  EOT
  type = list(object({
    name          = string
    default_value = optional(string)
    description   = optional(string)
  }))
  default = []
}

# =============================================================================
# IAM Configuration
# =============================================================================

variable "service_role_arn" {
  description = "ARN of an existing IAM service role for CodePipeline. If null, a role is auto-created with required permissions."
  type        = string
  default     = null

  validation {
    condition     = var.service_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/", var.service_role_arn))
    error_message = "service_role_arn must be a valid IAM role ARN."
  }
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Observability
# =============================================================================

variable "observability" {
  description = <<-EOT
    Observability configuration for CloudWatch alarms and event notifications.
    - enabled:                          Enable observability features.
    - enable_default_alarms:            Create default alarms for pipeline execution failures.
    - enable_dashboard:                 Create a CloudWatch dashboard.
    - enable_event_notifications:       Create EventBridge rule for pipeline state changes.
    - notification_sns_topic_arn:       SNS topic ARN for event notifications.
    - default_alarm_actions:            SNS topic ARNs for alarm notifications.
    - default_ok_actions:               SNS topic ARNs for OK state notifications.
    - default_insufficient_data_actions: SNS topic ARNs for insufficient data notifications.
    - failed_executions_threshold:      Threshold for failed pipeline executions alarm.
  EOT
  type = object({
    enabled                           = optional(bool, false)
    enable_default_alarms             = optional(bool, true)
    enable_dashboard                  = optional(bool, false)
    enable_event_notifications        = optional(bool, false)
    notification_sns_topic_arn        = optional(string)
    default_alarm_actions             = optional(list(string), [])
    default_ok_actions                = optional(list(string), [])
    default_insufficient_data_actions = optional(list(string), [])
    failed_executions_threshold       = optional(number, 1)
  })
  default = {}
}

variable "cloudwatch_metric_alarms" {
  description = "Map of custom CloudWatch metric alarms to create for this pipeline."
  type = map(object({
    alarm_description   = optional(string)
    metric_name         = string
    namespace           = optional(string, "AWS/CodePipeline")
    comparison_operator = string
    threshold           = number
    evaluation_periods  = optional(number, 1)
    period              = optional(number, 300)
    statistic           = optional(string, "Sum")
    treat_missing_data  = optional(string, "notBreaching")
    alarm_actions       = optional(list(string), [])
    ok_actions          = optional(list(string), [])
    dimensions          = optional(map(string), {})
  }))
  default = {}
}
