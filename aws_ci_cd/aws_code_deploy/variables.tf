# =============================================================================
# CodeDeploy - Variables
# =============================================================================

variable "application_name" {
  description = "The name of the CodeDeploy application."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,99}$", var.application_name))
    error_message = "Application name must be 1-100 characters, start with alphanumeric."
  }
}

variable "compute_platform" {
  description = "The compute platform for the application (Server, ECS, Lambda)."
  type        = string
  default     = "Server"

  validation {
    condition     = contains(["Server", "ECS", "Lambda"], var.compute_platform)
    error_message = "compute_platform must be one of: Server, ECS, Lambda."
  }
}

# =============================================================================
# Deployment Groups
# =============================================================================

variable "deployment_groups" {
  description = <<-EOT
    Map of deployment group configurations keyed by group name.

    Each deployment group supports:
    - deployment_config_name: Predefined or custom deployment config name.
    - deployment_type:        IN_PLACE or BLUE_GREEN.
    - ec2_tag_filters:        List of EC2 tag filters ({ key, value, type }).
    - ec2_tag_set:            List of EC2 tag sets (AND within set, OR between sets).
    - autoscaling_groups:     List of Auto Scaling group names.
    - ecs_service:            ECS service config ({ cluster_name, service_name }).
    - load_balancer_info:     Load balancer configuration for blue/green deployments.
    - blue_green_deployment_config: Blue/green deployment behavior configuration.
    - auto_rollback_configuration:  Auto rollback settings.
    - alarm_configuration:    CloudWatch alarm integration for deployment monitoring.
    - trigger_configuration:  SNS notification triggers for deployment events.
    - on_premises_tag_filters: List of on-premises instance tag filters.
    - outdated_instances_strategy: How to handle outdated instances (UPDATE or IGNORE).
  EOT
  type = map(object({
    deployment_config_name = optional(string, "CodeDeployDefault.AllAtOnce")
    deployment_type        = optional(string, "IN_PLACE")

    # EC2 Tag Filters
    ec2_tag_filters = optional(list(object({
      key   = optional(string)
      value = optional(string)
      type  = optional(string, "KEY_AND_VALUE")
    })), [])

    # EC2 Tag Sets (AND logic within a set, OR logic between sets)
    ec2_tag_set = optional(list(list(object({
      key   = optional(string)
      value = optional(string)
      type  = optional(string, "KEY_AND_VALUE")
    }))), [])

    # Auto Scaling Groups
    autoscaling_groups = optional(list(string), [])

    # ECS Service (for ECS compute platform)
    ecs_service = optional(object({
      cluster_name = string
      service_name = string
    }))

    # Load Balancer Info
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

    # Blue/Green Deployment Config
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

    # Auto Rollback
    auto_rollback_configuration = optional(object({
      enabled = optional(bool, true)
      events  = optional(list(string), ["DEPLOYMENT_FAILURE"])
    }))

    # Alarm Configuration
    alarm_configuration = optional(object({
      enabled                  = optional(bool, false)
      alarms                   = optional(list(string), [])
      ignore_poll_alarm_failure = optional(bool, false)
    }))

    # Trigger Configuration
    trigger_configuration = optional(list(object({
      trigger_name       = string
      trigger_target_arn = string
      trigger_events = list(string)
    })), [])

    # On-Premises Tag Filters
    on_premises_tag_filters = optional(list(object({
      key   = optional(string)
      value = optional(string)
      type  = optional(string, "KEY_AND_VALUE")
    })), [])

    outdated_instances_strategy = optional(string, "UPDATE")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, group in var.deployment_groups :
      contains(["IN_PLACE", "BLUE_GREEN"], group.deployment_type)
    ])
    error_message = "deployment_type must be IN_PLACE or BLUE_GREEN."
  }

  validation {
    condition = alltrue([
      for name, group in var.deployment_groups :
      contains(["UPDATE", "IGNORE"], group.outdated_instances_strategy)
    ])
    error_message = "outdated_instances_strategy must be UPDATE or IGNORE."
  }
}

# =============================================================================
# Custom Deployment Configurations
# =============================================================================

variable "custom_deployment_configs" {
  description = <<-EOT
    Map of custom deployment configurations keyed by config name.
    - compute_platform:       Compute platform (Server, ECS, Lambda).
    - minimum_healthy_hosts:  For Server platform - minimum healthy hosts config.
    - traffic_routing_config: For ECS/Lambda platform - traffic routing config.
  EOT
  type = map(object({
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
  }))
  default = {}
}

# =============================================================================
# IAM Configuration
# =============================================================================

variable "service_role_arn" {
  description = "ARN of an existing IAM service role for CodeDeploy. If null, a role is auto-created with managed policies."
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
    Observability configuration for CloudWatch alarms.
    - enabled:                          Enable observability features.
    - enable_default_alarms:            Create default alarms for deployment failures.
    - enable_dashboard:                 Create a CloudWatch dashboard.
    - default_alarm_actions:            SNS topic ARNs for alarm notifications.
    - default_ok_actions:               SNS topic ARNs for OK state notifications.
    - default_insufficient_data_actions: SNS topic ARNs for insufficient data notifications.
  EOT
  type = object({
    enabled                           = optional(bool, false)
    enable_default_alarms             = optional(bool, true)
    enable_dashboard                  = optional(bool, false)
    default_alarm_actions             = optional(list(string), [])
    default_ok_actions                = optional(list(string), [])
    default_insufficient_data_actions = optional(list(string), [])
  })
  default = {}
}

variable "cloudwatch_metric_alarms" {
  description = "Map of custom CloudWatch metric alarms to create for CodeDeploy."
  type = map(object({
    alarm_description   = optional(string)
    metric_name         = string
    namespace           = optional(string, "AWS/CodeDeploy")
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
