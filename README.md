# Terraform Modules

Reusable Terraform modules for common AWS infrastructure patterns.

## Guides

- [IAM Companion Guide](IAM_GUIDE.md) - recommended IAM separation model, module patterns, and review checklist.

## Implemented Modules

| Module | Purpose | Docs |
|--------|---------|------|
| `aws_s3` | S3 bucket with encryption, lifecycle, CORS, logging, replication | `aws_s3/usage.md` |
| `aws_ssm` | SSM Parameter Store module for plain and secure parameters with validation and policy support | `aws_ssm/usage.md` |
| `aws_dynamodb` | Dynamic DynamoDB table module with billing modes, GSIs/LSIs, TTL, streams, PITR, and SSE | `aws_dynamodb/usage.md` |
| `aws_ses` | Dynamic SES module for identities, DKIM, MAIL FROM, policies, configuration sets, event destinations, and templates | `aws_ses/usage.md` |
| `aws_cloudfront` | CloudFront distribution with multi-origin support, SPA fallback, signed URLs, custom domains, WAF, logging | `aws_cloudfront/usage.md` |
| `aws_acm` | ACM certificate module for single/multiple certificates with optional Route53 DNS validation records | `aws_acm/usage.md` |
| `aws_cognito` | Cognito User Pool and User Pool Client module with optional Identity Pool, domain, and Lambda triggers | `aws_cognito/usage.md` |
| `aws_kms` | KMS key and alias module for creating multiple keys with rotation, deletion window, and optional policy | `aws_kms/usage.md` |
| `aws_lambda` | Lambda function with optional managed IAM role, layers, KMS, concurrency controls, and log group management | `aws_lambda/usage.md` |
| `aws_lambda_layer` | Reusable Lambda layer publishing module with local/S3 sources and sharing permissions | `aws_lambda_layer/usage.md` |
| `aws_eventbridge` | Dynamic EventBridge module for buses, rules, targets, retries, DLQ, and optional Lambda invoke permissions | `aws_eventbridge/usage.md` |
| `aws_sqs` | SQS queue module with optional dead-letter queue and redrive policy wiring | `aws_sqs/usage.md` |
| `aws_api_gateway_rest_api` | Dynamic REST API Gateway with submodules for resources, methods, integrations, responses, stage, logs, and optional custom domain | `aws_api_gateway_rest_api/usage.md` |

## Prerequisites

- Terraform `>= 1.3` (recommended)
- AWS provider configured in the root stack
- Valid AWS credentials and region

## Quick Start

Use modules from this repo locally:

```hcl
module "s3" {
  source = "./aws_s3"

  bucket_name = "my-unique-bucket-name"
}
```

Use modules from GitHub:

```hcl
module "s3" {
  source = "git::https://github.com/shaunniee/terraform_modules.git//aws_s3?ref=main"

  bucket_name = "my-unique-bucket-name"
}
```

Then run:

```bash
terraform init
terraform plan
terraform apply
```

## Module Notes

- `aws_cloudfront` supports both `default_cache_behavior` (preferred) and `default_cache_behaviour` (deprecated).
- `aws_lambda` supports either:
  - module-created execution role (default), or
  - existing role via `execution_role_arn`.
- `aws_s3` output file is currently named `aws_s3/ouputs.tf` (typo in filename, functionality still works).
