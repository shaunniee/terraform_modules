# AWS Lambda Terraform Module

Terraform module for creating a Lambda function with:
- Optional module-managed IAM execution role (or existing role support)
- Optional opt-in IAM permissions for logging, monitoring, and tracing
- Optional Lambda X-Ray tracing configuration
- Deployment package from local zip file or S3
- Dead-letter target (SQS/SNS)
- Architectures, layers, ephemeral storage, reserved concurrency
- Optional KMS encryption for Lambda environment variables
- Optional managed CloudWatch log group with retention + KMS
- Optional dynamic CloudWatch metric alarms
- Optional DLQ-specific CloudWatch metric alarms
- Optional DLQ log metric filters
- Optional Lambda aliases (including weighted routing)

## Basic Usage

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "my-function"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "artifacts/lambda.zip"
}
```

## Permission Toggles Example (Test vs Production)

```hcl
# Testing profile: enable observability permissions
module "lambda_test" {
  source = "./aws_lambda"

  function_name = "orders-processor-test"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-processor.zip"

  tracing_mode                  = "Active"
  enable_logging_permissions    = true
  enable_monitoring_permissions = true
  enable_tracing_permissions    = true
}

# Production profile: tighter IAM by default
module "lambda_prod" {
  source = "./aws_lambda"

  function_name = "orders-processor-prod"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-processor.zip"

  tracing_mode                  = "PassThrough"
  enable_logging_permissions    = false
  enable_monitoring_permissions = false
  enable_tracing_permissions    = false
}
```

## Advanced Usage (Managed Role)

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-processor"
  description   = "Processes order events"
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  filename      = "build/orders-processor.zip"

  timeout      = 30
  memory_size  = 512
  publish      = true
  architectures = ["arm64"]
  layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:shared-utils:4"]

  ephemeral_storage_size         = 1024
  reserved_concurrent_executions = 20
  kms_key_arn                    = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

  create_cloudwatch_log_group = true
  log_retention_in_days       = 30
  log_group_kms_key_arn       = "arn:aws:kms:us-east-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  dead_letter_target_arn = "arn:aws:sqs:us-east-1:123456789012:orders-dlq"

  environment_variables = {
    STAGE     = "prod"
    LOG_LEVEL = "info"
  }

  tags = {
    Environment = "prod"
    Service     = "orders"
    ManagedBy   = "terraform"
  }
}
```

## Existing Execution Role Example

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "billing-worker"
  runtime       = "python3.12"
  handler       = "handler.main"
  filename      = "build/billing-worker.zip"

  execution_role_arn = "arn:aws:iam::123456789012:role/existing-lambda-execution-role"

  create_cloudwatch_log_group = false
}
```

## S3 Package Example

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "reports-worker"
  runtime       = "python3.12"
  handler       = "handler.main"

  s3_bucket         = "my-lambda-artifacts"
  s3_key            = "releases/reports-worker.zip"
  s3_object_version = "3Lg7Rk...."
}
```

## Alias Example

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "payments-handler"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/payments-handler.zip"
  publish       = true

  tracing_mode = "Active"

  aliases = {
    live = {
      description      = "Production alias"
      function_version = null
    }
    canary = {
      description      = "Canary traffic split"
      function_version = "12"
      routing_additional_version_weights = {
        "13" = 0.1
      }
    }
  }
}
```

## Tracing + Dynamic Metric Alarms Example

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-processor"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-processor.zip"

  tracing_mode = "Active"

  metric_alarms = {
    errors = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "Errors"
      period              = 60
      statistic           = "Sum"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    throttles = {
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "Throttles"
      period              = 60
      statistic           = "Sum"
      threshold           = 0
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    duration_p95 = {
      alarm_name          = "orders-processor-duration-p95"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      metric_name         = "Duration"
      period              = 60
      extended_statistic  = "p95"
      threshold           = 500
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }
}
```

## Boolean-First Observability Example (Recommended)

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-processor"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-processor.zip"

  observability = {
    enabled                         = true
    enable_default_alarms           = true
    enable_anomaly_detection_alarms = true
    default_alarm_actions           = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
  }
}
```

## Observability Scenario Reference

Use this section to quickly pick a configuration pattern.

| Scenario | `observability` | Other blocks | Best for |
|---|---|---|---|
| No observability | `enabled = false` | none | local/dev with external monitoring |
| Presets only | `enabled = true`, `enable_default_alarms = true` | optional shared actions | fast baseline alerting |
| Presets + custom overrides | same as above | `metric_alarms` | keep defaults and tune specific thresholds |
| Anomaly only | `enabled = true`, `enable_default_alarms = false`, `enable_anomaly_detection_alarms = true` | optional `metric_anomaly_alarms` | spiky/seasonal traffic |
| Custom alarms only | `enabled = false` | `metric_alarms` | full manual control |
| DLQ focused | any | `dead_letter_target_arn`, `dlq_cloudwatch_metric_alarms`, `dlq_log_metric_filters` | async failure visibility |
| External IAM role | any | `execution_role_arn`, optional `create_cloudwatch_log_group = false` | centralized IAM ownership |

### Scenario A: Minimal (No observability)

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-dev"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-dev.zip"

  observability = {
    enabled = false
  }
}
```

### Scenario B: Preset alarms only

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-api"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-api.zip"

  observability = {
    enabled               = true
    enable_default_alarms = true
    default_alarm_actions = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
  }
}
```

### Scenario C: Presets + override one default + add one custom alarm

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-api"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-api.zip"

  observability = {
    enabled               = true
    enable_default_alarms = true
  }

  metric_alarms = {
    errors = {
      enabled             = true
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "Errors"
      period              = 60
      statistic           = "Sum"
      threshold           = 5
      treat_missing_data  = "notBreaching"
    }

    iterator_age = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 3
      metric_name         = "IteratorAge"
      period              = 60
      statistic           = "Maximum"
      threshold           = 60000
      treat_missing_data  = "notBreaching"
    }
  }
}
```

### Scenario D: Anomaly alarms only

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-worker"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-worker.zip"

  observability = {
    enabled                         = true
    enable_default_alarms           = false
    enable_anomaly_detection_alarms = true
  }
}
```

### Scenario E: Fully custom alarms only (no presets)

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "billing-worker"
  runtime       = "python3.12"
  handler       = "handler.main"
  filename      = "build/billing-worker.zip"

  observability = {
    enabled = false
  }

  metric_alarms = {
    duration_p99 = {
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 5
      metric_name         = "Duration"
      period              = 60
      extended_statistic  = "p99"
      threshold           = 1200
      treat_missing_data  = "notBreaching"
    }
  }

  metric_anomaly_alarms = {
    invocations_anomaly_custom = {
      comparison_operator      = "GreaterThanUpperThreshold"
      evaluation_periods       = 2
      metric_name              = "Invocations"
      period                   = 300
      statistic                = "Sum"
      anomaly_detection_stddev = 3
      treat_missing_data       = "notBreaching"
    }
  }
}
```

### Scenario F: External IAM + explicit observability permissions

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "payments-handler"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/payments-handler.zip"

  execution_role_arn = "arn:aws:iam::123456789012:role/existing-lambda-execution-role"

  enable_logging_permissions    = false
  enable_monitoring_permissions = false
  enable_tracing_permissions    = false

  create_cloudwatch_log_group = false

  observability = {
    enabled               = true
    enable_default_alarms = true
  }
}
```

## DLQ Observability Example (Metrics, Alarms, Logs)

```hcl
module "lambda" {
  source = "./aws_lambda"

  function_name = "orders-processor"
  runtime       = "python3.12"
  handler       = "app.lambda_handler"
  filename      = "build/orders-processor.zip"

  dead_letter_target_arn = "arn:aws:sqs:us-east-1:123456789012:orders-dlq"

  dlq_cloudwatch_metric_alarms = {
    dlq_visible_messages = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "ApproximateNumberOfMessagesVisible"
      period              = 60
      statistic           = "Maximum"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    dlq_oldest_message_age = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 3
      metric_name         = "ApproximateAgeOfOldestMessage"
      period              = 60
      statistic           = "Maximum"
      threshold           = 300
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }

  dlq_log_metric_filters = {
    async_dlq_delivery_failures = {
      pattern          = "\"DeadLetterErrors\""
      metric_namespace = "Custom/LambdaDLQ"
      metric_name      = "DeadLetterErrorsFromLogs"
    }
  }
}
```

Notes:
- `dlq_cloudwatch_metric_alarms` requires `dead_letter_target_arn` and auto-infers dimensions:
  - SQS DLQ: `QueueName=<queue name>` with default namespace `AWS/SQS`
  - SNS DLQ: `TopicName=<topic name>` with default namespace `AWS/SNS`
- `dlq_log_metric_filters` creates CloudWatch log metric filters on `/aws/lambda/<function_name>`.
- If `create_cloudwatch_log_group = false` and `dlq_log_metric_filters` are set, the log group `/aws/lambda/<function_name>` must already exist.
- Lambda DLQ payloads are stored in SQS/SNS; payload-level logging still requires a DLQ consumer (Lambda/worker) that reads and logs messages.

Notes:
- The module always injects `FunctionName = <lambda function name>` into alarm dimensions.
- `dimensions` in each alarm can add dimensions, but cannot override `FunctionName`.
- `metric_alarms` supports `enabled = true|false` per alarm entry.
- Preset alarms are created when `observability.enabled = true` and `observability.enable_default_alarms = true` (`Errors`, `Throttles`, `Duration p95`).
- Anomaly alarms are created when `observability.enabled = true` and `observability.enable_anomaly_detection_alarms = true`, and can be customized via `metric_anomaly_alarms`.
- `enable_logging_permissions` controls attachment of `AWSLambdaBasicExecutionRole` when the module creates the role (enabled by default).
- `enable_monitoring_permissions` controls attachment of `CloudWatchLambdaInsightsExecutionRolePolicy` when the module creates the role.
- `enable_tracing_permissions` controls attachment of `AWSXRayDaemonWriteAccess` when `tracing_mode = "Active"` and the module creates the role.
- If you pass `execution_role_arn`, ensure that external role includes any logging/monitoring/tracing permissions your function needs.

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `function_name` | string | - | Yes | Lambda function name (1-64, alphanumeric, `-`, `_`) |
| `runtime` | string | - | Yes | Lambda runtime |
| `handler` | string | - | Yes | Lambda handler |
| `filename` | string | `null` | Conditional | Local path to deployment zip file |
| `source_code_hash` | string | `null` | No | Optional package hash (auto-computed for local file source) |
| `s3_bucket` | string | `null` | Conditional | S3 bucket containing deployment zip |
| `s3_key` | string | `null` | Conditional | S3 key containing deployment zip |
| `s3_object_version` | string | `null` | No | S3 object version for deployment zip |
| `execution_role_arn` | string | `null` | No | Existing IAM role ARN. If null, module creates role |
| `enable_logging_permissions` | bool | `true` | No | Attach `AWSLambdaBasicExecutionRole` when module creates role |
| `enable_monitoring_permissions` | bool | `false` | No | Attach `CloudWatchLambdaInsightsExecutionRolePolicy` when module creates role |
| `enable_tracing_permissions` | bool | `false` | No | Attach `AWSXRayDaemonWriteAccess` when tracing is active and module creates role |
| `description` | string | `null` | No | Lambda description |
| `timeout` | number | `3` | No | Timeout in seconds (1-900) |
| `memory_size` | number | `128` | No | Memory in MB (128-10240) |
| `publish` | bool | `false` | No | Publish new version on updates |
| `architectures` | list(string) | `["x86_64"]` | No | Exactly one of `x86_64` or `arm64` |
| `layers` | list(string) | `[]` | No | Lambda layer version ARNs |
| `ephemeral_storage_size` | number | `512` | No | `/tmp` size in MB (512-10240) |
| `reserved_concurrent_executions` | number | `-1` | No | Reserved concurrency (`-1` for unreserved) |
| `kms_key_arn` | string | `null` | No | KMS key ARN for environment variable encryption |
| `create_cloudwatch_log_group` | bool | `true` | No | Create CloudWatch log group |
| `log_retention_in_days` | number | `14` | No | CloudWatch retention value |
| `log_group_kms_key_arn` | string | `null` | No | KMS key ARN for log group encryption |
| `aliases` | map(object) | `{}` | No | Lambda aliases keyed by alias name |
| `tracing_mode` | string | `"PassThrough"` | No | Lambda X-Ray tracing mode (`PassThrough` or `Active`) |
| `observability` | object | disabled | No | Boolean-first observability toggles and shared alarm actions |
| `metric_alarms` | map(object) | `{}` | No | Dynamic CloudWatch metric alarms keyed by logical name |
| `metric_anomaly_alarms` | map(object) | `{}` | No | CloudWatch anomaly detection alarms keyed by logical name |
| `dlq_cloudwatch_metric_alarms` | map(object) | `{}` | No | DLQ-specific CloudWatch metric alarms (requires `dead_letter_target_arn`) |
| `dlq_log_metric_filters` | map(object) | `{}` | No | DLQ-related CloudWatch log metric filters on Lambda log group |
| `environment_variables` | map(string) | `{}` | No | Lambda environment variables |
| `dead_letter_target_arn` | string | `null` | No | SQS/SNS ARN for failed async invocations |
| `tags` | map(string) | `{}` | No | Resource tags |

## Outputs

| Output | Description |
|--------|-------------|
| `lambda_role_name` | IAM role name created by module (or `null` when external role used) |
| `lambda_role_arn` | IAM role ARN used by Lambda |
| `lambda_function_name` | Lambda function name |
| `lambda_function_invoke_arn` | Lambda invoke ARN |
| `lambda_version` | Published version / version reference |
| `lambda_arn` | Lambda function ARN |
| `cloudwatch_log_group_name` | Log group name when module creates it |
| `lambda_alias_arns` | Map of alias ARNs keyed by alias name |
| `lambda_alias_invoke_arns` | Map of alias invoke ARNs keyed by alias name |
| `cloudwatch_metric_alarm_arns` | Map of metric alarm ARNs keyed by `metric_alarms` key |
| `cloudwatch_metric_alarm_names` | Map of metric alarm names keyed by `metric_alarms` key |
| `cloudwatch_metric_anomaly_alarm_arns` | Map of anomaly alarm ARNs keyed by `metric_anomaly_alarms` key |
| `cloudwatch_metric_anomaly_alarm_names` | Map of anomaly alarm names keyed by `metric_anomaly_alarms` key |
| `dlq_cloudwatch_metric_alarm_arns` | Map of DLQ metric alarm ARNs keyed by `dlq_cloudwatch_metric_alarms` key |
| `dlq_cloudwatch_metric_alarm_names` | Map of DLQ metric alarm names keyed by `dlq_cloudwatch_metric_alarms` key |
| `dlq_log_metric_filter_names` | Map of DLQ log metric filter names keyed by `dlq_log_metric_filters` key |

## Package Source Rules

- Set exactly one source type:
  - `filename`, or
  - `s3_bucket` + `s3_key`
- `filename` must point to an existing `.zip` file.
