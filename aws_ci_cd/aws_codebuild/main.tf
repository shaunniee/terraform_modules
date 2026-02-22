# =============================================================================
# CodeBuild Project Module
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  create_role     = var.service_role_arn == null
  service_role_arn = local.create_role ? aws_iam_role.this[0].arn : var.service_role_arn

  cloudwatch_log_group = try(var.logs_config.cloudwatch.group_name, "/aws/codebuild/${var.name}")

  # Determine if environment variables reference SSM or Secrets Manager
  has_ssm_vars     = length([for v in var.environment.environment_variables : v if v.type == "PARAMETER_STORE"]) > 0
  has_secrets_vars = length([for v in var.environment.environment_variables : v if v.type == "SECRETS_MANAGER"]) > 0

  # Observability
  observability_enabled  = try(var.observability.enabled, false)
  dashboard_enabled      = local.observability_enabled && try(var.observability.enable_dashboard, false)
  default_alarms_enabled = local.observability_enabled && try(var.observability.enable_default_alarms, true)

  default_alarms = local.default_alarms_enabled ? {
    failed_builds = {
      alarm_description   = "CodeBuild project ${var.name} has failed builds."
      metric_name         = "FailedBuilds"
      namespace           = "AWS/CodeBuild"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = try(var.observability.failed_builds_threshold, 1)
      evaluation_periods  = 1
      period              = 300
      statistic           = "Sum"
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      dimensions          = { ProjectName = var.name }
    }
    build_duration = {
      alarm_description   = "CodeBuild project ${var.name} build duration exceeds threshold."
      metric_name         = "Duration"
      namespace           = "AWS/CodeBuild"
      comparison_operator = "GreaterThanThreshold"
      threshold           = try(var.observability.build_duration_threshold, 3600)
      evaluation_periods  = 1
      period              = 300
      statistic           = "Average"
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      dimensions          = { ProjectName = var.name }
    }
  } : {}

  effective_alarms = merge(local.default_alarms, var.cloudwatch_metric_alarms)
}

# =============================================================================
# IAM Role & Policy
# =============================================================================

resource "aws_iam_role" "this" {
  count = local.create_role ? 1 : 0

  name = "${var.name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
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
    Name = "${var.name}-codebuild-role"
  })
}

resource "aws_iam_role_policy" "this" {
  count = local.create_role ? 1 : 0

  name = "${var.name}-codebuild-policy"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # CloudWatch Logs permissions
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = [
            "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.cloudwatch_log_group}",
            "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.cloudwatch_log_group}:*"
          ]
        }
      ],
      # S3 artifact permissions
      [for _, stmt in {
        s3_artifacts = {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject",
            "s3:GetBucketAcl",
            "s3:GetBucketLocation"
          ]
          Resource = compact([
            var.artifacts.location != null ? "arn:aws:s3:::${var.artifacts.location}" : null,
            var.artifacts.location != null ? "arn:aws:s3:::${var.artifacts.location}/*" : null,
            var.cache.location != null ? "arn:aws:s3:::${split("/", var.cache.location)[0]}" : null,
            var.cache.location != null ? "arn:aws:s3:::${var.cache.location}*" : null,
          ])
        }
      } : stmt if var.artifacts.type == "S3" || var.cache.type == "S3"],
      # CodePipeline artifact bucket permissions (when source/artifacts type is CODEPIPELINE)
      [for _, stmt in {
        codepipeline_artifacts = {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject",
            "s3:GetBucketAcl",
            "s3:GetBucketLocation"
          ]
          Resource = ["*"]
        }
      } : stmt if var.source_config.type == "CODEPIPELINE" || var.artifacts.type == "CODEPIPELINE"],
      # ECR permissions for pulling Docker images
      [
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ]
          Resource = ["*"]
        }
      ],
      # CodeCommit permissions
      [for _, stmt in {
        codecommit = {
          Effect = "Allow"
          Action = [
            "codecommit:GitPull"
          ]
          Resource = ["*"]
        }
      } : stmt if var.source_config.type == "CODECOMMIT"],
      # VPC permissions
      [for _, stmt in {
        vpc_base = {
          Effect = "Allow"
          Action = [
            "ec2:CreateNetworkInterface",
            "ec2:DescribeDhcpOptions",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface",
            "ec2:DescribeSubnets",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeVpcs"
          ]
          Resource = ["*"]
        }
        vpc_permission = {
          Effect = "Allow"
          Action = [
            "ec2:CreateNetworkInterfacePermission"
          ]
          Resource = "arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*"
          Condition = {
            StringEquals = {
              "ec2:AuthorizedService" = "codebuild.amazonaws.com"
              "ec2:Subnet"           = [for s in var.vpc_config.subnets : "arn:aws:ec2:${local.region}:${local.account_id}:subnet/${s}"]
            }
          }
        }
      } : stmt if var.vpc_config != null],
      # KMS permissions
      [for _, stmt in {
        kms = {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ]
          Resource = [var.encryption_key]
        }
      } : stmt if var.encryption_key != null],
      # SSM Parameter Store permissions
      [for _, stmt in {
        ssm = {
          Effect = "Allow"
          Action = [
            "ssm:GetParameters",
            "ssm:GetParameter"
          ]
          Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/*"
        }
      } : stmt if local.has_ssm_vars],
      # Secrets Manager permissions
      [for _, stmt in {
        secrets = {
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue"
          ]
          Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:*"
        }
      } : stmt if local.has_secrets_vars],
      # CodeBuild report group permissions
      [
        {
          Effect = "Allow"
          Action = [
            "codebuild:CreateReportGroup",
            "codebuild:CreateReport",
            "codebuild:UpdateReport",
            "codebuild:BatchPutTestCases",
            "codebuild:BatchPutCodeCoverages"
          ]
          Resource = "arn:aws:codebuild:${local.region}:${local.account_id}:report-group/${var.name}-*"
        }
      ],
      # EFS permissions
      [for _, stmt in {
        efs = {
          Effect = "Allow"
          Action = [
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientRootAccess",
            "elasticfilesystem:ClientWrite",
            "elasticfilesystem:DescribeMountTargets"
          ]
          Resource = ["*"]
        }
      } : stmt if length(var.file_system_locations) > 0],
      # S3 logs permissions
      [for _, stmt in {
        s3_logs = {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetBucketAcl"
          ]
          Resource = [
            "arn:aws:s3:::${split("/", var.logs_config.s3.location)[0]}",
            "arn:aws:s3:::${var.logs_config.s3.location}*"
          ]
        }
      } : stmt if try(var.logs_config.s3.status, "DISABLED") == "ENABLED"]
    )
  })
}

# =============================================================================
# CodeBuild Project
# =============================================================================

resource "aws_codebuild_project" "this" {
  name                   = var.name
  description            = var.description
  build_timeout          = var.build_timeout
  queued_timeout         = var.queued_timeout
  service_role           = local.service_role_arn
  source_version         = var.source_version
  badge_enabled          = var.badge_enabled
  encryption_key         = var.encryption_key
  concurrent_build_limit = var.concurrent_build_limit

  # Source
  source {
    type                = var.source_config.type
    location            = var.source_config.location
    buildspec           = var.source_config.buildspec
    git_clone_depth     = contains(["CODECOMMIT", "GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET"], var.source_config.type) ? var.source_config.git_clone_depth : null
    insecure_ssl        = var.source_config.insecure_ssl
    report_build_status = contains(["GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET"], var.source_config.type) ? var.source_config.report_build_status : null

    dynamic "git_submodules_config" {
      for_each = contains(["CODECOMMIT", "GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET"], var.source_config.type) ? [1] : []
      content {
        fetch_submodules = var.source_config.git_submodules_config
      }
    }
  }

  # Secondary Sources
  dynamic "secondary_sources" {
    for_each = var.secondary_sources
    content {
      source_identifier   = secondary_sources.value.source_identifier
      type                = secondary_sources.value.type
      location            = secondary_sources.value.location
      buildspec           = secondary_sources.value.buildspec
      git_clone_depth     = contains(["CODECOMMIT", "GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET"], secondary_sources.value.type) ? secondary_sources.value.git_clone_depth : null
      insecure_ssl        = secondary_sources.value.insecure_ssl
      report_build_status = contains(["GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET"], secondary_sources.value.type) ? secondary_sources.value.report_build_status : null

      dynamic "git_submodules_config" {
        for_each = contains(["CODECOMMIT", "GITHUB", "GITHUB_ENTERPRISE", "BITBUCKET"], secondary_sources.value.type) ? [1] : []
        content {
          fetch_submodules = secondary_sources.value.git_submodules_config
        }
      }
    }
  }

  # Secondary Source Versions
  dynamic "secondary_source_version" {
    for_each = var.secondary_source_versions
    content {
      source_identifier = secondary_source_version.key
      source_version    = secondary_source_version.value
    }
  }

  # Environment
  environment {
    compute_type                = var.environment.compute_type
    image                       = var.environment.image
    type                        = var.environment.type
    privileged_mode             = var.environment.privileged_mode
    image_pull_credentials_type = var.environment.image_pull_credentials_type
    certificate                 = var.environment.certificate

    dynamic "environment_variable" {
      for_each = var.environment.environment_variables
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  # Artifacts
  artifacts {
    type                   = var.artifacts.type
    location               = var.artifacts.type == "S3" ? var.artifacts.location : null
    name                   = var.artifacts.name
    namespace_type         = var.artifacts.type == "S3" ? var.artifacts.namespace_type : null
    packaging              = var.artifacts.type == "S3" ? var.artifacts.packaging : null
    path                   = var.artifacts.type == "S3" ? var.artifacts.path : null
    encryption_disabled    = var.artifacts.encryption_disabled
    override_artifact_name = var.artifacts.type == "S3" ? var.artifacts.override_artifact_name : null
  }

  # Secondary Artifacts
  dynamic "secondary_artifacts" {
    for_each = var.secondary_artifacts
    content {
      artifact_identifier    = secondary_artifacts.value.artifact_identifier
      type                   = secondary_artifacts.value.type
      location               = secondary_artifacts.value.type == "S3" ? secondary_artifacts.value.location : null
      name                   = secondary_artifacts.value.name
      namespace_type         = secondary_artifacts.value.type == "S3" ? secondary_artifacts.value.namespace_type : null
      packaging              = secondary_artifacts.value.type == "S3" ? secondary_artifacts.value.packaging : null
      path                   = secondary_artifacts.value.type == "S3" ? secondary_artifacts.value.path : null
      encryption_disabled    = secondary_artifacts.value.encryption_disabled
      override_artifact_name = secondary_artifacts.value.type == "S3" ? secondary_artifacts.value.override_artifact_name : null
    }
  }

  # Cache
  dynamic "cache" {
    for_each = var.cache.type != "NO_CACHE" ? [var.cache] : []
    content {
      type     = cache.value.type
      location = cache.value.type == "S3" ? cache.value.location : null
      modes    = cache.value.type == "LOCAL" ? cache.value.modes : null
    }
  }

  # VPC Configuration
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      vpc_id             = vpc_config.value.vpc_id
      subnets            = vpc_config.value.subnets
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  # Logs Configuration
  logs_config {
    cloudwatch_logs {
      group_name  = try(var.logs_config.cloudwatch.group_name, local.cloudwatch_log_group)
      stream_name = try(var.logs_config.cloudwatch.stream_name, null)
      status      = try(var.logs_config.cloudwatch.status, "ENABLED")
    }

    dynamic "s3_logs" {
      for_each = var.logs_config.s3 != null ? [var.logs_config.s3] : []
      content {
        location            = s3_logs.value.location
        status              = s3_logs.value.status
        encryption_disabled = s3_logs.value.encryption_disabled
      }
    }
  }

  # File System Locations (EFS)
  dynamic "file_system_locations" {
    for_each = var.file_system_locations
    content {
      identifier    = file_system_locations.value.identifier
      location      = file_system_locations.value.location
      mount_point   = file_system_locations.value.mount_point
      mount_options = file_system_locations.value.mount_options
      type          = file_system_locations.value.type
    }
  }

  # Build Batch Configuration
  dynamic "build_batch_config" {
    for_each = var.build_batch_config != null ? [var.build_batch_config] : []
    content {
      service_role    = coalesce(build_batch_config.value.service_role, local.service_role_arn)
      combine_artifacts = build_batch_config.value.combine_artifacts
      timeout_in_mins   = build_batch_config.value.timeout_in_mins

      restrictions {
        compute_types_allowed  = build_batch_config.value.restrictions.compute_types_allowed
        maximum_builds_allowed = build_batch_config.value.restrictions.maximum_builds_allowed
      }
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

# =============================================================================
# Webhooks
# =============================================================================

resource "aws_codebuild_webhook" "this" {
  for_each = { for idx, wh in var.webhooks : idx => wh }

  project_name = aws_codebuild_project.this.name
  build_type   = each.value.build_type

  dynamic "filter_group" {
    for_each = each.value.filter_groups
    content {
      dynamic "filter" {
        for_each = filter_group.value
        content {
          type                    = filter.value.type
          pattern                 = filter.value.pattern
          exclude_matched_pattern = filter.value.exclude_matched_pattern
        }
      }
    }
  }
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.effective_alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = try(each.value.alarm_description, "Alarm for ${var.name} - ${each.key}")
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/CodeBuild")
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = try(each.value.evaluation_periods, 1)
  period              = try(each.value.period, 300)
  statistic           = try(each.value.statistic, "Sum")
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")

  alarm_actions = try(each.value.alarm_actions, try(var.observability.default_alarm_actions, []))
  ok_actions    = try(each.value.ok_actions, try(var.observability.default_ok_actions, []))
  insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])

  dimensions = try(each.value.dimensions, { ProjectName = var.name })

  tags = var.tags
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = "${var.name}-codebuild"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Build Results"
          metrics = [
            ["AWS/CodeBuild", "SucceededBuilds", "ProjectName", var.name, { stat = "Sum", color = "#2ca02c" }],
            [".", "FailedBuilds", ".", ".", { stat = "Sum", color = "#d62728" }]
          ]
          period = 300
          region = local.region
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
          title   = "Build Duration"
          metrics = [
            ["AWS/CodeBuild", "Duration", "ProjectName", var.name, { stat = "Average" }],
            [".", ".", ".", ".", { stat = "p90" }]
          ]
          period = 300
          region = local.region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Build Counts"
          metrics = [
            ["AWS/CodeBuild", "Builds", "ProjectName", var.name, { stat = "Sum" }]
          ]
          period = 300
          region = local.region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Download & Upload Source Duration"
          metrics = [
            ["AWS/CodeBuild", "DownloadSourceDuration", "ProjectName", var.name, { stat = "Average" }],
            [".", "UploadArtifactsDuration", ".", ".", { stat = "Average" }]
          ]
          period = 300
          region = local.region
          view   = "timeSeries"
        }
      }
    ]
  })
}
