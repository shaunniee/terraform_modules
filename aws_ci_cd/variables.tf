# =============================================================================
# AWS CI/CD Module - Variables
# =============================================================================
#
# This is the parent orchestrator module that ties together CodeBuild,
# CodePipeline, and CodeDeploy with shared infrastructure (artifact bucket, KMS).
#
# =============================================================================

variable "name" {
  description = "Base name used for naming all CI/CD resources."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{1,100}$", var.name))
    error_message = "name must be 2-101 characters, start with alphanumeric, and contain only alphanumeric, hyphens, and underscores."
  }
}

# =============================================================================
# Artifact Bucket Configuration
# =============================================================================

variable "create_artifact_bucket" {
  description = "Whether to create an S3 bucket for pipeline artifacts. Set to false if using an existing bucket."
  type        = bool
  default     = true
}

variable "artifact_bucket_name" {
  description = "Name for the artifact S3 bucket. Defaults to '{name}-artifacts-{account_id}'."
  type        = string
  default     = null

  validation {
    condition     = var.artifact_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be 3-63 chars, lowercase letters/numbers/dots/hyphens, and start/end with alphanumeric."
  }
}

variable "existing_artifact_bucket_name" {
  description = "Name of an existing S3 bucket to use for artifacts (when create_artifact_bucket is false)."
  type        = string
  default     = null

  validation {
    condition     = var.create_artifact_bucket || (var.existing_artifact_bucket_name != null && trimspace(var.existing_artifact_bucket_name) != "")
    error_message = "existing_artifact_bucket_name is required when create_artifact_bucket is false."
  }

  validation {
    condition     = var.existing_artifact_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.existing_artifact_bucket_name))
    error_message = "existing_artifact_bucket_name must be a valid S3 bucket name (3-63 chars, lowercase letters/numbers/dots/hyphens)."
  }
}

variable "artifact_bucket_config" {
  description = <<-EOT
    Configuration for the artifact S3 bucket.
    - versioning:                Enable versioning for artifact rollback support.
    - force_destroy:             Allow bucket deletion even with objects inside (use with caution).
    - lifecycle_expiration_days: Number of days before artifacts are automatically deleted (0 to disable).
    - noncurrent_expiration_days: Days before noncurrent versions are deleted.
    - kms_key_arn:               KMS key ARN for server-side encryption (uses AES256 if null).
    - access_logging_bucket:     S3 bucket name for access logging (null to disable).
    - access_logging_prefix:     Prefix for access log objects.
  EOT
  type = object({
    versioning                 = optional(bool, true)
    force_destroy              = optional(bool, false)
    lifecycle_expiration_days  = optional(number, 90)
    noncurrent_expiration_days = optional(number, 30)
    kms_key_arn                = optional(string)
    access_logging_bucket      = optional(string)
    access_logging_prefix      = optional(string, "artifact-access-logs/")
  })
  default = {}
}

# =============================================================================
# KMS Key Configuration
# =============================================================================

variable "create_kms_key" {
  description = "Whether to create a KMS key for encrypting CI/CD artifacts and logs."
  type        = bool
  default     = false
}

variable "kms_key_config" {
  description = <<-EOT
    Configuration for the KMS key.
    - description:             Key description.
    - deletion_window_in_days: Waiting period before key deletion (7-30 days).
    - enable_key_rotation:     Enable automatic key rotation.
  EOT
  type = object({
    description             = optional(string)
    deletion_window_in_days = optional(number, 30)
    enable_key_rotation     = optional(bool, true)
  })
  default = {}
}

# =============================================================================
# CodeBuild Projects
# =============================================================================

variable "codebuild_projects" {
  description = <<-EOT
    Map of CodeBuild project configurations keyed by project name.
    Each project accepts all aws_codebuild submodule variables.
    See the aws_codebuild submodule for full variable documentation.
  EOT
  type = map(object({
    description            = optional(string)
    build_timeout          = optional(number, 60)
    queued_timeout         = optional(number, 480)
    concurrent_build_limit = optional(number)
    source_version         = optional(string)
    badge_enabled          = optional(bool, false)

    source_config = object({
      type                  = string
      location              = optional(string)
      buildspec             = optional(string)
      git_clone_depth       = optional(number, 1)
      git_submodules_config = optional(bool, false)
      insecure_ssl          = optional(bool, false)
      report_build_status   = optional(bool, false)
    })

    secondary_sources         = optional(list(any), [])
    secondary_source_versions = optional(map(string), {})

    environment = optional(object({
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
    }), {})

    artifacts = optional(object({
      type                   = optional(string, "NO_ARTIFACTS")
      location               = optional(string)
      name                   = optional(string)
      namespace_type         = optional(string)
      packaging              = optional(string)
      path                   = optional(string)
      encryption_disabled    = optional(bool, false)
      override_artifact_name = optional(bool, false)
    }), {})

    secondary_artifacts = optional(list(any), [])

    cache = optional(object({
      type     = optional(string, "NO_CACHE")
      location = optional(string)
      modes    = optional(list(string), [])
    }), {})

    vpc_config = optional(object({
      vpc_id             = string
      subnets            = list(string)
      security_group_ids = list(string)
    }))

    logs_config = optional(object({
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
    }), {})

    service_role_arn   = optional(string)
    encryption_key     = optional(string)
    webhooks           = optional(list(any), [])
    file_system_locations = optional(list(any), [])
    build_batch_config = optional(any)

    observability = optional(object({
      enabled                           = optional(bool, false)
      enable_default_alarms             = optional(bool, true)
      enable_dashboard                  = optional(bool, false)
      default_alarm_actions             = optional(list(string), [])
      default_ok_actions                = optional(list(string), [])
      default_insufficient_data_actions = optional(list(string), [])
      failed_builds_threshold           = optional(number, 1)
      build_duration_threshold          = optional(number, 3600)
    }), {})

    cloudwatch_metric_alarms = optional(map(any), {})
  }))
  default = {}
}

# =============================================================================
# CodePipeline Configuration
# =============================================================================

variable "codepipeline" {
  description = <<-EOT
    CodePipeline configuration. Set to null to skip pipeline creation.
    See the aws_code_pipeline submodule for full variable documentation.
  EOT
  type = object({
    name           = optional(string)
    pipeline_type  = optional(string, "V2")
    execution_mode = optional(string, "QUEUED")

    stages = list(object({
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

    additional_artifact_stores = optional(map(object({
      location            = string
      type                = optional(string, "S3")
      encryption_key_id   = optional(string)
      encryption_key_type = optional(string, "KMS")
    })), {})

    triggers  = optional(list(any), [])
    variables = optional(list(any), [])

    service_role_arn = optional(string)

    observability = optional(object({
      enabled                           = optional(bool, false)
      enable_default_alarms             = optional(bool, true)
      enable_dashboard                  = optional(bool, false)
      enable_event_notifications        = optional(bool, false)
      notification_sns_topic_arn        = optional(string)
      default_alarm_actions             = optional(list(string), [])
      default_ok_actions                = optional(list(string), [])
      default_insufficient_data_actions = optional(list(string), [])
      failed_executions_threshold       = optional(number, 1)
    }), {})

    cloudwatch_metric_alarms = optional(map(any), {})
  })
  default = null
}

# =============================================================================
# CodeDeploy Configuration
# =============================================================================

variable "codedeploy" {
  description = <<-EOT
    CodeDeploy configuration. Set to null to skip CodeDeploy creation.
    See the aws_code_deploy submodule for full variable documentation.
  EOT
  type = object({
    application_name = optional(string)
    compute_platform = optional(string, "Server")

    deployment_groups = optional(map(object({
      deployment_config_name = optional(string, "CodeDeployDefault.AllAtOnce")
      deployment_type        = optional(string, "IN_PLACE")

      ec2_tag_filters = optional(list(object({
        key   = optional(string)
        value = optional(string)
        type  = optional(string, "KEY_AND_VALUE")
      })), [])

      ec2_tag_set = optional(list(list(object({
        key   = optional(string)
        value = optional(string)
        type  = optional(string, "KEY_AND_VALUE")
      }))), [])

      autoscaling_groups = optional(list(string), [])

      ecs_service = optional(object({
        cluster_name = string
        service_name = string
      }))

      load_balancer_info = optional(object({
        elb_info = optional(list(object({
          name = string
        })), [])
        target_group_info = optional(list(object({
          name = string
        })), [])
        target_group_pair_info = optional(object({
          target_groups = list(object({
            name = string
          }))
          prod_traffic_route = object({
            listener_arns = list(string)
          })
          test_traffic_route = optional(object({
            listener_arns = list(string)
          }))
        }))
      }))

      blue_green_deployment_config = optional(object({
        deployment_ready_option = optional(object({
          action_on_timeout    = optional(string, "CONTINUE_DEPLOYMENT")
          wait_time_in_minutes = optional(number, 0)
        }))
        green_fleet_provisioning_option = optional(object({
          action = optional(string, "DISCOVER_EXISTING")
        }))
        terminate_blue_instances_on_deployment_success = optional(object({
          action                           = optional(string, "TERMINATE")
          termination_wait_time_in_minutes = optional(number, 0)
        }))
      }))

      auto_rollback_configuration = optional(object({
        enabled = optional(bool, true)
        events  = optional(list(string), ["DEPLOYMENT_FAILURE"])
      }))

      alarm_configuration = optional(object({
        enabled                   = optional(bool, false)
        alarms                    = optional(list(string), [])
        ignore_poll_alarm_failure = optional(bool, false)
      }))

      trigger_configuration = optional(list(object({
        trigger_name       = string
        trigger_target_arn = string
        trigger_events     = list(string)
      })), [])

      on_premises_tag_filters = optional(list(object({
        key   = optional(string)
        value = optional(string)
        type  = optional(string, "KEY_AND_VALUE")
      })), [])

      outdated_instances_strategy = optional(string, "UPDATE")
    })), {})

    custom_deployment_configs = optional(map(object({
      compute_platform = optional(string)
      minimum_healthy_hosts = optional(object({
        type  = string
        value = number
      }))
      traffic_routing_config = optional(object({
        type = string
        time_based_canary = optional(object({
          interval   = number
          percentage = number
        }))
        time_based_linear = optional(object({
          interval   = number
          percentage = number
        }))
      }))
    })), {})

    service_role_arn = optional(string)

    observability = optional(object({
      enabled                           = optional(bool, false)
      enable_default_alarms             = optional(bool, true)
      enable_dashboard                  = optional(bool, false)
      default_alarm_actions             = optional(list(string), [])
      default_ok_actions                = optional(list(string), [])
      default_insufficient_data_actions = optional(list(string), [])
    }), {})

    cloudwatch_metric_alarms = optional(map(any), {})
  })
  default = null
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "A map of tags to apply to all CI/CD resources."
  type        = map(string)
  default     = {}
}
