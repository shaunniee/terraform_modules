# Terraform Modules

Reusable Terraform modules for common AWS infrastructure patterns.

## Implemented Modules

| Module | Purpose | Docs |
|--------|---------|------|
| `aws_s3` | S3 bucket with encryption, lifecycle, CORS, logging, replication | `aws_s3/usage.md` |
| `aws_ssm` | SSM Parameter Store module for plain and secure parameters with validation and policy support | `aws_ssm/usage.md` |
| `aws_dynamodb` | Dynamic DynamoDB table module with billing modes, GSIs/LSIs, TTL, streams, PITR, and SSE | `aws_dynamodb/usage.md` |
| `aws_cloudfront` | CloudFront distribution with multi-origin support, SPA fallback, signed URLs, custom domains, WAF, logging | `aws_cloudfront/usage.md` |
| `aws_lambda` | Lambda function with optional managed IAM role, layers, KMS, concurrency controls, and log group management | `aws_lambda/usage.md` |
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
