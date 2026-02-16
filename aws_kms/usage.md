
# AWS KMS Terraform Module

Reusable module for creating one or more AWS KMS keys and aliases from a single map input.

This module supports:
- Multiple key creation in one module call
- Per-key alias, description, and tags
- Optional key policy override
- Configurable key rotation and deletion window

## Basic Usage

```hcl
module "kms" {
  source = "./aws_kms"

  keys = {
    app = {
      alias       = "app"
      description = "KMS key for app encryption"
      tags = {
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
  }
}
```

## Advanced Usage (Multiple Keys + Custom Policy)

```hcl
module "kms" {
  source = "./aws_kms"

  keys = {
    s3_data = {
      alias                   = "s3-data"
      description             = "Encrypt S3 data at rest"
      enable_key_rotation     = true
      deletion_window_in_days = 30
      tags = {
        Environment = "prod"
        Service     = "storage"
      }
    }

    app_secrets = {
      alias                   = "app-secrets"
      description             = "Encrypt application secrets"
      enable_key_rotation     = true
      deletion_window_in_days = 7
      policy                  = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid    = "EnableRootPermissions"
            Effect = "Allow"
            Principal = {
              AWS = "arn:aws:iam::123456789012:root"
            }
            Action   = "kms:*"
            Resource = "*"
          }
        ]
      })
      tags = {
        Environment = "prod"
        Service     = "security"
      }
    }
  }
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `keys` | map(object) | `{}` | No | Map of KMS key definitions keyed by logical name |
| `keys[*].alias` | string | - | Yes (per key) | Alias name without `alias/` prefix |
| `keys[*].description` | string | `""` | No | Key description |
| `keys[*].deletion_window_in_days` | number | `30` | No | Waiting period before key deletion |
| `keys[*].enable_key_rotation` | bool | `true` | No | Enable automatic annual key rotation |
| `keys[*].policy` | string | `null` | No | Optional JSON key policy string |
| `keys[*].tags` | map(string) | `{}` | No | Tags applied to each key |

## Outputs

| Output | Description |
|--------|-------------|
| `kms_key_ids` | Map of key IDs by logical key |
| `kms_key_arns` | Map of key ARNs by logical key |

## Alias Behavior

- Alias resource name is always built as `alias/${each.value.alias}`.
- Do not include `alias/` in input; provide only the alias suffix.

## Notes

- The module creates one `aws_kms_key` and one `aws_kms_alias` per entry in `keys`.
- If `keys` is empty, no resources are created and outputs are empty maps.

