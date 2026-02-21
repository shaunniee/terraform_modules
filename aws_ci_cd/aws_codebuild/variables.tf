# =============================================================================
# CodeBuild Project - Variables
# =============================================================================

variable "name" {
  description = "The name of the CodeBuild project."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{1,254}$", var.name))
    error_message = "Project name must be 2-255 characters, start with alphanumeric, and contain only alphanumeric, hyphens, and underscores."
  }
}

variable "description" {
  description = "A short description of the CodeBuild project."
  type        = string
  default     = null
}

variable "build_timeout" {
  description = "Build timeout in minutes (5-480)."
  type        = number
  default     = 60

  validation {
    condition     = var.build_timeout >= 5 && var.build_timeout <= 480
    error_message = "build_timeout must be between 5 and 480 minutes."
  }
}

variable "queued_timeout" {
  description = "Queue timeout in minutes (5-480)."
  type        = number
  default     = 480

  validation {
    condition     = var.queued_timeout >= 5 && var.queued_timeout <= 480
    error_message = "queued_timeout must be between 5 and 480 minutes."
  }
}

variable "concurrent_build_limit" {
  description = "Maximum number of concurrent builds. Set to null for no limit."
  type        = number
  default     = null
}

variable "source_version" {
  description = "Source version (branch name, tag, commit ID). Leave null to use default branch."
  type        = string
  default     = null
}

variable "badge_enabled" {
  description = "Whether to generate a publicly-accessible build badge URL."
  type        = bool
  default     = false
}

# =============================================================================
# Source Configuration
# =============================================================================

variable "source_config" {
  description = <<-EOT
    Source configuration for the CodeBuild project.
    - type:                   Source type (CODECOMMIT, CODEPIPELINE, GITHUB, GITHUB_ENTERPRISE, BITBUCKET, S3, NO_SOURCE)
    - location:               Source location (repository URL, S3 bucket/key). Required unless type is CODEPIPELINE or NO_SOURCE.
    - buildspec:              Buildspec file path or inline YAML. Defaults to buildspec.yml in source root.
    - git_clone_depth:        Git clone depth (0 for full clone).
    - git_submodules_config:  Whether to fetch git submodules.
    - insecure_ssl:           Whether to ignore SSL warnings when connecting to source.
    - report_build_status:    Whether to report build status back to source provider.
  EOT
  type = object({
    type                  = string
    location              = optional(string)
    buildspec             = optional(string)
    git_clone_depth       = optional(number, 1)
    git_submodules_config = optional(bool, false)
    insecure_ssl          = optional(bool, false)
    report_build_status   = optional(bool, false)
  })

  validation {
    condition     = contains(["CODECOMMIT", "CODEPIPELINE", "GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET", "S3", "NO_SOURCE"], var.source_config.type)
    error_message = "source_config.type must be one of: CODECOMMIT, CODEPIPELINE, GITHUB, GITHUB_ENTERPRISE, BITBUCKET, S3, NO_SOURCE."
  }
}

variable "secondary_sources" {
  description = "List of secondary source configurations. Each must include a source_identifier."
  type = list(object({
    source_identifier     = string
    type                  = string
    location              = string
    buildspec             = optional(string)
    git_clone_depth       = optional(number, 1)
    git_submodules_config = optional(bool, false)
    insecure_ssl          = optional(bool, false)
    report_build_status   = optional(bool, false)
  }))
  default = []
}

variable "secondary_source_versions" {
  description = "Map of secondary source identifier to source version."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Environment Configuration
# =============================================================================

variable "environment" {
  description = <<-EOT
    Build environment configuration.
    - compute_type:                Compute type (BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE, BUILD_GENERAL1_2XLARGE, BUILD_LAMBDA_*)
    - image:                       Docker image for the build environment.
    - type:                        Environment type (LINUX_CONTAINER, ARM_CONTAINER, WINDOWS_CONTAINER, etc.)
    - privileged_mode:             Enable privileged mode (required for Docker-in-Docker builds).
    - image_pull_credentials_type: Credentials type for pulling image (CODEBUILD or SERVICE_ROLE).
    - certificate:                 ARN of S3 bucket object containing certificate for the build project.
    - environment_variables:       List of environment variables for the build.
  EOT
  type = object({
    compute_type                = optional(string, "BUILD_GENERAL1_SMALL")
    image                       = optional(string, "aws/codebuild/amazonlinux2-x86_64-standard:5.0")
    type                        = optional(string, "LINUX_CONTAINER")
    privileged_mode             = optional(bool, false)
    image_pull_credentials_type = optional(string, "CODEBUILD")
    certificate                 = optional(string)
    environment_variables = optional(list(object({
      name  = string
      value = string
      type  = optional(string, "PLAINTEXT")
    })), [])
  })
  default = {}

  validation {
    condition = contains([
      "LINUX_CONTAINER", "LINUX_GPU_CONTAINER", "ARM_CONTAINER",
      "WINDOWS_CONTAINER", "WINDOWS_SERVER_2019_CONTAINER",
      "LINUX_LAMBDA_CONTAINER", "ARM_LAMBDA_CONTAINER"
    ], var.environment.type)
    error_message = "environment.type must be a valid CodeBuild environment type."
  }

  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_2XLARGE",
      "BUILD_LAMBDA_1GB", "BUILD_LAMBDA_2GB", "BUILD_LAMBDA_4GB", "BUILD_LAMBDA_8GB", "BUILD_LAMBDA_10GB"
    ], var.environment.compute_type)
    error_message = "environment.compute_type must be a valid CodeBuild compute type."
  }

  validation {
    condition = contains(["CODEBUILD", "SERVICE_ROLE"], var.environment.image_pull_credentials_type)
    error_message = "environment.image_pull_credentials_type must be CODEBUILD or SERVICE_ROLE."
  }

  validation {
    condition = alltrue([
      for env_var in var.environment.environment_variables :
      contains(["PLAINTEXT", "PARAMETER_STORE", "SECRETS_MANAGER"], env_var.type)
    ])
    error_message = "Each environment_variable type must be PLAINTEXT, PARAMETER_STORE, or SECRETS_MANAGER."
  }
}

# =============================================================================
# Artifacts Configuration
# =============================================================================

variable "artifacts" {
  description = <<-EOT
    Build artifacts configuration.
    - type:                    Artifact type (CODEPIPELINE, NO_ARTIFACTS, S3).
    - location:                S3 bucket name (required when type is S3).
    - name:                    Artifact name.
    - namespace_type:          Namespace type (NONE or BUILD_ID).
    - packaging:               Packaging type (NONE or ZIP).
    - path:                    Path inside the S3 bucket.
    - encryption_disabled:     Whether to disable artifact encryption.
    - override_artifact_name:  Whether buildspec can override artifact name.
  EOT
  type = object({
    type                   = optional(string, "NO_ARTIFACTS")
    location               = optional(string)
    name                   = optional(string)
    namespace_type         = optional(string)
    packaging              = optional(string)
    path                   = optional(string)
    encryption_disabled    = optional(bool, false)
    override_artifact_name = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["CODEPIPELINE", "NO_ARTIFACTS", "S3"], var.artifacts.type)
    error_message = "artifacts.type must be one of: CODEPIPELINE, NO_ARTIFACTS, S3."
  }
}

variable "secondary_artifacts" {
  description = "List of secondary artifact configurations. Each must include an artifact_identifier."
  type = list(object({
    artifact_identifier    = string
    type                   = string
    location               = optional(string)
    name                   = optional(string)
    namespace_type         = optional(string)
    packaging              = optional(string)
    path                   = optional(string)
    encryption_disabled    = optional(bool, false)
    override_artifact_name = optional(bool, false)
  }))
  default = []
}

# =============================================================================
# Cache Configuration
# =============================================================================

variable "cache" {
  description = <<-EOT
    Build cache configuration.
    - type:     Cache type (NO_CACHE, S3, LOCAL).
    - location: S3 bucket/prefix for S3 cache.
    - modes:    Cache modes for LOCAL type.
  EOT
  type = object({
    type     = optional(string, "NO_CACHE")
    location = optional(string)
    modes    = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["NO_CACHE", "S3", "LOCAL"], var.cache.type)
    error_message = "cache.type must be one of: NO_CACHE, S3, LOCAL."
  }

  validation {
    condition = alltrue([
      for mode in var.cache.modes :
      contains(["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE", "LOCAL_CUSTOM_CACHE"], mode)
    ])
    error_message = "cache.modes entries must be LOCAL_DOCKER_LAYER_CACHE, LOCAL_SOURCE_CACHE, or LOCAL_CUSTOM_CACHE."
  }
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_config" {
  description = <<-EOT
    VPC configuration for CodeBuild to access private resources.
    - vpc_id:             VPC ID.
    - subnets:            List of subnet IDs.
    - security_group_ids: List of security group IDs.
  EOT
  type = object({
    vpc_id             = string
    subnets            = list(string)
    security_group_ids = list(string)
  })
  default = null
}

# =============================================================================
# Logging Configuration
# =============================================================================

variable "logs_config" {
  description = <<-EOT
    Logging configuration for build output.
    - cloudwatch: CloudWatch Logs configuration (group_name, stream_name, status).
    - s3:         S3 logging configuration (location, status, encryption_disabled).
  EOT
  type = object({
    cloudwatch = optional(object({
      group_name  = optional(string)
      stream_name = optional(string)
      status      = optional(string, "ENABLED")
    }), {})
    s3 = optional(object({
      location            = string
      status              = optional(string, "DISABLED")
      encryption_disabled = optional(bool, false)
    }))
  })
  default = {}
}

# =============================================================================
# IAM Configuration
# =============================================================================

variable "service_role_arn" {
  description = "ARN of an existing IAM service role for CodeBuild. If null, a role is auto-created with least-privilege permissions."
  type        = string
  default     = null

  validation {
    condition     = var.service_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:role/", var.service_role_arn))
    error_message = "service_role_arn must be a valid IAM role ARN."
  }
}

variable "encryption_key" {
  description = "KMS key ARN for encrypting build output artifacts."
  type        = string
  default     = null

  validation {
    condition     = var.encryption_key == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.encryption_key))
    error_message = "encryption_key must be a valid KMS key ARN."
  }
}

# =============================================================================
# Webhook Configuration
# =============================================================================

variable "webhooks" {
  description = <<-EOT
    List of webhook configurations for triggering builds from source providers.
    - build_type:    Build type (BUILD or BUILD_BATCH).
    - filter_groups: List of filter groups. AND logic within a group, OR logic between groups.
      Each filter: { type (EVENT, BASE_REF, HEAD_REF, FILE_PATH, COMMIT_MESSAGE, ACTOR_ACCOUNT_ID), pattern, exclude_matched_pattern }
  EOT
  type = list(object({
    build_type = optional(string, "BUILD")
    filter_groups = list(list(object({
      type                    = string
      pattern                 = string
      exclude_matched_pattern = optional(bool, false)
    })))
  }))
  default = []
}

# =============================================================================
# File System Locations (EFS)
# =============================================================================

variable "file_system_locations" {
  description = <<-EOT
    List of EFS file system locations to mount in the build environment.
    - identifier:    Unique identifier for the file system location.
    - location:      EFS DNS name with mount path.
    - mount_point:   Mount point inside the build container.
    - mount_options: NFS mount options.
    - type:          File system type (EFS).
  EOT
  type = list(object({
    identifier    = string
    location      = string
    mount_point   = string
    mount_options = optional(string, "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2")
    type          = optional(string, "EFS")
  }))
  default = []
}

# =============================================================================
# Build Batch Configuration
# =============================================================================

variable "build_batch_config" {
  description = <<-EOT
    Build batch configuration for running multiple builds in parallel.
    - service_role:      IAM role ARN for batch builds (uses main service role if null).
    - combine_artifacts: Whether to combine batch build artifacts into a single artifact.
    - timeout_in_mins:   Batch build timeout in minutes.
    - restrictions:      Batch build restrictions (compute types, max builds).
  EOT
  type = object({
    service_role      = optional(string)
    combine_artifacts = optional(bool, false)
    timeout_in_mins   = optional(number, 480)
    restrictions = optional(object({
      compute_types_allowed  = optional(list(string), [])
      maximum_builds_allowed = optional(number, 100)
    }), {})
  })
  default = null
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
    Observability configuration for CloudWatch alarms and dashboards.
    - enabled:                          Enable observability features.
    - enable_default_alarms:            Create default alarms for failed builds and build duration.
    - enable_dashboard:                 Create a CloudWatch dashboard for build metrics.
    - default_alarm_actions:            SNS topic ARNs for alarm notifications.
    - default_ok_actions:               SNS topic ARNs for OK state notifications.
    - default_insufficient_data_actions: SNS topic ARNs for insufficient data notifications.
    - failed_builds_threshold:          Number of failed builds to trigger alarm (default: 1).
    - build_duration_threshold:         Build duration in seconds to trigger alarm (default: 3600).
  EOT
  type = object({
    enabled                           = optional(bool, false)
    enable_default_alarms             = optional(bool, true)
    enable_dashboard                  = optional(bool, false)
    default_alarm_actions             = optional(list(string), [])
    default_ok_actions                = optional(list(string), [])
    default_insufficient_data_actions = optional(list(string), [])
    failed_builds_threshold           = optional(number, 1)
    build_duration_threshold          = optional(number, 3600)
  })
  default = {}
}

variable "cloudwatch_metric_alarms" {
  description = "Map of custom CloudWatch metric alarms to create for this CodeBuild project."
  type = map(object({
    alarm_description   = optional(string)
    metric_name         = string
    namespace           = optional(string, "AWS/CodeBuild")
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
