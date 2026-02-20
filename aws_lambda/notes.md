# AWS Lambda — Complete Engineering Reference Notes
> For use inside Terraform modules. Every detail, feature, config, and Terraform resource reference included.

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Function Configuration](#2-function-configuration)
3. [Runtimes](#3-runtimes)
4. [Deployment Packages & Layers](#4-deployment-packages--layers)
5. [Triggers & Event Sources](#5-triggers--event-sources)
6. [Networking (VPC)](#6-networking-vpc)
7. [IAM & Permissions](#7-iam--permissions)
8. [Environment Variables & Secrets](#8-environment-variables--secrets)
9. [Concurrency & Scaling](#9-concurrency--scaling)
10. [Execution Lifecycle](#10-execution-lifecycle)
11. [Destinations & Error Handling](#11-destinations--error-handling)
12. [Aliases & Versions](#12-aliases--versions)
13. [Lambda URLs](#13-lambda-urls)
14. [Container Image Functions](#14-container-image-functions)
15. [Extensions](#15-extensions)
16. [Cold Starts & Performance Tuning](#16-cold-starts--performance-tuning)
17. [Observability — Logging](#17-observability--logging)
18. [Observability — Metrics](#18-observability--metrics)
19. [Observability — Tracing (X-Ray)](#19-observability--tracing-x-ray)
20. [Observability — CloudWatch Lambda Insights](#20-observability--cloudwatch-lambda-insights)
21. [Debugging & Troubleshooting](#21-debugging--troubleshooting)
22. [Cost Model](#22-cost-model)
23. [Limits & Quotas](#23-limits--quotas)
24. [Security Best Practices](#24-security-best-practices)
25. [Terraform Full Resource Reference](#25-terraform-full-resource-reference)

---

## 1. Core Concepts

### What Lambda Is
- **Serverless compute** — run code without managing servers.
- Billed per invocation + GB-second of duration (100ms granularity).
- Each function runs in an **isolated execution environment** (microVM via Firecracker).
- Stateless by design; state must be externalized (S3, DynamoDB, ElastiCache, etc.).

### Invocation Models
| Model | Description | Terraform Trigger |
|---|---|---|
| **Synchronous** | Caller waits for response. Used by API GW, ALB, Lambda URL | `aws_lambda_function_url`, `aws_api_gateway_integration` |
| **Asynchronous** | Lambda queues the event; caller gets 202. Retries 2x by default. Used by S3, SNS, EventBridge | `aws_lambda_permission` with `principal = "s3.amazonaws.com"` |
| **Poll-based (ESM)** | Lambda polls SQS, Kinesis, DynamoDB Streams, MSK, Kafka | `aws_lambda_event_source_mapping` |

### Execution Environment Lifecycle
```
Init Phase  →  Invoke Phase  →  Shutdown Phase
  (cold)          (warm)
```
- **Init**: Downloads code, starts runtime, runs static initializers outside handler.
- **Invoke**: Handler runs. Environment may be **reused** (warm) for subsequent invocations.
- **Shutdown**: Extension flush + environment teardown.

---

## 2. Function Configuration

### Key Parameters

| Parameter | Description | Terraform Attribute |
|---|---|---|
| Function Name | Unique per region/account | `function_name` |
| Handler | `file.method` or `package.Class::method` | `handler` |
| Runtime | Language runtime version | `runtime` |
| Memory | 128 MB – 10,240 MB (64 MB increments) | `memory_size` |
| Ephemeral Storage | /tmp disk 512 MB – 10,240 MB | `ephemeral_storage { size = N }` |
| Timeout | 1 sec – 900 sec (15 min) | `timeout` |
| Architecture | x86_64 or arm64 (Graviton2) | `architectures = ["arm64"]` |
| Description | Human description | `description` |
| Publish | Create a numbered version on each deploy | `publish = true` |

### Terraform: `aws_lambda_function` core block
```hcl
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = var.description

  # Deployment package (zip)
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  # OR S3
  # s3_bucket        = var.s3_bucket
  # s3_key           = var.s3_key
  # s3_object_version = var.s3_version

  handler = "index.handler"
  runtime = "python3.12"

  role = aws_iam_role.lambda.arn

  memory_size = 512
  timeout     = 30
  publish     = true

  architectures = ["arm64"]

  ephemeral_storage {
    size = 1024 # MB
  }
}
```

---

## 3. Runtimes

### Managed Runtimes
| Runtime | Identifier |
|---|---|
| Python 3.12 | `python3.12` |
| Python 3.11 | `python3.11` |
| Python 3.10 | `python3.10` |
| Node.js 20.x | `nodejs20.x` |
| Node.js 18.x | `nodejs18.x` |
| Java 21 | `java21` |
| Java 17 | `java17` |
| Java 11 | `java11` |
| .NET 8 | `dotnet8` |
| Ruby 3.3 | `ruby3.3` |
| Go 1.x | `provided.al2023` (custom runtime) |
| Rust | `provided.al2023` (custom runtime) |

### Custom Runtime
- Use `provided.al2023` or `provided.al2` with a `bootstrap` executable in the zip.
- Bootstrap must implement the Lambda Runtime API (`/runtime/invocation/next`, etc.).

```hcl
resource "aws_lambda_function" "go" {
  runtime = "provided.al2023"
  handler = "bootstrap"
  architectures = ["arm64"]
  # ... zip containing bootstrap binary
}
```

### Runtime Deprecation
- AWS announces deprecation windows. After deprecation, can't create/update but existing functions still run.
- Monitor via `aws_lambda_function.this.runtime` and pin versions in Terraform.

---

## 4. Deployment Packages & Layers

### Zip Deployment
- Max unzipped: **250 MB** (includes layers).
- Max zip via console/API: **50 MB** (direct upload); **250 MB** via S3.

```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/lambda.zip"
}
```

### S3 Deployment (preferred for CI/CD)
```hcl
resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "lambda/${var.function_name}/${var.version}.zip"
  source = var.zip_path
  etag   = filemd5(var.zip_path)
}

resource "aws_lambda_function" "this" {
  s3_bucket         = aws_s3_object.lambda_zip.bucket
  s3_key            = aws_s3_object.lambda_zip.key
  s3_object_version = aws_s3_object.lambda_zip.version_id
  source_code_hash  = filebase64sha256(var.zip_path)
  # ...
}
```

### Lambda Layers
- Shared libraries/dependencies across functions.
- Max 5 layers per function.
- Layers are extracted to `/opt/` at runtime.
- Each layer max 250 MB unzipped.

```hcl
resource "aws_lambda_layer_version" "deps" {
  layer_name          = "python-deps"
  filename            = "layer.zip"
  source_code_hash    = filebase64sha256("layer.zip")
  compatible_runtimes = ["python3.12", "python3.11"]
  compatible_architectures = ["arm64", "x86_64"]
  description         = "Common Python dependencies"
}

resource "aws_lambda_function" "this" {
  layers = [
    aws_lambda_layer_version.deps.arn,
    "arn:aws:lambda:us-east-1:580247275435:layer:LambdaInsightsExtension-Arm64:20"
  ]
}
```

### Layer Path Conventions
| Language | Path in `/opt/` |
|---|---|
| Python | `/opt/python/` |
| Node.js | `/opt/nodejs/node_modules/` |
| Java | `/opt/java/lib/` |
| Ruby | `/opt/ruby/gems/` |
| All | `/opt/bin/`, `/opt/lib/` |

---

## 5. Triggers & Event Sources

### S3 Trigger
```hcl
resource "aws_s3_bucket_notification" "trigger" {
  bucket = aws_s3_bucket.source.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.this.arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.s3]
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}
```

### SQS Trigger (Event Source Mapping)
```hcl
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = aws_sqs_queue.this.arn
  function_name                      = aws_lambda_function.this.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 30
  enabled                            = true

  # Partial batch response — report failed items instead of full retry
  function_response_types = ["ReportBatchItemFailures"]

  # Filter messages before invoking
  filter_criteria {
    filter {
      pattern = jsonencode({ body = { action = ["process"] } })
    }
  }

  scaling_config {
    maximum_concurrency = 100
  }
}
```

### Kinesis / DynamoDB Streams Trigger
```hcl
resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn              = aws_kinesis_stream.this.arn
  function_name                 = aws_lambda_function.this.arn
  starting_position             = "LATEST"  # LATEST | TRIM_HORIZON | AT_TIMESTAMP
  starting_position_timestamp   = null
  batch_size                    = 100
  parallelization_factor        = 10  # 1-10 concurrent batches per shard
  maximum_batching_window_in_seconds = 30
  bisect_batch_on_function_error = true  # split batch on error to find poison pill
  maximum_retry_attempts        = 3
  maximum_record_age_in_seconds = 3600

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }

  function_response_types = ["ReportBatchItemFailures"]
}
```

### EventBridge (CloudWatch Events) Trigger
```hcl
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "lambda-schedule"
  schedule_expression = "rate(5 minutes)"
  # OR: cron(0 12 * * ? *)
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.this.arn

  input = jsonencode({ key = "value" })  # optional static input
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
```

### API Gateway (REST / HTTP)
```hcl
# HTTP API (v2) — lower cost, lower latency
resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
```

### SNS Trigger
```hcl
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.this.arn
}
```

### ALB Trigger
```hcl
resource "aws_lb_target_group" "lambda" {
  name        = "lambda-tg"
  target_type = "lambda"
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.this.arn
  depends_on       = [aws_lambda_permission.alb]
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}
```

### Cognito, IoT, CodeCommit, SES, Config
- All use `aws_lambda_permission` with appropriate `principal`.
- Cognito Pre/Post triggers set directly on the User Pool resource.

---

## 6. Networking (VPC)

### VPC Config
- Lambda creates **Hyperplane ENIs** (not per-function ENIs) in each subnet+SG combo.
- VPC Lambda can access RDS, ElastiCache, internal services, etc.
- Requires NAT Gateway or VPC endpoints for internet / AWS API access.

```hcl
resource "aws_lambda_function" "vpc" {
  # ...
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
}

resource "aws_security_group" "lambda" {
  name   = "lambda-sg"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### IAM Required for VPC
```hcl
data "aws_iam_policy" "vpc_access" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = data.aws_iam_policy.vpc_access.arn
}
```

### VPC Endpoints (avoid NAT for AWS services)
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = var.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}
```

### Notes
- VPC Lambda cold start adds ~1-2 seconds (first call after idle). Hyperplane helps but doesn't eliminate.
- Multi-AZ subnets give resilience and routing to AZ-local resources.
- Lambda can only be in one VPC. Use VPC peering or TGW for cross-VPC.

---

## 7. IAM & Permissions

### Execution Role (Trust Policy)
```hcl
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
```

### Managed Policies
```hcl
locals {
  managed_policies = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    # If VPC:
    # "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    # If X-Ray:
    # "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
  ]
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(local.managed_policies)
  role       = aws_iam_role.lambda.name
  policy_arn = each.value
}
```

### Custom Inline Policy
```hcl
data "aws_iam_policy_document" "custom" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.this.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.this.arn]
  }
}

resource "aws_iam_role_policy" "custom" {
  name   = "lambda-custom"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.custom.json
}
```

### Resource-Based Policy (who can invoke the Lambda)
```hcl
resource "aws_lambda_permission" "cross_account" {
  statement_id  = "AllowCrossAccountInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "123456789012"  # Another AWS account
  # OR a service: "s3.amazonaws.com", "events.amazonaws.com", etc.
  source_arn    = "arn:aws:s3:::my-bucket"  # restrict to specific resource
}
```

---

## 8. Environment Variables & Secrets

### Plain Environment Variables
```hcl
resource "aws_lambda_function" "this" {
  environment {
    variables = {
      APP_ENV    = var.environment
      LOG_LEVEL  = "INFO"
      TABLE_NAME = aws_dynamodb_table.this.name
      QUEUE_URL  = aws_sqs_queue.this.url
    }
  }
}
```
- Max 4 KB total for all env vars.
- Stored encrypted at rest using KMS (default Lambda service key or custom CMK).

### Encryption with Customer Managed Key
```hcl
resource "aws_lambda_function" "this" {
  kms_key_arn = aws_kms_key.lambda.arn

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.this.name
    }
  }
}
```

### AWS Secrets Manager (recommended for secrets)
- Don't put secrets in env vars in plaintext.
- Use Secrets Manager + Lambda extension or SDK call in handler.
- Lambda Powertools (Python/Node/Java/dotNET) has built-in parameters utility with caching.

```python
# In handler code (Python example)
import boto3
import json

client = boto3.client("secretsmanager")

# Cache outside handler (warm reuse)
_secret = None

def get_secret():
    global _secret
    if _secret is None:
        response = client.get_secret_value(SecretId=os.environ["SECRET_ARN"])
        _secret = json.loads(response["SecretString"])
    return _secret
```

### AWS Systems Manager Parameter Store
```hcl
resource "aws_ssm_parameter" "config" {
  name  = "/app/${var.environment}/db_host"
  type  = "SecureString"
  value = var.db_host
  key_id = aws_kms_key.ssm.arn
}

resource "aws_lambda_function" "this" {
  environment {
    variables = {
      SSM_PREFIX = "/app/${var.environment}/"
    }
  }
}
```

---

## 9. Concurrency & Scaling

### Scaling Behavior
- Lambda scales to match incoming request rate automatically.
- **Burst limit**: 3,000 concurrent executions immediately, then +500/minute until regional limit.
- **Regional concurrency limit**: default 1,000 (soft limit, can request increase).

### Reserved Concurrency
- Guarantees capacity is reserved for a specific function.
- Also caps maximum concurrency for that function (cost control / downstream protection).
- Setting to 0 effectively disables the function.

```hcl
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name = aws_lambda_function.this.function_name
}

resource "aws_lambda_provisioned_concurrency_config" "this" {
  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.live.name
  provisioned_concurrent_executions = 10
}
```

```hcl
# Reserved concurrency - on the function itself
resource "aws_lambda_function" "this" {
  # ...
  reserved_concurrent_executions = 50  # -1 = unreserved, 0 = throttle all
}
```

### Provisioned Concurrency
- Pre-warms execution environments to eliminate cold starts.
- Billed even when idle.
- Must be on an **alias** or **published version** (not $LATEST).

```hcl
resource "aws_lambda_provisioned_concurrency_config" "this" {
  function_name                     = aws_lambda_function.this.function_name
  qualifier                         = aws_lambda_alias.live.name  # or version number
  provisioned_concurrent_executions = 5
}
```

### Auto-Scaling Provisioned Concurrency
```hcl
resource "aws_appautoscaling_target" "lambda" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "function:${aws_lambda_function.this.function_name}:${aws_lambda_alias.live.name}"
  scalable_dimension = "lambda:function:ProvisionedConcurrency"
  service_namespace  = "lambda"
}

resource "aws_appautoscaling_policy" "lambda" {
  name               = "lambda-provisioned-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.lambda.resource_id
  scalable_dimension = aws_appautoscaling_target.lambda.scalable_dimension
  service_namespace  = aws_appautoscaling_target.lambda.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 0.7  # 70% utilization

    predefined_metric_specification {
      predefined_metric_type = "LambdaProvisionedConcurrencyUtilization"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

---

## 10. Execution Lifecycle

### Init Phase (Cold Start)
- Downloads code from S3/ECR.
- Starts runtime process.
- Runs **initialization code** outside handler (module-level / class-level).
- Initializes Lambda extensions.
- Duration billed as part of first invocation.

### Handler Execution
- Per-invocation code runs.
- Can access `/tmp` (ephemeral, persistent within same execution environment).
- Can reuse DB connections, HTTP clients, SDK clients initialized outside handler.

### Shutdown Phase
- SIGTERM sent to handler + extensions.
- 2 second window for graceful shutdown.
- Use `SIGTERM` handler to flush buffers, close connections.

```python
import signal
import sys

def handler(event, context):
    pass

def cleanup(signum, frame):
    # Flush logs, close connections
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
```

### Execution Environment Reuse
- After invocation, environment kept warm for ~5-15 minutes (varies).
- `/tmp` contents, global variables, DB connections persist across warm invocations.
- Do NOT store sensitive per-request state in globals.

---

## 11. Destinations & Error Handling

### Async Invocation Retry
- Lambda retries async invocations **twice** (3 total attempts) by default.
- Between retries: ~1 min, then ~2 min wait.
- Configure max age of event and max retry attempts.

```hcl
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.live.name  # or "$LATEST"

  maximum_event_age_in_seconds = 3600  # 60-21600
  maximum_retry_attempts       = 1     # 0-2

  destination_config {
    on_success {
      destination = aws_sqs_queue.success.arn  # SQS, SNS, Lambda, EventBridge
    }
    on_failure {
      destination = aws_sqs_queue.dlq.arn
    }
  }
}
```

### Dead Letter Queue (legacy, pre-destinations)
```hcl
resource "aws_lambda_function" "this" {
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn  # or SNS topic ARN
  }
}
```

### SQS DLQ for Lambda
- After all retries exhausted, messages go to DLQ.
- Set `maxReceiveCount` on the SQS redrive policy.

```hcl
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.function_name}-dlq"
  message_retention_seconds  = 1209600  # 14 days
  kms_master_key_id          = aws_kms_key.sqs.id
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.function_name}-queue"
  visibility_timeout_seconds = 300  # > lambda timeout

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
```

### Error Handling Patterns (ESM)
- **SQS**: `ReportBatchItemFailures` — return `batchItemFailures` from handler to retry only failed items.
- **Kinesis/DynamoDB Streams**: `bisect_batch_on_function_error = true` splits batch to find poison pill.
- **Kinesis/DynamoDB**: `destination_config.on_failure` sends failed records to SQS/SNS/S3.

---

## 12. Aliases & Versions

### Versions
- Immutable snapshots of function code + config.
- `$LATEST` is the mutable version.
- Published with `publish = true` on function resource.
- ARN: `arn:aws:lambda:region:account:function:name:version_number`

### Aliases
- Named pointers to one or two versions.
- Used for traffic shifting (canary/blue-green deployments).
- ARN: `arn:aws:lambda:region:account:function:name:alias_name`

```hcl
resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Production alias"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version

  # Weighted traffic shifting (canary)
  routing_config {
    additional_version_weights = {
      (aws_lambda_function.this.version) = 0.1  # 10% to new version
    }
  }
}
```

### CodeDeploy Traffic Shifting (with AppSpec)
```hcl
resource "aws_codedeploy_deployment_group" "lambda" {
  deployment_group_name  = "${var.function_name}-dg"
  deployment_config_name = "CodeDeployDefault.LambdaCanary10Percent5Minutes"
  app_name               = aws_codedeploy_app.this.name
  service_role_arn       = aws_iam_role.codedeploy.arn

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
}
```

---

## 13. Lambda URLs

- Built-in HTTPS endpoint for Lambda (no API Gateway needed).
- Supports two auth types: `AWS_IAM` or `NONE` (public).
- Supports CORS.
- Supports response streaming (write response progressively).

```hcl
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.live.name  # optional
  authorization_type = "AWS_IAM"  # or "NONE"

  cors {
    allow_credentials = true
    allow_origins     = ["https://myapp.com"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["Content-Type", "Authorization"]
    expose_headers    = ["X-Custom-Header"]
    max_age           = 86400
  }

  invoke_mode = "BUFFERED"  # or "RESPONSE_STREAM"
}

output "lambda_url" {
  value = aws_lambda_function_url.this.function_url
}
```

### Response Streaming (Node.js)
- `invoke_mode = "RESPONSE_STREAM"` (Node.js 18+ only currently).
- Allows streaming data to clients before function completes.
- Useful for LLM responses, large file generation, etc.

---

## 14. Container Image Functions

- Package Lambda as Docker image (up to **10 GB**).
- Must implement Lambda Runtime Interface Client (RIC).
- Use AWS base images (`public.ecr.aws/lambda/python:3.12`) or build from scratch.

```hcl
resource "aws_ecr_repository" "lambda" {
  name                 = var.function_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_lambda_function" "container" {
  function_name = var.function_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"

  image_uri = "${aws_ecr_repository.lambda.repository_url}:${var.image_tag}"

  image_config {
    command           = ["app.handler"]
    entry_point       = ["/lambda-entrypoint.sh"]
    working_directory = "/var/task"
  }

  memory_size   = 1024
  timeout       = 60
  architectures = ["arm64"]
}
```

### ECR Permissions for Lambda
```hcl
resource "aws_ecr_repository_policy" "lambda" {
  repository = aws_ecr_repository.lambda.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LambdaECRImageRetrievalPolicy"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = [
        "ecr:BatchGetImage",
        "ecr:DeleteRepositoryPolicy",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:SetRepositoryPolicy"
      ]
    }]
  })
}
```

---

## 15. Extensions

### What Are Extensions
- Processes that run alongside the Lambda function handler in the same execution environment.
- Can hook into lifecycle events: `Init`, `Invoke`, `Shutdown`.
- Used for monitoring, observability, secrets fetching, etc.
- Internal (same process) or External (separate process).

### Lambda Insights Extension
- Enhanced CloudWatch metrics (memory, CPU, cold start duration, etc.).
- Deployed as a layer.

```hcl
locals {
  # Check latest version at: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versions.html
  insights_layer_arm64 = "arn:aws:lambda:${var.region}:580247275435:layer:LambdaInsightsExtension-Arm64:20"
  insights_layer_x86   = "arn:aws:lambda:${var.region}:580247275435:layer:LambdaInsightsExtension:38"
}

resource "aws_lambda_function" "this" {
  layers = [local.insights_layer_arm64]
  # ...
}
```

### Secrets Manager Extension
- Caches secrets locally with TTL, avoiding per-invocation API calls.
- ARN varies by region. Use SSM parameter `/aws/service/aws-secrets-manager-extension-arn`.

### ADOT (AWS Distro for OpenTelemetry) Extension
```hcl
resource "aws_lambda_function" "this" {
  layers = [
    "arn:aws:lambda:${var.region}:901920570463:layer:aws-otel-python-arm64-ver-1-21-0:1"
  ]

  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER  = "/opt/otel-instrument"
      OPENTELEMETRY_COLLECTOR_CONFIG_FILE = "/var/task/collector.yaml"
    }
  }
}
```

---

## 16. Cold Starts & Performance Tuning

### What Causes Cold Starts
- New execution environment created (scale-out or first invocation).
- Duration: runtime download + init + user code init.
- Java/dotNET typically longest (100ms-10s). Python/Node fastest (50-500ms).

### Mitigation Strategies
| Strategy | How | Terraform |
|---|---|---|
| Provisioned Concurrency | Pre-warm envs | `aws_lambda_provisioned_concurrency_config` |
| Smaller package | Only include required code | Package optimization |
| Arm64 (Graviton2) | Faster init, cheaper | `architectures = ["arm64"]` |
| Avoid VPC (if possible) | VPC adds latency | Remove `vpc_config` |
| Move SDK clients outside handler | Reused across warm invocations | Code pattern |
| SnapStart (Java only) | Snapshot after init | `snap_start { apply_on = "PublishedVersions" }` |

### Lambda SnapStart (Java 11+)
```hcl
resource "aws_lambda_function" "java" {
  runtime = "java21"
  publish = true  # Required

  snap_start {
    apply_on = "PublishedVersions"  # or "None"
  }
}
```

### Memory & CPU Relationship
- CPU allocated **proportionally to memory**.
- 1,769 MB = 1 full vCPU.
- For CPU-bound tasks: increasing memory reduces duration (net cost-neutral or cheaper).
- Use AWS Lambda Power Tuning (open source Step Functions tool) to find optimal memory.

### Timeout Best Practices
- Set timeout slightly above p99 of expected duration.
- Too short → false timeouts. Too long → cost overrun on hung functions.
- SQS visibility timeout must be >= Lambda timeout × 6 (for ESM polling).

---

## 17. Observability — Logging

### CloudWatch Logs
- Lambda automatically sends stdout/stderr to `/aws/lambda/<function_name>` log group.
- Each execution environment writes to a unique log stream.

```hcl
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.logs.arn  # optional encryption

  tags = var.tags
}
```

> **Note**: Create the log group in Terraform BEFORE deploying the function, otherwise Lambda auto-creates it without retention/KMS settings.

### Log Formats
- Default: unstructured text.
- **Structured JSON logging** (recommended): enables CloudWatch Logs Insights queries on fields.

```python
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(json.dumps({
        "message": "Processing request",
        "request_id": context.aws_request_id,
        "function_name": context.function_name,
        "remaining_ms": context.get_remaining_time_in_millis(),
    }))
```

### Lambda-Managed Log Format (Advanced Logging Controls)
- New feature: native JSON structured logs from Lambda itself.
- Control log level and format without code changes.

```hcl
resource "aws_lambda_function" "this" {
  logging_config {
    log_format            = "JSON"      # "Text" or "JSON"
    log_group             = "/aws/lambda/${var.function_name}"
    application_log_level = "INFO"      # TRACE, DEBUG, INFO, WARN, ERROR, FATAL
    system_log_level      = "WARN"      # TRACE, DEBUG, INFO, WARN
  }
}
```

### CloudWatch Logs Insights Queries

```
# Find errors in last 1 hour
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50

# Avg duration by function
stats avg(duration) as avgDuration, max(duration) as maxDuration
by functionVersion
| sort avgDuration desc

# Cold start analysis
filter @message like /Init Duration/
| parse @message "Init Duration: * ms" as initDuration
| stats avg(initDuration), count() by bin(5min)

# JSON log querying
fields @timestamp, level, message, request_id
| filter level = "ERROR"
| sort @timestamp desc
```

### Log Subscription (streaming to other services)
```hcl
resource "aws_cloudwatch_log_subscription_filter" "lambda" {
  name            = "lambda-log-filter"
  log_group_name  = aws_cloudwatch_log_group.lambda.name
  filter_pattern  = "[timestamp, requestId, level=\"ERROR\", ...]"
  destination_arn = aws_kinesis_firehose_delivery_stream.logs.arn
}
```

---

## 18. Observability — Metrics

### Built-in CloudWatch Metrics (namespace: `AWS/Lambda`)

| Metric | Description | Stat |
|---|---|---|
| `Invocations` | Total invocations | Sum |
| `Errors` | Invocations with function errors | Sum |
| `Throttles` | Throttled invocations | Sum |
| `Duration` | Execution time in ms | Avg, p50, p95, p99, Max |
| `ConcurrentExecutions` | Concurrent running executions | Max |
| `UnreservedConcurrentExecutions` | Concurrent executions from unreserved pool | Max |
| `ProvisionedConcurrencyInvocations` | Invocations using provisioned concurrency | Sum |
| `ProvisionedConcurrencyUtilization` | % of provisioned concurrency used | Max |
| `InitDuration` | Cold start init time | Avg, Max |
| `PostRuntimeExtensionsDuration` | Extension overhead after handler | Avg, Max |
| `AsyncEventsReceived` | Async events received | Sum |
| `AsyncEventAge` | Age of async events | Avg, Max |

### CloudWatch Alarms
```hcl
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "throttles" {
  alarm_name          = "${var.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "duration_p99" {
  alarm_name          = "${var.function_name}-duration-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = var.timeout_ms * 0.8  # alert at 80% of timeout

  metric_name = "Duration"
  namespace   = "AWS/Lambda"
  period      = 60
  extended_statistic = "p99"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

### CloudWatch Dashboard
```hcl
resource "aws_cloudwatch_dashboard" "lambda" {
  dashboard_name = "${var.function_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title  = "Invocations & Errors"
          period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.this.function_name, { stat = "Sum" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.this.function_name, { stat = "Sum", color = "#d62728" }],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "Duration (p50, p95, p99)"
          period = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.this.function_name, { stat = "p50" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.this.function_name, { stat = "p95" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.this.function_name, { stat = "p99" }],
          ]
        }
      }
    ]
  })
}
```

---

## 19. Observability — Tracing (X-Ray)

### Enable Active Tracing
```hcl
resource "aws_lambda_function" "this" {
  tracing_config {
    mode = "Active"  # "Active" or "PassThrough"
  }
}

# Required IAM
resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
```

### X-Ray Modes
| Mode | Description |
|---|---|
| `PassThrough` | Honors trace headers from upstream; no segments created unless sampled |
| `Active` | Always samples and creates segments, regardless of upstream |

### X-Ray SDK Usage (Python)
```python
from aws_xray_sdk.core import xray_recorder, patch_all

# Patch all supported libraries (boto3, requests, etc.)
patch_all()

@xray_recorder.capture("process_data")
def process_data(data):
    # Adds subsegment automatically
    pass

def handler(event, context):
    with xray_recorder.in_subsegment("custom-subsegment") as subsegment:
        subsegment.put_annotation("user_id", event["userId"])
        subsegment.put_metadata("payload", event)
        # do work
```

### X-Ray Groups & Sampling Rules
```hcl
resource "aws_xray_group" "lambda" {
  group_name        = var.function_name
  filter_expression = "resource.arn CONTAINS \"${aws_lambda_function.this.function_name}\""
}

resource "aws_xray_sampling_rule" "lambda" {
  rule_name      = "${var.function_name}-sampling"
  priority       = 1000
  version        = 1
  reservoir_size = 5
  fixed_rate     = 0.05  # 5%
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "AWS::Lambda::Function"
  service_name   = aws_lambda_function.this.function_name
  resource_arn   = "*"
}
```

---

## 20. Observability — CloudWatch Lambda Insights

### What It Provides
- Enhanced metrics per invocation stored in CW Logs structured format.
- Metrics: `memory_utilization`, `cpu_total_time`, `init_duration`, `shutdown_duration`, `rx_bytes`, `tx_bytes`, etc.
- Enables memory utilization alarms (not available in standard Lambda metrics).

```hcl
locals {
  # Arm64 layer ARNs: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versions.html
  lambda_insights_layer = "arn:aws:lambda:${var.region}:580247275435:layer:LambdaInsightsExtension-Arm64:20"
}

resource "aws_lambda_function" "this" {
  layers = [local.lambda_insights_layer]
}

# Required IAM for Lambda Insights
resource "aws_iam_role_policy_attachment" "insights" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}
```

### Memory Utilization Alarm
```hcl
resource "aws_cloudwatch_metric_alarm" "memory" {
  alarm_name          = "${var.function_name}-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "memory_utilization"
  namespace           = "LambdaInsights"
  period              = 60
  statistic           = "Maximum"
  threshold           = 85  # alert at 85% memory utilization

  dimensions = {
    function_name = aws_lambda_function.this.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

---

## 21. Debugging & Troubleshooting

### Common Error Types

| Error | Cause | Resolution |
|---|---|---|
| `Task timed out after X seconds` | Handler exceeded timeout | Increase timeout, optimize code, async patterns |
| `Runtime.OutOfMemory` | Process exceeded memory | Increase memory_size |
| `Runtime.HandlerNotFound` | Handler path wrong | Verify `handler` matches file/method |
| `AccessDeniedException` | Missing IAM permission | Check execution role policies |
| `TooManyRequestsException` | Throttled (concurrency) | Increase reserved concurrency or regional limit |
| `Runtime.ImportModuleError` | Missing dependency | Check layer or deployment package |
| `KMSDisabledException` | KMS key disabled | Check KMS key state |
| `ENILimitReached` | Too many VPC ENIs | Request limit increase or reduce subnet/SG combos |

### Local Testing

```bash
# AWS SAM CLI
sam local invoke MyFunction -e event.json
sam local start-api
sam local start-lambda

# AWS CLI invoke
aws lambda invoke \
  --function-name my-function \
  --payload '{"key": "value"}' \
  --log-type Tail \
  --query 'LogResult' \
  --output text response.json | base64 -d

# Invoke with qualifier
aws lambda invoke \
  --function-name my-function:live \
  --payload '{}' \
  response.json
```

### CloudWatch Logs Insights — Debug Queries

```
# Find specific request ID
fields @timestamp, @message
| filter @requestId = "abc-123"

# All errors with request IDs
fields @timestamp, @requestId, @message
| filter @message like /ERROR|Exception/
| sort @timestamp desc

# Timeout analysis
filter @message like /Task timed out/
| stats count() by bin(1h)

# Memory usage (with Lambda Insights)
fields @timestamp, memory_utilization, memory_size, function_name
| filter memory_utilization > 80
| sort @timestamp desc

# P99 latency per version
filter @type = "REPORT"
| parse @message "Duration: * ms" as duration
| parse @message "Memory Used: * MB" as memUsed
| stats avg(duration), pct(duration, 99), max(memUsed) by functionVersion
```

### Lambda-specific CloudWatch Log Events
```
START RequestId: abc-123 Version: $LATEST
END RequestId: abc-123
REPORT RequestId: abc-123  Duration: 123.45 ms  Billed Duration: 124 ms  Memory Size: 512 MB  Max Memory Used: 87 MB  Init Duration: 234.56 ms
```
- `Init Duration` only appears on cold starts.
- `Max Memory Used` — use this to right-size memory.

### Enable Debug Mode (runtime env var)
```hcl
resource "aws_lambda_function" "this" {
  environment {
    variables = {
      LOG_LEVEL              = "DEBUG"
      AWS_LAMBDA_LOG_LEVEL   = "DEBUG"  # For Lambda-managed log format
      POWERTOOLS_LOG_LEVEL   = "DEBUG"  # For Lambda Powertools
    }
  }
}
```

### EventBridge Debugging (dead-letter for EventBridge)
- When Lambda fails async invocations, events route to destination on_failure.
- Use EventBridge Archive and Replay to re-process events.

```hcl
resource "aws_cloudwatch_event_archive" "this" {
  name             = "${var.function_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = 30
}
```

---

## 22. Cost Model

### Pricing Components
1. **Requests**: $0.20 per 1M invocations (first 1M free/month).
2. **Duration**: $0.0000166667 per GB-second (x86), $0.0000133334 per GB-second (arm64).
3. **Provisioned Concurrency**: $0.000004646 per GB-second allocated (x86), lower for arm64.
4. **Ephemeral Storage**: Storage above 512 MB: $0.0000000309 per GB-second.
5. **Data Transfer**: Standard EC2 data transfer rates.

### Cost Optimization
- Use **arm64** (Graviton2) — 20% cheaper, often faster.
- Right-size memory with Lambda Power Tuning.
- Avoid over-provisioning provisioned concurrency.
- Use SQS batching to reduce invocation count.
- Aggregate logs before sending to CloudWatch (reduce PUT requests).
- Use S3 intelligent tiering for deployment artifacts.
- Delete old Lambda versions not referenced by aliases.

```hcl
# Auto-cleanup old lambda versions (using custom resource or Lambda)
# There's no native Terraform support; use aws_lambda_function with lifecycle
resource "aws_lambda_function" "this" {
  lifecycle {
    create_before_destroy = true
  }
}
```

---

## 23. Limits & Quotas

| Resource | Limit | Adjustable |
|---|---|---|
| Concurrent executions (per region) | 1,000 | Yes |
| Function timeout | 900 seconds (15 min) | No |
| Memory | 128 MB – 10,240 MB | No |
| Ephemeral storage `/tmp` | 512 MB – 10,240 MB | No |
| Deployment package (zip, S3) | 250 MB unzipped | No |
| Container image size | 10 GB | No |
| Layers per function | 5 | No |
| Env variables total size | 4 KB | No |
| Function resource policy | 20 KB | No |
| Invocation payload (sync) | 6 MB (request + response) | No |
| Invocation payload (async) | 256 KB | No |
| VPC ENIs per VPC | 250 | Yes |
| Burst concurrency | 3,000 | Yes |
| Functions per region | 75 (soft) | Yes |
| Versions per function | 75 (soft) | Yes |

---

## 24. Security Best Practices

### Principle of Least Privilege
- One role per function.
- Use resource-level permissions (not `*`).
- Use condition keys: `aws:SourceArn`, `aws:SourceAccount`.

### Encryption
- Env vars: use customer managed KMS key (`kms_key_arn`).
- In-transit: Lambda always uses TLS for internal communication.
- Artifacts: S3 bucket with SSE-KMS.
- Logs: KMS-encrypted log groups.

### Network Security
- Run in private subnets.
- Restrictive security groups (egress only to needed services).
- Use VPC endpoints to avoid internet for AWS API calls.
- Block public internet egress if not needed (no NAT GW, no IGW route).

### Code Security
- Never hardcode secrets. Use Secrets Manager or Parameter Store.
- Pin dependency versions and scan with tools like Snyk, Dependabot.
- Enable ECR image scanning for container functions.
- Use `reserved_concurrent_executions` to limit blast radius.

### Code Signing (Integrity)
```hcl
resource "aws_signer_signing_profile" "lambda" {
  platform_id = "AWSLambda-SHA384-ECDSA"
  name        = "${var.function_name}-signing-profile"

  signature_validity_period {
    value = 5
    type  = "YEARS"
  }
}

resource "aws_lambda_code_signing_config" "this" {
  description = "Code signing for ${var.function_name}"

  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.lambda.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"  # or "Warn"
  }
}

resource "aws_lambda_function" "this" {
  code_signing_config_arn = aws_lambda_code_signing_config.this.arn
}
```

---

### Terraform Resource Quick Reference Table

| Resource | Purpose |
|---|---|
| `aws_lambda_function` | Core function config |
| `aws_lambda_alias` | Alias (live, canary, etc.) |
| `aws_lambda_permission` | Resource-based policy (who can invoke) |
| `aws_lambda_event_source_mapping` | SQS/Kinesis/DDB/MSK/Kafka polling |
| `aws_lambda_function_url` | Built-in HTTPS URL |
| `aws_lambda_function_event_invoke_config` | Async retry + destinations |
| `aws_lambda_layer_version` | Shared dependencies/extensions |
| `aws_lambda_provisioned_concurrency_config` | Provisioned concurrency |
| `aws_lambda_code_signing_config` | Code signing enforcement |
| `aws_cloudwatch_log_group` | Pre-create log group with retention/KMS |
| `aws_cloudwatch_metric_alarm` | Alerts on errors, throttles, duration |
| `aws_cloudwatch_dashboard` | Operational dashboard |
| `aws_xray_sampling_rule` | Custom X-Ray sampling |
| `aws_xray_group` | X-Ray service group / filter |
| `aws_appautoscaling_target` | Auto-scale provisioned concurrency target |
| `aws_appautoscaling_policy` | Auto-scale policy (target tracking) |
| `aws_iam_role` | Execution role |
| `aws_iam_role_policy` | Inline policy on role |
| `aws_iam_role_policy_attachment` | Attach managed policies |
| `aws_sqs_queue` | DLQ or trigger queue |
| `aws_sqs_queue_policy` | Allow Lambda to send to SQS |
| `aws_s3_bucket_notification` | S3 event trigger |
| `aws_cloudwatch_event_rule` | EventBridge schedule/pattern |
| `aws_cloudwatch_event_target` | EventBridge → Lambda target |
| `aws_cloudwatch_log_subscription_filter` | Stream logs to Firehose/Lambda |
| `aws_signer_signing_profile` | Code signing profile |
| `aws_ecr_repository` | Container image registry (for Image package type) |
| `archive_file` (data source) | Create zip deployment package |

---

*Last updated: February 2026 — Covers Lambda up to AWS feature releases as of this date.*
*Next service notes: API Gateway, DynamoDB, ECS, SQS, EventBridge, Step Functions.*