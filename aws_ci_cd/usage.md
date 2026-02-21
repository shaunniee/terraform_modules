# aws_ci_cd module usage

Reusable parent CI/CD module that orchestrates:
- `aws_codebuild` (one or many build projects)
- `aws_code_pipeline` (optional pipeline)
- `aws_code_deploy` (optional deployment app/groups)
- Optional artifact bucket + optional KMS key with secure defaults

## Features

- Dynamic map-driven CodeBuild projects
- Dynamic stage/action-based CodePipeline (V1 or V2)
- Dynamic CodeDeploy deployment groups for Server, ECS, and Lambda
- Optional creation of artifact bucket in-module (`create_artifact_bucket = true`)
- Optional in-module KMS key (`create_kms_key = true`) for artifact encryption
- Auto-created IAM roles for each service (or bring your own roles)
- Built-in observability options for all 3 services (alarms/dashboards)
- Strong defaults: TLS-only S3 access, SSE enforced, public access blocked

---

## Minimal end-to-end (Source → Build → Deploy to S3)

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "my-app"

  codebuild_projects = {
    build = {
      source_config = {
        type      = "CODEPIPELINE"
        buildspec = "buildspec.yml"
      }
      artifacts = {
        type = "CODEPIPELINE"
      }
    }
  }

  codepipeline = {
    stages = [
      {
        name = "Source"
        actions = [
          {
            name     = "Source"
            category = "Source"
            owner    = "AWS"
            provider = "CodeStarSourceConnection"
            configuration = {
              ConnectionArn    = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxxx"
              FullRepositoryId = "org/repo"
              BranchName       = "main"
            }
            output_artifacts = ["source_output"]
          }
        ]
      },
      {
        name = "Build"
        actions = [
          {
            name             = "Build"
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            configuration    = { ProjectName = "my-app-build" }
            input_artifacts  = ["source_output"]
            output_artifacts = ["build_output"]
          }
        ]
      },
      {
        name = "Deploy"
        actions = [
          {
            name            = "DeployToS3"
            category        = "Deploy"
            owner           = "AWS"
            provider        = "S3"
            configuration   = { BucketName = "my-deploy-bucket", Extract = "true" }
            input_artifacts = ["build_output"]
          }
        ]
      }
    ]
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

---

## Use existing artifact bucket (no bucket creation)

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "my-app"

  create_artifact_bucket        = false
  existing_artifact_bucket_name = "org-shared-cicd-artifacts"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE" }
      artifacts     = { type = "CODEPIPELINE" }
    }
  }

  codepipeline = {
    stages = [
      { name = "Source", actions = [{ name = "Src", category = "Source", owner = "AWS", provider = "S3", configuration = { S3Bucket = "org-src", S3ObjectKey = "app.zip", PollForSourceChanges = "false" }, output_artifacts = ["source"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "my-app-build" }, input_artifacts = ["source"], output_artifacts = ["out"] }] }
    ]
  }
}
```

---

## Create artifact bucket + KMS (recommended production baseline)

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "payments"

  create_artifact_bucket = true
  create_kms_key         = true

  artifact_bucket_config = {
    versioning                 = true
    lifecycle_expiration_days  = 60
    noncurrent_expiration_days = 14
    force_destroy              = false
  }

  kms_key_config = {
    description             = "CI/CD key for payments"
    enable_key_rotation     = true
    deletion_window_in_days = 30
  }

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE", buildspec = "buildspec.yml" }
      artifacts     = { type = "CODEPIPELINE" }
    }
  }

  codepipeline = {
    stages = [
      { name = "Source", actions = [{ name = "Source", category = "Source", owner = "AWS", provider = "CodeStarSourceConnection", configuration = { ConnectionArn = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxxx", FullRepositoryId = "org/payments", BranchName = "main" }, output_artifacts = ["source"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "payments-build" }, input_artifacts = ["source"], output_artifacts = ["build"] }] }
    ]
  }
}
```

---

## Multi-project CodeBuild in one module

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "monorepo"

  codebuild_projects = {
    lint = {
      source_config = { type = "CODEPIPELINE", buildspec = "buildspec.lint.yml" }
      artifacts     = { type = "CODEPIPELINE" }
      environment = {
        compute_type = "BUILD_GENERAL1_SMALL"
      }
    }

    test = {
      source_config = { type = "CODEPIPELINE", buildspec = "buildspec.test.yml" }
      artifacts     = { type = "CODEPIPELINE" }
      environment = {
        compute_type = "BUILD_GENERAL1_MEDIUM"
      }
    }

    package = {
      source_config = { type = "CODEPIPELINE", buildspec = "buildspec.package.yml" }
      artifacts     = { type = "CODEPIPELINE" }
      environment = {
        compute_type    = "BUILD_GENERAL1_MEDIUM"
        privileged_mode = true
      }
    }
  }
}
```

---

## EC2/On-prem deploy with CodeDeploy

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "orders"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE" }
      artifacts     = { type = "CODEPIPELINE" }
    }
  }

  codedeploy = {
    compute_platform = "Server"
    deployment_groups = {
      production = {
        deployment_config_name = "CodeDeployDefault.OneAtATime"
        ec2_tag_filters = [
          { key = "Environment", value = "production", type = "KEY_AND_VALUE" }
        ]
        auto_rollback_configuration = {
          enabled = true
          events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
        }
      }
    }
  }

  codepipeline = {
    stages = [
      { name = "Source", actions = [{ name = "Source", category = "Source", owner = "AWS", provider = "CodeCommit", configuration = { RepositoryName = "orders", BranchName = "main" }, output_artifacts = ["src"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "orders-build" }, input_artifacts = ["src"], output_artifacts = ["build"] }] },
      { name = "Deploy", actions = [{ name = "Deploy", category = "Deploy", owner = "AWS", provider = "CodeDeploy", configuration = { ApplicationName = "orders", DeploymentGroupName = "production" }, input_artifacts = ["build"] }] }
    ]
  }
}
```

---

## ECS Blue/Green deployment

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "checkout"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE", buildspec = "buildspec.yml" }
      artifacts     = { type = "CODEPIPELINE" }
      environment = {
        compute_type    = "BUILD_GENERAL1_MEDIUM"
        privileged_mode = true
      }
    }
  }

  codedeploy = {
    compute_platform = "ECS"
    deployment_groups = {
      ecs_prod = {
        deployment_type        = "BLUE_GREEN"
        deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
        ecs_service = {
          cluster_name = "checkout-cluster"
          service_name = "checkout-service"
        }
        load_balancer_info = {
          target_group_pair_info = {
            target_groups = [{ name = "checkout-blue" }, { name = "checkout-green" }]
            prod_traffic_route = { listener_arns = ["arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/prod/abc"] }
          }
        }
      }
    }
  }

  codepipeline = {
    stages = [
      { name = "Source", actions = [{ name = "Source", category = "Source", owner = "AWS", provider = "CodeStarSourceConnection", configuration = { ConnectionArn = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxxx", FullRepositoryId = "org/checkout", BranchName = "main" }, output_artifacts = ["source"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "checkout-build" }, input_artifacts = ["source"], output_artifacts = ["build_output"] }] },
      { name = "Deploy", actions = [{ name = "DeployToECS", category = "Deploy", owner = "AWS", provider = "CodeDeployToECS", configuration = { ApplicationName = "checkout", DeploymentGroupName = "ecs_prod", TaskDefinitionTemplateArtifact = "build_output", AppSpecTemplateArtifact = "build_output" }, input_artifacts = ["build_output"] }] }
    ]
  }
}
```

---

## Lambda deployment (canary)

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "billing-lambda"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE" }
      artifacts     = { type = "CODEPIPELINE" }
      environment = {
        compute_type = "BUILD_LAMBDA_1GB"
        image        = "aws/codebuild/amazonlinux-aarch64-lambda-standard:python3.12"
        type         = "ARM_LAMBDA_CONTAINER"
      }
    }
  }

  codedeploy = {
    compute_platform = "Lambda"
    deployment_groups = {
      prod = {
        deployment_config_name = "CodeDeployDefault.LambdaCanary10Percent5Minutes"
      }
    }
  }
}
```

---

## Pipeline V2 with triggers and manual approval

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "platform"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE", buildspec = "buildspec.yml" }
      artifacts     = { type = "CODEPIPELINE" }
    }
  }

  codepipeline = {
    pipeline_type = "V2"
    execution_mode = "QUEUED"

    triggers = [
      {
        git_configuration = {
          source_action_name = "Source"
          push = [
            {
              branches = { includes = ["main"] }
              file_paths = { includes = ["services/platform/**", "libs/common/**"] }
            }
          ]
        }
      }
    ]

    stages = [
      { name = "Source", actions = [{ name = "Source", category = "Source", owner = "AWS", provider = "CodeStarSourceConnection", configuration = { ConnectionArn = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxxx", FullRepositoryId = "org/mono", BranchName = "main" }, output_artifacts = ["src"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "platform-build" }, input_artifacts = ["src"], output_artifacts = ["build"] }] },
      { name = "Approval", actions = [{ name = "Manual", category = "Approval", owner = "AWS", provider = "Manual", configuration = { CustomData = "Approve production deployment" } }] }
    ]
  }
}
```

---

## Observability-enabled setup

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "analytics"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE" }
      artifacts     = { type = "CODEPIPELINE" }
      observability = {
        enabled                = true
        enable_default_alarms  = true
        enable_dashboard       = true
        failed_builds_threshold = 1
        build_duration_threshold = 1800
        default_alarm_actions  = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
      }
    }
  }

  codepipeline = {
    stages = [
      { name = "Source", actions = [{ name = "Src", category = "Source", owner = "AWS", provider = "S3", configuration = { S3Bucket = "analytics-src", S3ObjectKey = "source.zip" }, output_artifacts = ["src"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "analytics-build" }, input_artifacts = ["src"], output_artifacts = ["build"] }] }
    ]
    observability = {
      enabled                    = true
      enable_default_alarms      = true
      enable_dashboard           = true
      enable_event_notifications = true
      notification_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:cicd-alerts"
      default_alarm_actions      = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
    }
  }

  codedeploy = {
    deployment_groups = {}
    observability = {
      enabled               = true
      enable_default_alarms = true
      enable_dashboard      = true
    }
  }
}
```

---

## Frontend deploy to S3 + CloudFront cache invalidation (recommended)

This pattern uses:
- CodeBuild to build frontend assets and package output
- CodePipeline S3 deploy action to publish to the website bucket
- A Lambda invoke action to invalidate CloudFront cache after deploy

```hcl
module "frontend_ci_cd" {
  source = "../aws_ci_cd"
  name   = "frontend-web"

  create_artifact_bucket = true
  create_kms_key         = true

  codebuild_projects = {
    frontend_build = {
      source_config = {
        type      = "CODEPIPELINE"
        buildspec = "buildspec.frontend.yml"
      }
      artifacts = {
        type = "CODEPIPELINE"
      }
      environment = {
        compute_type = "BUILD_GENERAL1_MEDIUM"
        image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
        type         = "LINUX_CONTAINER"
        environment_variables = [
          { name = "NODE_ENV", value = "production", type = "PLAINTEXT" }
        ]
      }
    }
  }

  codepipeline = {
    pipeline_type  = "V2"
    execution_mode = "QUEUED"

    stages = [
      {
        name = "Source"
        actions = [
          {
            name     = "Source"
            category = "Source"
            owner    = "AWS"
            provider = "CodeStarSourceConnection"
            configuration = {
              ConnectionArn    = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxxx"
              FullRepositoryId = "org/frontend"
              BranchName       = "main"
            }
            output_artifacts = ["source_output"]
          }
        ]
      },
      {
        name = "Build"
        actions = [
          {
            name             = "BuildFrontend"
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            configuration    = { ProjectName = "frontend-web-frontend_build" }
            input_artifacts  = ["source_output"]
            output_artifacts = ["build_output"]
          }
        ]
      },
      {
        name = "Deploy"
        actions = [
          {
            name            = "DeployToS3"
            category        = "Deploy"
            owner           = "AWS"
            provider        = "S3"
            configuration   = { BucketName = "my-frontend-site-bucket", Extract = "true" }
            input_artifacts = ["build_output"]
          },
          {
            name      = "InvalidateCloudFront"
            category  = "Invoke"
            owner     = "AWS"
            provider  = "Lambda"
            run_order = 2
            configuration = {
              FunctionName   = "cloudfront-invalidator"
              UserParameters = jsonencode({ distribution_id = "E1ABCDEF2GHIJK", paths = ["/*"] })
            }
          }
        ]
      }
    ]
  }
}
```

Example `buildspec.frontend.yml` (optimized for caching):

```yaml
version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: 20
    commands:
      - npm ci
  build:
    commands:
      - npm run build
  post_build:
    commands:
      - mkdir -p artifact
      - cp -R dist/* artifact/
artifacts:
  base-directory: artifact
  files:
    - '**/*'
```

CloudFront invalidation Lambda handler example (Python):

```python
import json
import boto3
import uuid

cf = boto3.client("cloudfront")

def handler(event, context):
    params = json.loads(event.get("UserParameters", "{}"))
    distribution_id = params["distribution_id"]
    paths = params.get("paths", ["/*"])

    resp = cf.create_invalidation(
        DistributionId=distribution_id,
        InvalidationBatch={
            "Paths": {"Quantity": len(paths), "Items": paths},
            "CallerReference": str(uuid.uuid4()),
        },
    )
    return {"statusCode": 200, "invalidation_id": resp["Invalidation"]["Id"]}
```

---

## Lambda function deployment with CodeDeploy canary + rollback

```hcl
module "lambda_ci_cd" {
  source = "../aws_ci_cd"
  name   = "orders-lambda"

  create_artifact_bucket = true
  create_kms_key         = true

  codebuild_projects = {
    package = {
      source_config = {
        type      = "CODEPIPELINE"
        buildspec = "buildspec.lambda.yml"
      }
      artifacts = {
        type = "CODEPIPELINE"
      }
      environment = {
        compute_type = "BUILD_LAMBDA_1GB"
        image        = "aws/codebuild/amazonlinux-aarch64-lambda-standard:python3.12"
        type         = "ARM_LAMBDA_CONTAINER"
      }
    }
  }

  codedeploy = {
    compute_platform = "Lambda"
    deployment_groups = {
      production = {
        deployment_config_name = "CodeDeployDefault.LambdaCanary10Percent5Minutes"
        auto_rollback_configuration = {
          enabled = true
          events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"]
        }
        alarm_configuration = {
          enabled = true
          alarms  = ["orders-lambda-errors", "orders-lambda-throttles"]
        }
      }
    }
  }

  codepipeline = {
    stages = [
      {
        name = "Source"
        actions = [
          {
            name     = "Source"
            category = "Source"
            owner    = "AWS"
            provider = "CodeStarSourceConnection"
            configuration = {
              ConnectionArn    = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxxx"
              FullRepositoryId = "org/orders-lambda"
              BranchName       = "main"
            }
            output_artifacts = ["source_output"]
          }
        ]
      },
      {
        name = "Build"
        actions = [
          {
            name             = "PackageLambda"
            category         = "Build"
            owner            = "AWS"
            provider         = "CodeBuild"
            configuration    = { ProjectName = "orders-lambda-package" }
            input_artifacts  = ["source_output"]
            output_artifacts = ["build_output"]
          }
        ]
      },
      {
        name = "Deploy"
        actions = [
          {
            name            = "DeployLambda"
            category        = "Deploy"
            owner           = "AWS"
            provider        = "CodeDeploy"
            configuration   = { ApplicationName = "orders-lambda", DeploymentGroupName = "production" }
            input_artifacts = ["build_output"]
          }
        ]
      }
    ]
  }
}
```

How Lambda function + alias are selected in CodeDeploy:

- `ApplicationName` + `DeploymentGroupName` in CodePipeline select the CodeDeploy deployment group.
- Lambda function and alias come from `appspec.yml` inside the deployment artifact.
- Keep alias stable (for example `live`) and shift traffic between published versions.

`appspec.yml` example:

```yaml
version: 0.0
Resources:
  - OrdersLambda:
      Type: AWS::Lambda::Function
      Properties:
        Name: orders-handler
        Alias: live
        CurrentVersion: 12
        TargetVersion: 13
```

Example `buildspec.lambda.yml` (auto-generates `appspec.yml` with current + target versions):

```yaml
version: 0.2
env:
  variables:
    FUNCTION_NAME: "orders-handler"
    FUNCTION_ALIAS: "live"
phases:
  install:
    runtime-versions:
      python: 3.12
  build:
    commands:
      - pip install -r requirements.txt -t package/
      - cp -R src/* package/
      - cd package && zip -r ../function.zip . && cd ..
      - TARGET_VERSION=$(aws lambda publish-version --function-name "$FUNCTION_NAME" --query 'Version' --output text)
      - CURRENT_VERSION=$(aws lambda get-alias --function-name "$FUNCTION_NAME" --name "$FUNCTION_ALIAS" --query 'FunctionVersion' --output text)
      - |
        cat > appspec.yml <<EOF
        version: 0.0
        Resources:
          - OrdersLambda:
              Type: AWS::Lambda::Function
              Properties:
                Name: ${FUNCTION_NAME}
                Alias: ${FUNCTION_ALIAS}
                CurrentVersion: ${CURRENT_VERSION}
                TargetVersion: ${TARGET_VERSION}
        EOF
artifacts:
  files:
    - function.zip
    - appspec.yml
```

---

## Logs for CI/CD (where to look)

### 1) CodeBuild logs (primary build logs)

- Default CloudWatch log group: `/aws/codebuild/<project-name>`
- In this module, CloudWatch logging is enabled by default for CodeBuild.
- You can override group/stream with `codebuild_projects["<key>"].logs_config.cloudwatch`.
- Optional S3 build logs can be enabled with `codebuild_projects["<key>"].logs_config.s3`.

Example:

```hcl
codebuild_projects = {
  build = {
    source_config = { type = "CODEPIPELINE" }
    artifacts     = { type = "CODEPIPELINE" }
    logs_config = {
      cloudwatch = {
        group_name = "/aws/codebuild/my-custom-group"
        status     = "ENABLED"
      }
      s3 = {
        location = "my-log-bucket/codebuild/"
        status   = "ENABLED"
      }
    }
  }
}
```

### 2) CodePipeline logs/events

- CodePipeline does not emit full step logs like CodeBuild; use:
  - Pipeline execution history (stage/action status)
  - CloudWatch metrics/alarms
  - EventBridge notifications (supported in this module)
- Enable event notifications:

```hcl
codepipeline = {
  # ... stages ...
  observability = {
    enabled                    = true
    enable_event_notifications = true
    notification_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:cicd-events"
  }
}
```

### 3) CodeDeploy logs

- Deployment lifecycle status is in CodeDeploy deployment events/timeline.
- For EC2/on-prem deployments, detailed script logs are on instances via CodeDeploy agent logs:
  - `/var/log/aws/codedeploy-agent/codedeploy-agent.log`
  - `/opt/codedeploy-agent/deployment-root/...` (hook script logs)
- For Lambda deployments, execution logs are in the Lambda function CloudWatch log group.

### 4) CloudFront invalidation Lambda logs (frontend pattern)

- If you use the cache invalidation Lambda action in pipeline, check that Lambda’s CloudWatch logs for invalidation request IDs and errors.

### Quick CLI checks

```bash
# Show latest CodeBuild builds
aws codebuild list-builds-for-project --project-name <project-name>

# Fetch one build details (includes log group/stream)
aws codebuild batch-get-builds --ids <build-id>

# Pipeline execution status
aws codepipeline get-pipeline-state --name <pipeline-name>

# CodeDeploy deployment details
aws deploy get-deployment --deployment-id <deployment-id>
```

---

## Complete observability and logging guide (production)

Use this section as the standard baseline for CI/CD observability across build, pipeline, and deploy.

### What the module provides

- **CodeBuild**: default alarms + optional dashboard + CloudWatch/S3 build logs.
- **CodePipeline**: failed execution alarms + optional dashboard + EventBridge notifications to SNS.
- **CodeDeploy**: deployment failure alarms + optional dashboard + deployment lifecycle visibility.
- **Aggregated outputs**: alarm ARN maps and dashboard ARNs exposed by the parent module.

### Enablement matrix

- **CodeBuild**
  - `codebuild_projects.<key>.observability.enabled = true`
  - `enable_default_alarms`, `enable_dashboard`
  - thresholds: `failed_builds_threshold`, `build_duration_threshold`
- **CodePipeline**
  - `codepipeline.observability.enabled = true`
  - `enable_default_alarms`, `enable_dashboard`
  - optional eventing: `enable_event_notifications = true` + `notification_sns_topic_arn`
- **CodeDeploy**
  - `codedeploy.observability.enabled = true`
  - `enable_default_alarms`, `enable_dashboard`

### Production preset (copy/paste)

```hcl
module "ci_cd" {
  source = "../aws_ci_cd"
  name   = "payments"

  codebuild_projects = {
    build = {
      source_config = { type = "CODEPIPELINE" }
      artifacts     = { type = "CODEPIPELINE" }

      logs_config = {
        cloudwatch = {
          status = "ENABLED"
        }
        s3 = {
          location = "my-observability-logs-bucket/codebuild/"
          status   = "ENABLED"
        }
      }

      observability = {
        enabled                            = true
        enable_default_alarms              = true
        enable_dashboard                   = true
        failed_builds_threshold            = 1
        build_duration_threshold           = 1800
        default_alarm_actions              = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
        default_ok_actions                 = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
        default_insufficient_data_actions  = []
      }
    }
  }

  codepipeline = {
    stages = [
      { name = "Source", actions = [{ name = "Source", category = "Source", owner = "AWS", provider = "S3", configuration = { S3Bucket = "pipeline-source", S3ObjectKey = "source.zip" }, output_artifacts = ["src"] }] },
      { name = "Build", actions = [{ name = "Build", category = "Build", owner = "AWS", provider = "CodeBuild", configuration = { ProjectName = "payments-build" }, input_artifacts = ["src"], output_artifacts = ["build"] }] }
    ]

    observability = {
      enabled                           = true
      enable_default_alarms             = true
      enable_dashboard                  = true
      enable_event_notifications        = true
      notification_sns_topic_arn        = "arn:aws:sns:us-east-1:123456789012:cicd-events"
      default_alarm_actions             = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
      default_ok_actions                = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
      default_insufficient_data_actions = []
    }
  }

  codedeploy = {
    deployment_groups = {
      production = {
        deployment_config_name = "CodeDeployDefault.OneAtATime"
      }
    }

    observability = {
      enabled                           = true
      enable_default_alarms             = true
      enable_dashboard                  = true
      default_alarm_actions             = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
      default_ok_actions                = ["arn:aws:sns:us-east-1:123456789012:cicd-alerts"]
      default_insufficient_data_actions = []
    }
  }
}
```

### Outputs to wire into monitoring

- `codebuild_alarm_arns`
- `codepipeline_alarm_arns`
- `codedeploy_alarm_arns`
- `codebuild_role_arns`, `codebuild_role_names`
- `codepipeline_role_arn`, `codepipeline_role_name`
- `codedeploy_role_arn`, `codedeploy_role_name`

### Recommended alerting policy

- Route all default alarms to a shared SNS topic (`cicd-alerts`) consumed by on-call tooling.
- Use separate SNS topic for event notifications (`cicd-events`) to avoid noise in pager channels.
- Keep `evaluation_periods` low for failures, higher for duration/latency metrics to reduce flapping.

### Required IAM permissions for full logging/observability

- **CodeBuild role**
  - CloudWatch logs: `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`
  - Optional S3 logs: `s3:PutObject`, `s3:GetBucketAcl` on log bucket/prefix
- **CodePipeline role**
  - SNS publish for manual approvals/notifications: `sns:Publish`
  - Lambda invoke (if invalidate action): `lambda:InvokeFunction`
- **CodeDeploy service role**
  - Managed by compute platform policy; ensure target resources and alarms are accessible

### Troubleshooting flow

1. Check `aws codepipeline get-pipeline-state --name <pipeline-name>` for failing stage/action.
2. For build failures, fetch build details (`batch-get-builds`) and inspect CloudWatch log stream.
3. For deploy failures, inspect `aws deploy get-deployment --deployment-id <id>` and deployment events.
4. For frontend invalidation failures, inspect the invalidation Lambda log group.
5. Confirm alarms/dashboards via module outputs and CloudWatch console.

---

## Important inputs

- `name`: base name prefix for all resources.
- `codebuild_projects`: map of project configs (can be empty).
- `codepipeline`: pipeline object or `null` to skip pipeline creation.
- `codedeploy`: codedeploy object or `null` to skip codedeploy creation.
- `create_artifact_bucket`: create artifact bucket in this module (`true`) or use existing (`false`).
- `existing_artifact_bucket_name`: required when `create_artifact_bucket = false`.
- `create_kms_key`: create KMS key for artifact encryption.
- `tags`: tags applied across resources.

## Outputs

- `artifact_bucket_name`, `artifact_bucket_arn`
- `kms_key_arn`, `kms_key_alias`
- `codebuild_project_names`, `codebuild_project_arns`
- `codepipeline_name`, `codepipeline_arn`
- `codedeploy_app_name`, `codedeploy_app_arn`
- alarm output maps per service

---

## Best practices

- Use `create_kms_key = true` for production unless you have a centralized KMS strategy.
- Keep artifact lifecycle retention finite (`lifecycle_expiration_days`) to control cost.
- Prefer CodePipeline V2 + triggers for monorepos and path-scoped automation.
- Use separate deployment groups for staging and production with a manual approval stage.
- Enable rollback (`auto_rollback_configuration`) for all critical deployment groups.
- Use least-privilege external roles when you need cross-account actions.
- Enable observability and route alarms to SNS/on-call.
- Keep build projects single-purpose (`lint`, `test`, `package`) for clearer failure domains.
- Use `privileged_mode = true` only where Docker-in-Docker is required.
- Avoid storing secrets as plaintext env vars; use `SECRETS_MANAGER` or `PARAMETER_STORE`.

---

## Notes

- This parent module composes submodules under `aws_ci_cd/aws_codebuild`, `aws_ci_cd/aws_code_pipeline`, and `aws_ci_cd/aws_code_deploy`.
- For advanced provider-specific action `configuration` keys in pipeline stages, pass them directly through the `actions[].configuration` map.
