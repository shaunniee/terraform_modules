# AWS DynamoDB Terraform Module

Reusable and dynamic DynamoDB table module with support for:
- On-demand (`PAY_PER_REQUEST`) and provisioned billing
- Primary key + optional sort key
- GSIs and LSIs
- TTL, streams, PITR, SSE, table class, deletion protection
- Strong validations for index/key/capacity consistency

## Basic Usage (On-Demand)

```hcl
module "dynamodb_orders" {
  source = "./aws_dynamodb"

  table_name = "orders"
  hash_key   = "pk"
  range_key  = "sk"

  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "pk", type = "S" },
    { name = "sk", type = "S" }
  ]

  point_in_time_recovery_enabled = true

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Advanced Usage (Provisioned + GSIs + LSI + TTL + Streams)

```hcl
module "dynamodb_products" {
  source = "./aws_dynamodb"

  table_name = "products"
  hash_key   = "tenant_id"
  range_key  = "product_id"

  billing_mode   = "PROVISIONED"
  read_capacity  = 10
  write_capacity = 10

  attributes = [
    { name = "tenant_id", type = "S" },
    { name = "product_id", type = "S" },
    { name = "category", type = "S" },
    { name = "created_at", type = "N" }
  ]

  global_secondary_indexes = [
    {
      name            = "gsi_category"
      hash_key        = "category"
      range_key       = "created_at"
      projection_type = "INCLUDE"
      non_key_attributes = ["product_name", "price"]
      read_capacity   = 5
      write_capacity  = 5
    }
  ]

  local_secondary_indexes = [
    {
      name            = "lsi_created_at"
      range_key       = "created_at"
      projection_type = "KEYS_ONLY"
    }
  ]

  ttl = {
    enabled        = true
    attribute_name = "expires_at"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  server_side_encryption = {
    enabled     = true
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  deletion_protection_enabled    = true
  table_class                    = "STANDARD"
  point_in_time_recovery_enabled = true

  tags = {
    Environment = "prod"
    Service     = "catalog"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `table_name` | string | - | Yes | DynamoDB table name |
| `hash_key` | string | - | Yes | Partition key name |
| `range_key` | string | `null` | No | Sort key name |
| `billing_mode` | string | `PAY_PER_REQUEST` | No | `PAY_PER_REQUEST` or `PROVISIONED` |
| `read_capacity` | number | `null` | Conditionally | Required for PROVISIONED |
| `write_capacity` | number | `null` | Conditionally | Required for PROVISIONED |
| `attributes` | list(object) | - | Yes | Attribute definitions for key schema fields |
| `global_secondary_indexes` | list(object) | `[]` | No | GSI definitions |
| `local_secondary_indexes` | list(object) | `[]` | No | LSI definitions |
| `ttl` | object | disabled | No | TTL configuration |
| `stream_enabled` | bool | `false` | No | Enable DynamoDB streams |
| `stream_view_type` | string | `null` | Conditionally | Required if streams enabled |
| `point_in_time_recovery_enabled` | bool | `true` | No | Enable PITR |
| `server_side_encryption` | object | enabled | No | SSE and optional KMS key |
| `deletion_protection_enabled` | bool | `false` | No | Protect table from deletion |
| `table_class` | string | `STANDARD` | No | `STANDARD` or `STANDARD_INFREQUENT_ACCESS` |
| `tags` | map(string) | `{}` | No | Tags |

## Outputs

| Output | Description |
|--------|-------------|
| `table_name` | Table name |
| `table_id` | Table ID |
| `table_arn` | Table ARN |
| `table_stream_arn` | Stream ARN (if enabled) |
| `table_stream_label` | Stream label (if enabled) |
| `global_secondary_index_names` | GSI names |
| `local_secondary_index_names` | LSI names |

## Notes

- `attributes` must contain only attributes used in table/GSI/LSI key schemas.
- For `PROVISIONED` billing, table and all GSIs require capacities.
- For `PAY_PER_REQUEST`, capacities must not be set.
