# =============================================================================
# AWS CI/CD Parent Module
# =============================================================================
#
# Orchestrates CodeBuild, CodePipeline, and CodeDeploy with shared
# infrastructure including S3 artifact bucket and optional KMS encryption.
#
# Usage Examples:
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 1: Simple GitHub → CodeBuild → S3 Deploy                       │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "ci_cd" {                                                      │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "my-app"                                                   │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = {                                               │
# │          type     = "CODEPIPELINE"                                     │
# │          buildspec = "buildspec.yml"                                   │
# │        }                                                               │
# │        artifacts = { type = "CODEPIPELINE" }                           │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      stages = [                                                        │
# │        {                                                               │
# │          name = "Source"                                                │
# │          actions = [{                                                  │
# │            name     = "GitHub"                                         │
# │            category = "Source"                                         │
# │            owner    = "AWS"                                            │
# │            provider = "CodeStarSourceConnection"                       │
# │            configuration = {                                           │
# │              ConnectionArn    = "arn:aws:..."                          │
# │              FullRepositoryId = "owner/repo"                           │
# │              BranchName       = "main"                                 │
# │            }                                                           │
# │            output_artifacts = ["source_output"]                        │
# │          }]                                                            │
# │        },                                                              │
# │        {                                                               │
# │          name = "Build"                                                │
# │          actions = [{                                                  │
# │            name     = "Build"                                          │
# │            category = "Build"                                          │
# │            owner    = "AWS"                                            │
# │            provider = "CodeBuild"                                      │
# │            configuration = { ProjectName = "my-app-build" }            │
# │            input_artifacts  = ["source_output"]                        │
# │            output_artifacts = ["build_output"]                         │
# │          }]                                                            │
# │        },                                                              │
# │        {                                                               │
# │          name = "Deploy"                                               │
# │          actions = [{                                                  │
# │            name     = "S3Deploy"                                       │
# │            category = "Deploy"                                         │
# │            owner    = "AWS"                                            │
# │            provider = "S3"                                             │
# │            configuration = {                                           │
# │              BucketName = "my-deploy-bucket"                           │
# │              Extract    = "true"                                       │
# │            }                                                           │
# │            input_artifacts = ["build_output"]                          │
# │          }]                                                            │
# │        }                                                               │
# │      ]                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    tags = { Environment = "production" }                               │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 2: CodeCommit → CodeBuild → CodeDeploy (EC2)                   │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "ci_cd" {                                                      │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "my-ec2-app"                                               │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = {                                               │
# │          type      = "CODEPIPELINE"                                    │
# │          buildspec = "buildspec.yml"                                   │
# │        }                                                               │
# │        artifacts = { type = "CODEPIPELINE" }                           │
# │        environment = {                                                 │
# │          compute_type = "BUILD_GENERAL1_MEDIUM"                        │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codedeploy = {                                                      │
# │      deployment_groups = {                                             │
# │        production = {                                                  │
# │          ec2_tag_filters = [                                           │
# │            { key = "Environment", value = "production", type = "KEY_AND_VALUE" }│
# │          ]                                                             │
# │          auto_rollback_configuration = {                               │
# │            enabled = true                                              │
# │            events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]│
# │          }                                                             │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      stages = [                                                        │
# │        {                                                               │
# │          name = "Source"                                                │
# │          actions = [{                                                  │
# │            name     = "CodeCommit"                                     │
# │            category = "Source"                                         │
# │            owner    = "AWS"                                            │
# │            provider = "CodeCommit"                                     │
# │            configuration = {                                           │
# │              RepositoryName = "my-repo"                                │
# │              BranchName     = "main"                                   │
# │            }                                                           │
# │            output_artifacts = ["source_output"]                        │
# │          }]                                                            │
# │        },                                                              │
# │        {                                                               │
# │          name = "Build"                                                │
# │          actions = [{                                                  │
# │            name     = "Build"                                          │
# │            category = "Build"                                          │
# │            owner    = "AWS"                                            │
# │            provider = "CodeBuild"                                      │
# │            configuration = { ProjectName = "my-ec2-app-build" }        │
# │            input_artifacts  = ["source_output"]                        │
# │            output_artifacts = ["build_output"]                         │
# │          }]                                                            │
# │        },                                                              │
# │        {                                                               │
# │          name = "Deploy"                                               │
# │          actions = [{                                                  │
# │            name     = "Deploy"                                         │
# │            category = "Deploy"                                         │
# │            owner    = "AWS"                                            │
# │            provider = "CodeDeploy"                                     │
# │            configuration = {                                           │
# │              ApplicationName     = "my-ec2-app"                        │
# │              DeploymentGroupName = "production"                        │
# │            }                                                           │
# │            input_artifacts = ["build_output"]                          │
# │          }]                                                            │
# │        }                                                               │
# │      ]                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    tags = { Environment = "production", Team = "backend" }             │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 3: Docker → ECS Blue/Green Deploy                              │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "ci_cd" {                                                      │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "my-ecs-app"                                               │
# │    create_kms_key = true                                               │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = {                                               │
# │          type      = "CODEPIPELINE"                                    │
# │          buildspec = "buildspec.yml"                                   │
# │        }                                                               │
# │        artifacts = { type = "CODEPIPELINE" }                           │
# │        environment = {                                                 │
# │          compute_type    = "BUILD_GENERAL1_MEDIUM"                     │
# │          privileged_mode = true                                        │
# │          environment_variables = [                                     │
# │            { name = "ECR_REPO", value = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app", type = "PLAINTEXT" },│
# │            { name = "DOCKER_PASSWORD", value = "/docker/password", type = "PARAMETER_STORE" }│
# │          ]                                                             │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codedeploy = {                                                      │
# │      compute_platform = "ECS"                                          │
# │      deployment_groups = {                                             │
# │        ecs-production = {                                              │
# │          deployment_type        = "BLUE_GREEN"                         │
# │          deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"     │
# │          ecs_service = {                                               │
# │            cluster_name = "my-cluster"                                 │
# │            service_name = "my-service"                                 │
# │          }                                                             │
# │          load_balancer_info = {                                        │
# │            target_group_pair_info = {                                  │
# │              target_groups = [                                         │
# │                { name = "blue-tg" },                                   │
# │                { name = "green-tg" }                                   │
# │              ]                                                         │
# │              prod_traffic_route = {                                    │
# │                listener_arns = ["arn:aws:elasticloadbalancing:..."]    │
# │              }                                                         │
# │              test_traffic_route = {                                    │
# │                listener_arns = ["arn:aws:elasticloadbalancing:..."]    │
# │              }                                                         │
# │            }                                                           │
# │          }                                                             │
# │          blue_green_deployment_config = {                              │
# │            terminate_blue_instances_on_deployment_success = {          │
# │              action                           = "TERMINATE"            │
# │              termination_wait_time_in_minutes = 5                      │
# │            }                                                           │
# │          }                                                             │
# │          auto_rollback_configuration = {                               │
# │            enabled = true                                              │
# │            events  = ["DEPLOYMENT_FAILURE"]                            │
# │          }                                                             │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      stages = [                                                        │
# │        { name = "Source", actions = [{ ... }] },                       │
# │        { name = "Build",  actions = [{ ... }] },                       │
# │        { name = "Deploy", actions = [{                                 │
# │            name     = "ECS-Deploy"                                     │
# │            category = "Deploy"                                         │
# │            owner    = "AWS"                                            │
# │            provider = "CodeDeployToECS"                                │
# │            configuration = {                                           │
# │              ApplicationName                = "my-ecs-app"             │
# │              DeploymentGroupName            = "ecs-production"         │
# │              TaskDefinitionTemplateArtifact = "build_output"           │
# │              AppSpecTemplateArtifact        = "build_output"           │
# │            }                                                           │
# │            input_artifacts = ["build_output"]                          │
# │        }] }                                                            │
# │      ]                                                                 │
# │    }                                                                   │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 4: Multi-Environment with Manual Approval                      │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "ci_cd" {                                                      │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "my-app"                                                   │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = { type = "CODEPIPELINE" }                       │
# │        artifacts      = { type = "CODEPIPELINE" }                      │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codedeploy = {                                                      │
# │      deployment_groups = {                                             │
# │        staging = {                                                     │
# │          ec2_tag_filters = [                                           │
# │            { key = "Environment", value = "staging" }                  │
# │          ]                                                             │
# │        }                                                               │
# │        production = {                                                  │
# │          deployment_config_name = "CodeDeployDefault.OneAtATime"       │
# │          ec2_tag_filters = [                                           │
# │            { key = "Environment", value = "production" }               │
# │          ]                                                             │
# │          auto_rollback_configuration = {                               │
# │            enabled = true                                              │
# │            events  = ["DEPLOYMENT_FAILURE","DEPLOYMENT_STOP_ON_ALARM"] │
# │          }                                                             │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      stages = [                                                        │
# │        { name = "Source",   actions = [{ ... }] },                     │
# │        { name = "Build",    actions = [{ ... }] },                     │
# │        { name = "Staging",  actions = [{                               │
# │            name = "Deploy-Staging", category = "Deploy",               │
# │            owner = "AWS", provider = "CodeDeploy",                     │
# │            configuration = {                                           │
# │              ApplicationName     = "my-app"                            │
# │              DeploymentGroupName = "staging"                           │
# │            },                                                          │
# │            input_artifacts = ["build_output"]                          │
# │        }] },                                                           │
# │        { name = "Approval", actions = [{                               │
# │            name = "ManualApproval", category = "Approval",             │
# │            owner = "AWS", provider = "Manual",                         │
# │            configuration = {                                           │
# │              NotificationArn = "arn:aws:sns:..."                       │
# │              CustomData      = "Approve production deployment?"        │
# │            }                                                           │
# │        }] },                                                           │
# │        { name = "Production", actions = [{                             │
# │            name = "Deploy-Production", category = "Deploy",            │
# │            owner = "AWS", provider = "CodeDeploy",                     │
# │            configuration = {                                           │
# │              ApplicationName     = "my-app"                            │
# │              DeploymentGroupName = "production"                        │
# │            },                                                          │
# │            input_artifacts = ["build_output"]                          │
# │        }] }                                                            │
# │      ]                                                                 │
# │    }                                                                   │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 5: Lambda Deployment                                           │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "ci_cd" {                                                      │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "lambda-app"                                               │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = { type = "CODEPIPELINE" }                       │
# │        artifacts      = { type = "CODEPIPELINE" }                      │
# │        environment = {                                                 │
# │          compute_type = "BUILD_LAMBDA_1GB"                             │
# │          image        = "aws/codebuild/amazonlinux-aarch64-lambda-standard:python3.12"│
# │          type         = "ARM_LAMBDA_CONTAINER"                         │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codedeploy = {                                                      │
# │      compute_platform = "Lambda"                                       │
# │      deployment_groups = {                                             │
# │        production = {                                                  │
# │          deployment_config_name = "CodeDeployDefault.LambdaCanary10Percent5Minutes"│
# │          auto_rollback_configuration = {                               │
# │            enabled = true                                              │
# │            events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]│
# │          }                                                             │
# │        }                                                               │
# │      }                                                                 │
# │      custom_deployment_configs = {                                     │
# │        "LambdaCanary20Percent10Min" = {                                │
# │          traffic_routing_config = {                                    │
# │            type = "TimeBasedCanary"                                    │
# │            time_based_canary = {                                       │
# │              interval   = 10                                           │
# │              percentage = 20                                           │
# │            }                                                           │
# │          }                                                             │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      stages = [                                                        │
# │        { name = "Source", actions = [{ ... }] },                       │
# │        { name = "Build",  actions = [{ ... }] },                       │
# │        { name = "Deploy", actions = [{                                 │
# │            name = "Lambda-Deploy", category = "Deploy",                │
# │            owner = "AWS", provider = "CodeDeploy",                     │
# │            configuration = {                                           │
# │              ApplicationName     = "lambda-app"                        │
# │              DeploymentGroupName = "production"                        │
# │            },                                                          │
# │            input_artifacts = ["build_output"]                          │
# │        }] }                                                            │
# │      ]                                                                 │
# │    }                                                                   │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 6: Monorepo with V2 Triggers (Path-based filtering)            │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "frontend_pipeline" {                                          │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "frontend"                                                 │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = { type = "CODEPIPELINE" }                       │
# │        artifacts      = { type = "CODEPIPELINE" }                      │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      pipeline_type = "V2"                                              │
# │      triggers = [{                                                     │
# │        git_configuration = {                                           │
# │          source_action_name = "Source"                                  │
# │          push = [{                                                     │
# │            branches   = { includes = ["main"] }                        │
# │            file_paths = { includes = ["frontend/**"] }                 │
# │          }]                                                            │
# │        }                                                               │
# │      }]                                                                │
# │      stages = [                                                        │
# │        { name = "Source", actions = [{ ... }] },                       │
# │        { name = "Build",  actions = [{ ... }] },                       │
# │        { name = "Deploy", actions = [{ ... }] }                        │
# │      ]                                                                 │
# │    }                                                                   │
# │  }                                                                     │
# │                                                                        │
# │  module "backend_pipeline" {                                           │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "backend"                                                  │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      pipeline_type = "V2"                                              │
# │      triggers = [{                                                     │
# │        git_configuration = {                                           │
# │          source_action_name = "Source"                                  │
# │          push = [{                                                     │
# │            branches   = { includes = ["main"] }                        │
# │            file_paths = { includes = ["backend/**", "shared/**"] }     │
# │          }]                                                            │
# │        }                                                               │
# │      }]                                                                │
# │      stages = [...]                                                    │
# │    }                                                                   │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Example 7: Full-Featured (All options enabled)                         │
# ├──────────────────────────────────────────────────────────────────────────┤
# │                                                                        │
# │  module "ci_cd" {                                                      │
# │    source = "./aws_ci_cd"                                              │
# │    name   = "my-app"                                                   │
# │    create_kms_key = true                                               │
# │                                                                        │
# │    artifact_bucket_config = {                                          │
# │      versioning                = true                                  │
# │      lifecycle_expiration_days = 60                                    │
# │      access_logging_bucket    = "my-logs-bucket"                       │
# │    }                                                                   │
# │                                                                        │
# │    codebuild_projects = {                                              │
# │      build = {                                                         │
# │        source_config = { type = "CODEPIPELINE" }                       │
# │        artifacts      = { type = "CODEPIPELINE" }                      │
# │        environment = {                                                 │
# │          compute_type    = "BUILD_GENERAL1_LARGE"                      │
# │          privileged_mode = true                                        │
# │          environment_variables = [                                     │
# │            { name = "ENV", value = "prod", type = "PLAINTEXT" },       │
# │            { name = "DB_PASS", value = "/app/db-pass", type = "PARAMETER_STORE" }│
# │          ]                                                             │
# │        }                                                               │
# │        vpc_config = {                                                  │
# │          vpc_id             = "vpc-123"                                │
# │          subnets            = ["subnet-1", "subnet-2"]                 │
# │          security_group_ids = ["sg-123"]                               │
# │        }                                                               │
# │        cache = {                                                       │
# │          type  = "LOCAL"                                               │
# │          modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]    │
# │        }                                                               │
# │        observability = {                                               │
# │          enabled          = true                                       │
# │          enable_dashboard = true                                       │
# │        }                                                               │
# │      }                                                                 │
# │      test = {                                                          │
# │        source_config = { type = "CODEPIPELINE" }                       │
# │        artifacts      = { type = "CODEPIPELINE" }                      │
# │        environment = {                                                 │
# │          compute_type = "BUILD_GENERAL1_MEDIUM"                        │
# │        }                                                               │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codedeploy = {                                                      │
# │      deployment_groups = {                                             │
# │        staging    = { ec2_tag_filters = [{ key = "Env", value = "staging" }] }│
# │        production = {                                                  │
# │          deployment_config_name = "CodeDeployDefault.OneAtATime"       │
# │          ec2_tag_filters = [{ key = "Env", value = "production" }]     │
# │          auto_rollback_configuration = {                               │
# │            enabled = true                                              │
# │            events  = ["DEPLOYMENT_FAILURE","DEPLOYMENT_STOP_ON_ALARM"] │
# │          }                                                             │
# │          alarm_configuration = {                                       │
# │            enabled = true                                              │
# │            alarms  = ["my-app-high-cpu", "my-app-errors"]              │
# │          }                                                             │
# │          trigger_configuration = [{                                    │
# │            trigger_name       = "deploy-notifications"                 │
# │            trigger_target_arn = "arn:aws:sns:..."                      │
# │            trigger_events     = ["DeploymentSuccess","DeploymentFailure"]│
# │          }]                                                            │
# │        }                                                               │
# │      }                                                                 │
# │      observability = {                                                 │
# │        enabled = true                                                  │
# │        default_alarm_actions = ["arn:aws:sns:..."]                     │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    codepipeline = {                                                    │
# │      pipeline_type = "V2"                                              │
# │      triggers = [{                                                     │
# │        git_configuration = {                                           │
# │          source_action_name = "Source"                                  │
# │          push = [{ branches = { includes = ["main"] } }]               │
# │        }                                                               │
# │      }]                                                                │
# │      stages = [                                                        │
# │        { name = "Source",     actions = [{ ... }] },                   │
# │        { name = "Build",      actions = [{ ... }] },                   │
# │        { name = "Test",       actions = [{ ... }] },                   │
# │        { name = "Staging",    actions = [{ ... }] },                   │
# │        { name = "Approval",   actions = [{                             │
# │            name = "ManualApproval", category = "Approval",             │
# │            owner = "AWS", provider = "Manual",                         │
# │            configuration = {                                           │
# │              NotificationArn = "arn:aws:sns:..."                       │
# │            }                                                           │
# │        }] },                                                           │
# │        { name = "Production", actions = [{ ... }] }                    │
# │      ]                                                                 │
# │      observability = {                                                 │
# │        enabled                    = true                               │
# │        enable_dashboard           = true                               │
# │        enable_event_notifications = true                               │
# │        notification_sns_topic_arn = "arn:aws:sns:..."                  │
# │      }                                                                 │
# │    }                                                                   │
# │                                                                        │
# │    tags = {                                                            │
# │      Environment = "production"                                        │
# │      Team        = "platform"                                          │
# │      ManagedBy   = "terraform"                                         │
# │    }                                                                   │
# │  }                                                                     │
# │                                                                        │
# └──────────────────────────────────────────────────────────────────────────┘
#
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  artifact_bucket_name = var.create_artifact_bucket ? coalesce(
    var.artifact_bucket_name,
    "${var.name}-artifacts-${local.account_id}"
  ) : var.existing_artifact_bucket_name

  kms_key_arn = var.create_kms_key ? aws_kms_key.this[0].arn : try(var.artifact_bucket_config.kms_key_arn, null)

  artifact_bucket_access_role_arns = distinct(compact(concat(
    var.codepipeline != null ? [try(module.codepipeline[0].codepipeline_role_arn, null)] : [],
    [for _, cb in module.codebuild : try(cb.codebuild_role_arn, null)],
    var.codedeploy != null ? [try(module.codedeploy[0].codedeploy_role_arn, null)] : []
  )))
}

# =============================================================================
# KMS Key for Encryption
# =============================================================================

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description             = coalesce(try(var.kms_key_config.description, null), "KMS key for ${var.name} CI/CD pipeline encryption")
  deletion_window_in_days = try(var.kms_key_config.deletion_window_in_days, 30)
  enable_key_rotation     = try(var.kms_key_config.enable_key_rotation, true)

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCodePipelineService"
        Effect = "Allow"
        Principal = {
          Service = [
            "codepipeline.amazonaws.com",
            "codebuild.amazonaws.com",
            "s3.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-ci-cd-key"
  })
}

resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.name}-ci-cd"
  target_key_id = aws_kms_key.this[0].key_id
}

# =============================================================================
# S3 Artifact Bucket
# =============================================================================

resource "aws_s3_bucket" "artifacts" {
  count = var.create_artifact_bucket ? 1 : 0

  bucket        = local.artifact_bucket_name
  force_destroy = try(var.artifact_bucket_config.force_destroy, false)

  tags = merge(var.tags, {
    Name = local.artifact_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  count = var.create_artifact_bucket ? 1 : 0

  bucket = aws_s3_bucket.artifacts[0].id

  versioning_configuration {
    status = try(var.artifact_bucket_config.versioning, true) ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  count = var.create_artifact_bucket ? 1 : 0

  bucket = aws_s3_bucket.artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = local.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  count = var.create_artifact_bucket ? 1 : 0

  bucket = aws_s3_bucket.artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  count = var.create_artifact_bucket && try(var.artifact_bucket_config.lifecycle_expiration_days, 90) > 0 ? 1 : 0

  bucket = aws_s3_bucket.artifacts[0].id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = try(var.artifact_bucket_config.lifecycle_expiration_days, 90)
    }

    noncurrent_version_expiration {
      noncurrent_days = try(var.artifact_bucket_config.noncurrent_expiration_days, 30)
    }
  }
}

resource "aws_s3_bucket_logging" "artifacts" {
  count = var.create_artifact_bucket && try(var.artifact_bucket_config.access_logging_bucket, null) != null ? 1 : 0

  bucket = aws_s3_bucket.artifacts[0].id

  target_bucket = var.artifact_bucket_config.access_logging_bucket
  target_prefix = try(var.artifact_bucket_config.access_logging_prefix, "artifact-access-logs/")
}

resource "aws_s3_bucket_policy" "artifacts" {
  count = var.create_artifact_bucket ? 1 : 0

  bucket = aws_s3_bucket.artifacts[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(local.artifact_bucket_access_role_arns) > 0 ? [
        {
          Sid    = "AllowModuleCICDRoles"
          Effect = "Allow"
          Principal = {
            AWS = local.artifact_bucket_access_role_arns
          }
          Action = [
            "s3:GetBucketLocation",
            "s3:GetBucketVersioning",
            "s3:ListBucket",
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject",
            "s3:PutObjectAcl"
          ]
          Resource = [
            aws_s3_bucket.artifacts[0].arn,
            "${aws_s3_bucket.artifacts[0].arn}/*"
          ]
        }
      ] : [],
      [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource = [
            aws_s3_bucket.artifacts[0].arn,
            "${aws_s3_bucket.artifacts[0].arn}/*"
          ]
          Condition = {
            Bool = {
              "aws:SecureTransport" = "false"
            }
          }
        },
        {
          Sid       = "DenyIncorrectEncryptionHeader"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:PutObject"
          Resource  = "${aws_s3_bucket.artifacts[0].arn}/*"
          Condition = {
            StringNotEquals = {
              "s3:x-amz-server-side-encryption" = local.kms_key_arn != null ? "aws:kms" : "AES256"
            }
          }
        }
      ]
    )
  })
}

# =============================================================================
# CodeBuild Projects
# =============================================================================

module "codebuild" {
  source   = "./aws_codebuild"
  for_each = var.codebuild_projects

  name                   = "${var.name}-${each.key}"
  description            = each.value.description
  build_timeout          = each.value.build_timeout
  queued_timeout         = each.value.queued_timeout
  concurrent_build_limit = each.value.concurrent_build_limit
  source_version         = each.value.source_version
  badge_enabled          = each.value.badge_enabled
  source_config          = each.value.source_config
  secondary_sources      = each.value.secondary_sources
  secondary_source_versions = each.value.secondary_source_versions
  environment            = each.value.environment
  artifacts              = each.value.artifacts
  secondary_artifacts    = each.value.secondary_artifacts
  cache                  = each.value.cache
  vpc_config             = each.value.vpc_config
  logs_config            = each.value.logs_config
  service_role_arn       = each.value.service_role_arn
  encryption_key         = each.value.encryption_key != null ? each.value.encryption_key : local.kms_key_arn
  webhooks               = each.value.webhooks
  file_system_locations  = each.value.file_system_locations
  build_batch_config     = each.value.build_batch_config
  observability          = each.value.observability
  cloudwatch_metric_alarms = each.value.cloudwatch_metric_alarms

  tags = var.tags
}

# =============================================================================
# CodePipeline
# =============================================================================

module "codepipeline" {
  source = "./aws_code_pipeline"
  count  = var.codepipeline != null ? 1 : 0

  name           = coalesce(try(var.codepipeline.name, null), var.name)
  pipeline_type  = var.codepipeline.pipeline_type
  execution_mode = var.codepipeline.execution_mode

  artifact_store = {
    location          = local.artifact_bucket_name
    type              = "S3"
    encryption_key_id = local.kms_key_arn
  }

  additional_artifact_stores = try(var.codepipeline.additional_artifact_stores, {})
  stages                     = var.codepipeline.stages
  triggers                   = try(var.codepipeline.triggers, [])
  variables                  = try(var.codepipeline.variables, [])
  service_role_arn           = try(var.codepipeline.service_role_arn, null)
  observability              = try(var.codepipeline.observability, {})
  cloudwatch_metric_alarms   = try(var.codepipeline.cloudwatch_metric_alarms, {})

  tags = var.tags
}

# =============================================================================
# CodeDeploy
# =============================================================================

module "codedeploy" {
  source = "./aws_code_deploy"
  count  = var.codedeploy != null ? 1 : 0

  application_name          = coalesce(try(var.codedeploy.application_name, null), var.name)
  compute_platform          = var.codedeploy.compute_platform
  deployment_groups         = try(var.codedeploy.deployment_groups, {})
  custom_deployment_configs = try(var.codedeploy.custom_deployment_configs, {})
  service_role_arn          = try(var.codedeploy.service_role_arn, null)
  observability             = try(var.codedeploy.observability, {})
  cloudwatch_metric_alarms  = try(var.codedeploy.cloudwatch_metric_alarms, {})

  tags = var.tags
}
