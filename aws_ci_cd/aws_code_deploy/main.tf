# =============================================================================
# CodeDeploy Module
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  create_role      = var.service_role_arn == null
  service_role_arn = local.create_role ? aws_iam_role.this[0].arn : var.service_role_arn

  # Select the correct managed policy based on compute platform
  managed_policy_arn = {
    Server = "arn:aws:iam::aws:policy/AWSCodeDeployRole"
    ECS    = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
    Lambda = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForLambda"
  }[var.compute_platform]

  # Observability
  observability_enabled  = try(var.observability.enabled, false)
  dashboard_enabled      = local.observability_enabled && try(var.observability.enable_dashboard, false)
  default_alarms_enabled = local.observability_enabled && try(var.observability.enable_default_alarms, true)

  default_alarms = local.default_alarms_enabled ? {
    deployment_failures = {
      alarm_description   = "CodeDeploy application ${var.application_name} has deployment failures."
      metric_name         = "DeploymentFailure"
      namespace           = "AWS/CodeDeploy"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 1
      evaluation_periods  = 1
      period              = 300
      statistic           = "Sum"
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      dimensions          = {}
    }
  } : {}

  effective_alarms = merge(local.default_alarms, var.cloudwatch_metric_alarms)
}

# =============================================================================
# IAM Role
# =============================================================================

resource "aws_iam_role" "this" {
  count = local.create_role ? 1 : 0

  name = "${var.application_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.application_name}-codedeploy-role"
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  count = local.create_role ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = local.managed_policy_arn
}

# =============================================================================
# CodeDeploy Application
# =============================================================================

resource "aws_codedeploy_app" "this" {
  name             = var.application_name
  compute_platform = var.compute_platform

  tags = merge(var.tags, {
    Name = var.application_name
  })
}

# =============================================================================
# Custom Deployment Configurations
# =============================================================================

resource "aws_codedeploy_deployment_config" "this" {
  for_each = var.custom_deployment_configs

  deployment_config_name = each.key
  compute_platform       = coalesce(each.value.compute_platform, var.compute_platform)

  dynamic "minimum_healthy_hosts" {
    for_each = each.value.minimum_healthy_hosts != null ? [each.value.minimum_healthy_hosts] : []
    content {
      type  = minimum_healthy_hosts.value.type
      value = minimum_healthy_hosts.value.value
    }
  }

  dynamic "traffic_routing_config" {
    for_each = each.value.traffic_routing_config != null ? [each.value.traffic_routing_config] : []
    content {
      type = traffic_routing_config.value.type

      dynamic "time_based_canary" {
        for_each = traffic_routing_config.value.time_based_canary != null ? [traffic_routing_config.value.time_based_canary] : []
        content {
          interval   = time_based_canary.value.interval
          percentage = time_based_canary.value.percentage
        }
      }

      dynamic "time_based_linear" {
        for_each = traffic_routing_config.value.time_based_linear != null ? [traffic_routing_config.value.time_based_linear] : []
        content {
          interval   = time_based_linear.value.interval
          percentage = time_based_linear.value.percentage
        }
      }
    }
  }
}

# =============================================================================
# Deployment Groups
# =============================================================================

resource "aws_codedeploy_deployment_group" "this" {
  for_each = var.deployment_groups

  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = each.key
  service_role_arn       = local.service_role_arn
  deployment_config_name = each.value.deployment_config_name
  autoscaling_groups     = each.value.autoscaling_groups
  outdated_instances_strategy = each.value.outdated_instances_strategy

  # Deployment Style
  deployment_style {
    deployment_type   = each.value.deployment_type
    deployment_option = each.value.load_balancer_info != null ? "WITH_TRAFFIC_CONTROL" : "WITHOUT_TRAFFIC_CONTROL"
  }

  # EC2 Tag Filters
  dynamic "ec2_tag_filter" {
    for_each = each.value.ec2_tag_filters
    content {
      key   = ec2_tag_filter.value.key
      value = ec2_tag_filter.value.value
      type  = ec2_tag_filter.value.type
    }
  }

  # EC2 Tag Sets
  dynamic "ec2_tag_set" {
    for_each = each.value.ec2_tag_set
    content {
      dynamic "ec2_tag_filter" {
        for_each = ec2_tag_set.value
        content {
          key   = ec2_tag_filter.value.key
          value = ec2_tag_filter.value.value
          type  = ec2_tag_filter.value.type
        }
      }
    }
  }

  # ECS Service
  dynamic "ecs_service" {
    for_each = each.value.ecs_service != null ? [each.value.ecs_service] : []
    content {
      cluster_name = ecs_service.value.cluster_name
      service_name = ecs_service.value.service_name
    }
  }

  # Load Balancer Info
  dynamic "load_balancer_info" {
    for_each = each.value.load_balancer_info != null ? [each.value.load_balancer_info] : []
    content {
      dynamic "elb_info" {
        for_each = load_balancer_info.value.elb_info
        content {
          name = elb_info.value.name
        }
      }

      dynamic "target_group_info" {
        for_each = load_balancer_info.value.target_group_info
        content {
          name = target_group_info.value.name
        }
      }

      dynamic "target_group_pair_info" {
        for_each = load_balancer_info.value.target_group_pair_info != null ? [load_balancer_info.value.target_group_pair_info] : []
        content {
          dynamic "target_group" {
            for_each = target_group_pair_info.value.target_groups
            content {
              name = target_group.value.name
            }
          }

          prod_traffic_route {
            listener_arns = target_group_pair_info.value.prod_traffic_route.listener_arns
          }

          dynamic "test_traffic_route" {
            for_each = target_group_pair_info.value.test_traffic_route != null ? [target_group_pair_info.value.test_traffic_route] : []
            content {
              listener_arns = test_traffic_route.value.listener_arns
            }
          }
        }
      }
    }
  }

  # Blue/Green Deployment Config
  dynamic "blue_green_deployment_config" {
    for_each = each.value.blue_green_deployment_config != null ? [each.value.blue_green_deployment_config] : []
    content {
      dynamic "deployment_ready_option" {
        for_each = blue_green_deployment_config.value.deployment_ready_option != null ? [blue_green_deployment_config.value.deployment_ready_option] : []
        content {
          action_on_timeout    = deployment_ready_option.value.action_on_timeout
          wait_time_in_minutes = deployment_ready_option.value.wait_time_in_minutes
        }
      }

      dynamic "green_fleet_provisioning_option" {
        for_each = blue_green_deployment_config.value.green_fleet_provisioning_option != null ? [blue_green_deployment_config.value.green_fleet_provisioning_option] : []
        content {
          action = green_fleet_provisioning_option.value.action
        }
      }

      dynamic "terminate_blue_instances_on_deployment_success" {
        for_each = blue_green_deployment_config.value.terminate_blue_instances_on_deployment_success != null ? [blue_green_deployment_config.value.terminate_blue_instances_on_deployment_success] : []
        content {
          action                           = terminate_blue_instances_on_deployment_success.value.action
          termination_wait_time_in_minutes = terminate_blue_instances_on_deployment_success.value.termination_wait_time_in_minutes
        }
      }
    }
  }

  # Auto Rollback
  dynamic "auto_rollback_configuration" {
    for_each = each.value.auto_rollback_configuration != null ? [each.value.auto_rollback_configuration] : []
    content {
      enabled = auto_rollback_configuration.value.enabled
      events  = auto_rollback_configuration.value.events
    }
  }

  # Alarm Configuration
  dynamic "alarm_configuration" {
    for_each = each.value.alarm_configuration != null ? [each.value.alarm_configuration] : []
    content {
      enabled                  = alarm_configuration.value.enabled
      alarms                   = alarm_configuration.value.alarms
      ignore_poll_alarm_failure = alarm_configuration.value.ignore_poll_alarm_failure
    }
  }

  # Trigger Configuration
  dynamic "trigger_configuration" {
    for_each = each.value.trigger_configuration
    content {
      trigger_name       = trigger_configuration.value.trigger_name
      trigger_target_arn = trigger_configuration.value.trigger_target_arn
      trigger_events     = trigger_configuration.value.trigger_events
    }
  }

  # On-Premises Tag Filters
  dynamic "on_premises_instance_tag_filter" {
    for_each = each.value.on_premises_tag_filters
    content {
      key   = on_premises_instance_tag_filter.value.key
      value = on_premises_instance_tag_filter.value.value
      type  = on_premises_instance_tag_filter.value.type
    }
  }

  tags = merge(var.tags, {
    Name = each.key
  })

  depends_on = [aws_codedeploy_deployment_config.this]
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.effective_alarms

  alarm_name          = "${var.application_name}-${each.key}"
  alarm_description   = try(each.value.alarm_description, "Alarm for ${var.application_name} - ${each.key}")
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/CodeDeploy")
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = try(each.value.evaluation_periods, 1)
  period              = try(each.value.period, 300)
  statistic           = try(each.value.statistic, "Sum")
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")

  alarm_actions = try(each.value.alarm_actions, try(var.observability.default_alarm_actions, []))
  ok_actions    = try(each.value.ok_actions, try(var.observability.default_ok_actions, []))
  insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])

  dimensions = try(each.value.dimensions, {})

  tags = var.tags
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = "${var.application_name}-codedeploy"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Deployment Results"
          metrics = [
            ["AWS/CodeDeploy", "DeploymentSuccess", { stat = "Sum", color = "#2ca02c" }],
            [".", "DeploymentFailure", { stat = "Sum", color = "#d62728" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Deployment Duration"
          metrics = [
            ["AWS/CodeDeploy", "DeploymentDuration", { stat = "Average" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      }
    ]
  })
}
