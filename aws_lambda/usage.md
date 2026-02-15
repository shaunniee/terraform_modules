# AWS Lambda Terraform Module

Terraform module for creating a Lambda function with:
- Optional module-managed IAM execution role (or existing role support)
- Deployment package from local zip file or S3
- Dead-letter target (SQS/SNS)
- Architectures, layers, ephemeral storage, reserved concurrency
- Optional KMS encryption for Lambda environment variables
- Optional managed CloudWatch log group with retention + KMS
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

## Package Source Rules

- Set exactly one source type:
  - `filename`, or
  - `s3_bucket` + `s3_key`
- `filename` must point to an existing `.zip` file.
