# =============================================================================
# CodePipeline Module
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  create_role      = var.service_role_arn == null
  service_role_arn = local.create_role ? aws_iam_role.this[0].arn : var.service_role_arn

  # Detect which providers are used in actions to scope IAM permissions
  all_actions    = flatten([for stage in var.stages : stage.actions])
  providers_used = toset([for action in local.all_actions : action.provider])

  has_codecommit     = contains(local.providers_used, "CodeCommit")
  has_codebuild      = contains(local.providers_used, "CodeBuild")
  has_codedeploy     = contains(local.providers_used, "CodeDeploy")
  has_s3_source      = contains(local.providers_used, "S3")
  has_ecr_source     = contains(local.providers_used, "ECR")
  has_ecs_deploy     = contains(local.providers_used, "ECS")
  has_lambda         = contains(local.providers_used, "Lambda")
  has_cloudformation = contains(local.providers_used, "CloudFormation") || contains(local.providers_used, "CloudFormationStackSet")
  has_codestar       = contains(local.providers_used, "CodeStarSourceConnection")
  has_approval       = contains(local.providers_used, "Manual")
  has_elastic_beanstalk = contains(local.providers_used, "ElasticBeanstalk")

  # Observability
  observability_enabled  = try(var.observability.enabled, false)
  dashboard_enabled      = local.observability_enabled && try(var.observability.enable_dashboard, false)
  default_alarms_enabled = local.observability_enabled && try(var.observability.enable_default_alarms, true)
  event_notifications    = local.observability_enabled && try(var.observability.enable_event_notifications, false)

  default_alarms = local.default_alarms_enabled ? {
    pipeline_execution_failed = {
      alarm_description   = "CodePipeline ${var.name} has failed executions."
      metric_name         = "PipelineExecutionFailedCount"
      namespace           = "AWS/CodePipeline"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = try(var.observability.failed_executions_threshold, 1)
      evaluation_periods  = 1
      period              = 300
      statistic           = "Sum"
      treat_missing_data  = "notBreaching"
      alarm_actions       = try(var.observability.default_alarm_actions, [])
      ok_actions          = try(var.observability.default_ok_actions, [])
      dimensions          = { PipelineName = var.name }
    }
  } : {}

  effective_alarms = merge(local.default_alarms, var.cloudwatch_metric_alarms)
}

# =============================================================================
# IAM Role & Policy
# =============================================================================

resource "aws_iam_role" "this" {
  count = local.create_role ? 1 : 0

  name = "${var.name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
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
    Name = "${var.name}-codepipeline-role"
  })
}

resource "aws_iam_role_policy" "this" {
  count = local.create_role ? 1 : 0

  name = "${var.name}-codepipeline-policy"
  role = aws_iam_role.this[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # S3 artifact store permissions (always needed)
      [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:GetBucketVersioning",
            "s3:PutObjectAcl",
            "s3:PutObject"
          ]
          Resource = [
            "arn:aws:s3:::${var.artifact_store.location}",
            "arn:aws:s3:::${var.artifact_store.location}/*"
          ]
        }
      ],
      # KMS permissions for artifact encryption
      var.artifact_store.encryption_key_id != null ? [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ]
          Resource = [var.artifact_store.encryption_key_id]
        }
      ] : [],
      # CodeCommit permissions
      local.has_codecommit ? [
        {
          Effect = "Allow"
          Action = [
            "codecommit:CancelUploadArchive",
            "codecommit:GetBranch",
            "codecommit:GetCommit",
            "codecommit:GetRepository",
            "codecommit:GetUploadArchiveStatus",
            "codecommit:UploadArchive"
          ]
          Resource = ["*"]
        }
      ] : [],
      # CodeBuild permissions
      local.has_codebuild ? [
        {
          Effect = "Allow"
          Action = [
            "codebuild:BatchGetBuilds",
            "codebuild:StartBuild",
            "codebuild:BatchGetBuildBatches",
            "codebuild:StartBuildBatch"
          ]
          Resource = ["*"]
        }
      ] : [],
      # CodeDeploy permissions
      local.has_codedeploy ? [
        {
          Effect = "Allow"
          Action = [
            "codedeploy:CreateDeployment",
            "codedeploy:GetApplication",
            "codedeploy:GetApplicationRevision",
            "codedeploy:GetDeployment",
            "codedeploy:GetDeploymentConfig",
            "codedeploy:RegisterApplicationRevision"
          ]
          Resource = ["*"]
        }
      ] : [],
      # S3 source permissions
      local.has_s3_source ? [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:GetBucketVersioning",
            "s3:PutObject"
          ]
          Resource = ["*"]
        }
      ] : [],
      # ECR permissions
      local.has_ecr_source ? [
        {
          Effect = "Allow"
          Action = [
            "ecr:DescribeImages",
            "ecr:GetAuthorizationToken",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer"
          ]
          Resource = ["*"]
        }
      ] : [],
      # ECS permissions
      local.has_ecs_deploy ? [
        {
          Effect = "Allow"
          Action = [
            "ecs:DescribeServices",
            "ecs:DescribeTaskDefinition",
            "ecs:DescribeTasks",
            "ecs:ListTasks",
            "ecs:RegisterTaskDefinition",
            "ecs:UpdateService",
            "ecs:TagResource"
          ]
          Resource = ["*"]
        }
      ] : [],
      # Lambda permissions
      local.has_lambda ? [
        {
          Effect = "Allow"
          Action = [
            "lambda:InvokeFunction",
            "lambda:ListFunctions",
            "lambda:GetFunction",
            "lambda:UpdateFunctionCode"
          ]
          Resource = ["*"]
        }
      ] : [],
      # CloudFormation permissions
      local.has_cloudformation ? [
        {
          Effect = "Allow"
          Action = [
            "cloudformation:CreateStack",
            "cloudformation:DeleteStack",
            "cloudformation:DescribeStacks",
            "cloudformation:UpdateStack",
            "cloudformation:CreateChangeSet",
            "cloudformation:DeleteChangeSet",
            "cloudformation:DescribeChangeSet",
            "cloudformation:ExecuteChangeSet",
            "cloudformation:SetStackPolicy",
            "cloudformation:ValidateTemplate"
          ]
          Resource = ["*"]
        }
      ] : [],
      # CodeStar Connections
      local.has_codestar ? [
        {
          Effect = "Allow"
          Action = [
            "codestar-connections:UseConnection"
          ]
          Resource = ["*"]
        }
      ] : [],
      # Approval / SNS permissions
      local.has_approval ? [
        {
          Effect = "Allow"
          Action = [
            "sns:Publish"
          ]
          Resource = ["*"]
        }
      ] : [],
      # Elastic Beanstalk permissions
      local.has_elastic_beanstalk ? [
        {
          Effect = "Allow"
          Action = [
            "elasticbeanstalk:CreateApplicationVersion",
            "elasticbeanstalk:DescribeApplicationVersions",
            "elasticbeanstalk:DescribeEnvironments",
            "elasticbeanstalk:DescribeEvents",
            "elasticbeanstalk:UpdateEnvironment"
          ]
          Resource = ["*"]
        }
      ] : [],
      # IAM PassRole (needed for ECS, CloudFormation, Elastic Beanstalk)
      local.has_ecs_deploy || local.has_cloudformation || local.has_elastic_beanstalk ? [
        {
          Effect = "Allow"
          Action = [
            "iam:PassRole"
          ]
          Resource = ["*"]
          Condition = {
            StringEqualsIfExists = {
              "iam:PassedToService" = compact([
                local.has_ecs_deploy ? "ecs-tasks.amazonaws.com" : "",
                local.has_cloudformation ? "cloudformation.amazonaws.com" : "",
                local.has_elastic_beanstalk ? "elasticbeanstalk.amazonaws.com" : ""
              ])
            }
          }
        }
      ] : []
    )
  })
}

# =============================================================================
# CodePipeline
# =============================================================================

resource "aws_codepipeline" "this" {
  name          = var.name
  role_arn      = local.service_role_arn
  pipeline_type = var.pipeline_type
  execution_mode = var.pipeline_type == "V2" ? var.execution_mode : "SUPERSEDED"

  # Primary artifact store
  artifact_store {
    location = var.artifact_store.location
    type     = var.artifact_store.type
    region   = var.artifact_store.region

    dynamic "encryption_key" {
      for_each = var.artifact_store.encryption_key_id != null ? [1] : []
      content {
        id   = var.artifact_store.encryption_key_id
        type = var.artifact_store.encryption_key_type
      }
    }
  }

  # Additional artifact stores for cross-region
  dynamic "artifact_store" {
    for_each = var.additional_artifact_stores
    content {
      location = artifact_store.value.location
      type     = artifact_store.value.type
      region   = artifact_store.key

      dynamic "encryption_key" {
        for_each = artifact_store.value.encryption_key_id != null ? [1] : []
        content {
          id   = artifact_store.value.encryption_key_id
          type = artifact_store.value.encryption_key_type
        }
      }
    }
  }

  # Stages
  dynamic "stage" {
    for_each = var.stages
    content {
      name = stage.value.name

      dynamic "action" {
        for_each = stage.value.actions
        content {
          name             = action.value.name
          category         = action.value.category
          owner            = action.value.owner
          provider         = action.value.provider
          version          = action.value.version
          input_artifacts  = action.value.input_artifacts
          output_artifacts = action.value.output_artifacts
          configuration    = action.value.configuration
          run_order        = action.value.run_order
          region           = action.value.region
          namespace        = action.value.namespace
          role_arn         = action.value.role_arn
        }
      }
    }
  }

  # V2 Triggers
  dynamic "trigger" {
    for_each = var.pipeline_type == "V2" ? var.triggers : []
    content {
      provider_type = trigger.value.provider_type

      git_configuration {
        source_action_name = trigger.value.git_configuration.source_action_name

        dynamic "push" {
          for_each = trigger.value.git_configuration.push
          content {
            dynamic "tags" {
              for_each = push.value.tags != null ? [push.value.tags] : []
              content {
                includes = tags.value.includes
                excludes = tags.value.excludes
              }
            }
            dynamic "branches" {
              for_each = push.value.branches != null ? [push.value.branches] : []
              content {
                includes = branches.value.includes
                excludes = branches.value.excludes
              }
            }
            dynamic "file_paths" {
              for_each = push.value.file_paths != null ? [push.value.file_paths] : []
              content {
                includes = file_paths.value.includes
                excludes = file_paths.value.excludes
              }
            }
          }
        }

        dynamic "pull_request" {
          for_each = trigger.value.git_configuration.pull_request
          content {
            events = pull_request.value.events

            dynamic "branches" {
              for_each = pull_request.value.branches != null ? [pull_request.value.branches] : []
              content {
                includes = branches.value.includes
                excludes = branches.value.excludes
              }
            }
            dynamic "file_paths" {
              for_each = pull_request.value.file_paths != null ? [pull_request.value.file_paths] : []
              content {
                includes = file_paths.value.includes
                excludes = file_paths.value.excludes
              }
            }
          }
        }
      }
    }
  }

  # V2 Pipeline Variables
  dynamic "variable" {
    for_each = var.pipeline_type == "V2" ? var.variables : []
    content {
      name          = variable.value.name
      default_value = variable.value.default_value
      description   = variable.value.description
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.effective_alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = try(each.value.alarm_description, "Alarm for ${var.name} - ${each.key}")
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/CodePipeline")
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = try(each.value.evaluation_periods, 1)
  period              = try(each.value.period, 300)
  statistic           = try(each.value.statistic, "Sum")
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")

  alarm_actions = try(each.value.alarm_actions, try(var.observability.default_alarm_actions, []))
  ok_actions    = try(each.value.ok_actions, try(var.observability.default_ok_actions, []))
  insufficient_data_actions = try(var.observability.default_insufficient_data_actions, [])

  dimensions = try(each.value.dimensions, { PipelineName = var.name })

  tags = var.tags
}

# =============================================================================
# EventBridge Rule for Pipeline Notifications
# =============================================================================

resource "aws_cloudwatch_event_rule" "pipeline_notifications" {
  count = local.event_notifications ? 1 : 0

  name        = "${var.name}-pipeline-state-change"
  description = "Capture pipeline state changes for ${var.name}"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [var.name]
      state    = ["FAILED", "SUCCEEDED", "CANCELED"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "pipeline_notifications" {
  count = local.event_notifications && try(var.observability.notification_sns_topic_arn, null) != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.pipeline_notifications[0].name
  target_id = "${var.name}-sns-notification"
  arn       = var.observability.notification_sns_topic_arn
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "this" {
  count = local.dashboard_enabled ? 1 : 0

  dashboard_name = "${var.name}-codepipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Pipeline Execution Results"
          metrics = [
            ["AWS/CodePipeline", "PipelineExecutionSucceededCount", "PipelineName", var.name, { stat = "Sum", color = "#2ca02c" }],
            [".", "PipelineExecutionFailedCount", ".", ".", { stat = "Sum", color = "#d62728" }]
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
          title   = "Pipeline Execution Time"
          metrics = [
            ["AWS/CodePipeline", "PipelineExecutionTime", "PipelineName", var.name, { stat = "Average" }],
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
        width  = 24
        height = 6
        properties = {
          title = "Stage Execution Results"
          metrics = [
            for stage in var.stages : [
              "AWS/CodePipeline", "StageExecutionSucceededCount", "PipelineName", var.name, "StageName", stage.name, { stat = "Sum" }
            ]
          ]
          period = 300
          region = local.region
          view   = "timeSeries"
        }
      }
    ]
  })
}
