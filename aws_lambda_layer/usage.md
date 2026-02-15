# AWS Lambda Layer Terraform Module

Reusable module for publishing Lambda layers from local zip or S3 source, with optional sharing permissions.

## Features

- Publish Lambda layer versions
- Supports local zip (`filename`) or S3 source (`s3_bucket` + `s3_key`)
- Optional compatible runtimes and architectures
- Optional layer permissions for account/public/organization sharing

## Basic Usage (Local Zip)

```hcl
module "shared_layer" {
  source = "./aws_lambda_layer"

  layer_name          = "shared-utils"
  description         = "Shared dependencies for admin services"
  compatible_runtimes = ["nodejs22.x"]
  compatible_architectures = ["arm64"]

  filename = "build/layers/shared-utils.zip"
}

module "admin_posts_lambda" {
  source = "./aws_lambda"

  function_name = "admin-blog-posts"
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  filename      = "build/admin-blog-posts.zip"
  publish       = true

  layers = [module.shared_layer.layer_arn]
}
```

## Usage (S3 Source)

```hcl
module "python_layer" {
  source = "./aws_lambda_layer"

  layer_name          = "python-shared"
  compatible_runtimes = ["python3.12"]

  s3_bucket = "my-artifacts-bucket"
  s3_key    = "layers/python-shared.zip"
}
```

## Usage (Share Layer)

```hcl
module "public_layer" {
  source = "./aws_lambda_layer"

  layer_name = "shared-public"
  filename   = "build/layers/shared-public.zip"

  permissions = [
    {
      statement_id = "AllowAccount123456789012"
      principal    = "123456789012"
    },
    {
      statement_id = "AllowOrg"
      principal    = "*"
      organization_id = "o-abc123def456"
    }
  ]
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `layer_name` | string | - | Yes | Lambda layer name |
| `description` | string | `null` | No | Layer description |
| `license_info` | string | `null` | No | Layer license info |
| `compatible_runtimes` | list(string) | `[]` | No | Compatible runtimes |
| `compatible_architectures` | list(string) | `[]` | No | `x86_64` and/or `arm64` |
| `filename` | string | `null` | Conditional | Local zip file path |
| `source_code_hash` | string | `null` | No | Optional precomputed source hash |
| `s3_bucket` | string | `null` | Conditional | S3 bucket for zip |
| `s3_key` | string | `null` | Conditional | S3 key for zip |
| `s3_object_version` | string | `null` | No | S3 object version |
| `permissions` | list(object) | `[]` | No | Layer version permissions |

## Outputs

| Output | Description |
|--------|-------------|
| `layer_name` | Layer name |
| `layer_version` | Published version number |
| `layer_arn` | Versioned layer ARN |
| `layer_version_arn` | Version-specific ARN |
| `layer_source_code_size` | Layer package size |

## Notes

- Set exactly one source method:
  - `filename`, or
  - `s3_bucket` + `s3_key`
- Each publish creates a new immutable layer version.
