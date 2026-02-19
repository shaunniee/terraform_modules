# AWS DynamoDB Terraform Module

Comprehensive Terraform module for provisioning an AWS DynamoDB table with optional indexes, streams, TTL, encryption, recovery, deletion protection, and Global Tables replicas.

## What this module manages

This module creates one `aws_dynamodb_table` resource and supports:

- On-demand and provisioned billing modes
- Primary key and optional sort key
- Global Secondary Indexes (GSIs)
- Local Secondary Indexes (LSIs)
- DynamoDB Streams
- TTL (Time To Live)
- Point-in-time recovery (PITR)
- Server-side encryption (SSE)
- Deletion protection
- Table class selection
- Global Tables replicas (multi-region)
- Dynamic CloudWatch metric alarms
- Contributor Insights (table and GSI) for hot-key tracing/analysis
- Optional CloudTrail data-event logging for table audit logs
- Input validation and lifecycle preconditions for safer plans

---

## Prerequisites

- Terraform version compatible with your AWS provider configuration
- AWS provider configured with credentials and region
- IAM permissions for DynamoDB (and KMS if customer-managed keys are used)

If you use replicas (Global Tables), ensure permissions and KMS policies are valid in each replica region.

---

## Quick start

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

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

---

## Usage patterns

### 1) On-demand table (PAY_PER_REQUEST)

Use this for unpredictable traffic and operational simplicity.

```hcl
module "dynamodb_users" {
  source = "./aws_dynamodb"

  table_name   = "users"
  hash_key     = "user_id"
  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "user_id", type = "S" }
  ]

  tags = {
    Environment = "dev"
    Service     = "identity"
  }
}
```

### 2) Provisioned table with GSIs and LSI

Use this when you need explicit capacity management.

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
      name               = "gsi_category"
      hash_key           = "category"
      range_key          = "created_at"
      projection_type    = "INCLUDE"
      non_key_attributes = ["product_name", "price"]
      read_capacity      = 5
      write_capacity     = 5
    }
  ]

  local_secondary_indexes = [
    {
      name            = "lsi_created_at"
      range_key       = "created_at"
      projection_type = "KEYS_ONLY"
    }
  ]

  tags = {
    Environment = "prod"
    Service     = "catalog"
  }
}
```

### 3) Global Tables (replicas)

Use this for multi-region active-active replication.

```hcl
module "dynamodb_sessions" {
  source = "./aws_dynamodb"

  table_name = "sessions"
  hash_key   = "tenant_id"
  range_key  = "session_id"

  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "tenant_id", type = "S" },
    { name = "session_id", type = "S" }
  ]

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replicas = [
    {
      region_name = "us-west-2"
    },
    {
      region_name = "eu-west-1"
    }
  ]

  tags = {
    Environment = "prod"
    Service     = "session"
  }
}
```

### 4) Table with TTL, Streams, PITR, and SSE (custom KMS)

```hcl
module "dynamodb_events" {
  source = "./aws_dynamodb"

  table_name = "events"
  hash_key   = "pk"
  range_key  = "sk"

  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "pk", type = "S" },
    { name = "sk", type = "S" }
  ]

  ttl = {
    enabled        = true
    attribute_name = "expires_at"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery_enabled = true

  server_side_encryption = {
    enabled     = true
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  deletion_protection_enabled = true

  tags = {
    Environment = "prod"
    Service     = "eventing"
  }
}
```

### 5) Observability (Logging, Metrics, Alarms, Tracing)

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

  cloudwatch_metric_alarms = {
    throttled_requests = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "ThrottledRequests"
      period              = 60
      statistic           = "Sum"
      threshold           = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    user_errors = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      metric_name         = "UserErrors"
      period              = 60
      statistic           = "Sum"
      threshold           = 5
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }

  contributor_insights = {
    table_enabled                         = true
    all_global_secondary_indexes_enabled = true
  }

  cloudtrail_data_events = {
    enabled        = true
    trail_name     = "orders-dynamodb-audit"
    s3_bucket_name = "my-cloudtrail-audit-logs"
    read_write_type = "All"
  }
}
```

Notes:
- Metrics/alarms: module injects `TableName=<table name>` into alarm dimensions.
- Tracing/insights: DynamoDB does not support native X-Ray segment tracing for table operations; Contributor Insights is the closest built-in per-table/per-GSI hot-key analysis feature.
- Logging: CloudTrail data events provide API audit logging for table reads/writes.

---

## Inputs

### Required inputs

| Name | Type | Description |
|------|------|-------------|
| `table_name` | `string` | DynamoDB table name (3-255 chars, `[a-zA-Z0-9_.-]`) |
| `hash_key` | `string` | Partition key attribute name |
| `attributes` | `list(object({ name = string, type = string }))` | Key attribute definitions used by table/index schemas |

### Optional inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `range_key` | `string` | `null` | Sort key attribute name |
| `billing_mode` | `string` | `"PAY_PER_REQUEST"` | `PAY_PER_REQUEST` or `PROVISIONED` |
| `read_capacity` | `number` | `null` | Table read capacity for `PROVISIONED` |
| `write_capacity` | `number` | `null` | Table write capacity for `PROVISIONED` |
| `global_secondary_indexes` | `list(object(...))` | `[]` | GSI definitions |
| `local_secondary_indexes` | `list(object(...))` | `[]` | LSI definitions |
| `replicas` | `list(object({ region_name = string, kms_key_arn = optional(string) }))` | `[]` | Global Table replica definitions |
| `ttl` | `object({ enabled = bool, attribute_name = optional(string) })` | `{ enabled = false, attribute_name = null }` | TTL settings |
| `stream_enabled` | `bool` | `false` | Enable DynamoDB streams |
| `stream_view_type` | `string` | `null` | `KEYS_ONLY`, `NEW_IMAGE`, `OLD_IMAGE`, `NEW_AND_OLD_IMAGES` |
| `point_in_time_recovery_enabled` | `bool` | `true` | Enable PITR |
| `server_side_encryption` | `object({ enabled = bool, kms_key_arn = optional(string) })` | `{ enabled = true, kms_key_arn = null }` | SSE config |
| `deletion_protection_enabled` | `bool` | `false` | Enable deletion protection |
| `table_class` | `string` | `"STANDARD"` | `STANDARD` or `STANDARD_INFREQUENT_ACCESS` |
| `tags` | `map(string)` | `{}` | Tags to apply |
| `cloudwatch_metric_alarms` | `map(object(...))` | `{}` | CloudWatch metric alarms for DynamoDB table metrics |
| `contributor_insights` | `object({ table_enabled, all_global_secondary_indexes_enabled, global_secondary_index_names })` | `{ table_enabled = false, all_global_secondary_indexes_enabled = false, global_secondary_index_names = [] }` | Contributor Insights tracing/analysis settings |
| `cloudtrail_data_events` | `object({ enabled, trail_name, s3_bucket_name, include_management_events, read_write_type, tags })` | disabled | CloudTrail data-event logging settings for table audit logs |

---

## Outputs

| Name | Description |
|------|-------------|
| `table_name` | DynamoDB table name |
| `table_id` | DynamoDB table ID |
| `table_arn` | DynamoDB table ARN |
| `table_stream_arn` | Stream ARN (or `null` if disabled) |
| `table_stream_label` | Stream label (or `null` if disabled) |
| `global_secondary_index_names` | Configured GSI names |
| `local_secondary_index_names` | Configured LSI names |
| `configured_replica_regions` | Replica regions from module input |
| `replica_regions` | Replica regions reported by AWS |
| `cloudwatch_metric_alarm_arns` | Map of alarm ARNs keyed by `cloudwatch_metric_alarms` key |
| `cloudwatch_metric_alarm_names` | Map of alarm names keyed by `cloudwatch_metric_alarms` key |
| `contributor_insights_table_enabled` | Whether table Contributor Insights is enabled |
| `contributor_insights_gsi_names` | GSI names with Contributor Insights enabled |
| `cloudtrail_data_events_trail_arn` | CloudTrail ARN when data-event logging is enabled |
| `cloudtrail_data_events_trail_name` | CloudTrail name when data-event logging is enabled |

---

## Validation and guardrails

The module enforces input correctness with both variable validation and resource lifecycle preconditions.

### Key schema validation

- `hash_key` must exist in `attributes`
- `range_key` must be `null` or exist in `attributes`
- Every GSI key (`hash_key`, optional `range_key`) must exist in `attributes`
- Every LSI `range_key` must exist in `attributes`
- LSIs require table `range_key` to be set
- `attributes` may contain only attributes used by table/GSI/LSI key schemas

### Capacity/billing validation

- If `billing_mode = "PROVISIONED"`, table `read_capacity` and `write_capacity` are required
- If `billing_mode = "PAY_PER_REQUEST"`, table capacities must be `null`
- GSI capacities must be provided in `PROVISIONED` mode and omitted in `PAY_PER_REQUEST`

### Streams/TTL/replica validation

- If `stream_enabled = true`, `stream_view_type` is required
- If `stream_enabled = false`, `stream_view_type` must be `null`
- If `ttl.enabled = true`, `ttl.attribute_name` must be non-empty
- If `replicas` is non-empty:
  - `stream_enabled` must be `true`
  - `stream_view_type` must be `"NEW_AND_OLD_IMAGES"`

### Other validation

- Attribute types must be one of `S`, `N`, `B`
- Index names must be unique per index type
- `table_class` must be `STANDARD` or `STANDARD_INFREQUENT_ACCESS`
- KMS ARNs (table SSE and replicas) are format-validated when provided

---

## Behavior notes

- `attributes` in Terraform DynamoDB definitions represent key schema attributes (table/index keys), not every item attribute.
- `table_stream_arn` and `table_stream_label` are available only when streams are enabled.
- Enabling replicas configures DynamoDB Global Tables v2 style replication through the table resource.

---

## Best practices

- Prefer `PAY_PER_REQUEST` for variable or unknown traffic patterns.
- Use `PROVISIONED` only when you intentionally manage throughput.
- Keep index count and projected attributes minimal to control costs.
- Enable PITR for production workloads.
- Use customer-managed KMS keys for stricter compliance requirements.
- Add tags for ownership, cost allocation, and environment segmentation.

---

## Common errors and fixes

- **Error:** capacities set while using `PAY_PER_REQUEST`  
  **Fix:** set `read_capacity = null` and `write_capacity = null` for table and GSIs.

- **Error:** GSI/LSI key not found in `attributes`  
  **Fix:** add matching key attribute definitions to `attributes`.

- **Error:** replicas configured but stream settings invalid  
  **Fix:** set `stream_enabled = true` and `stream_view_type = "NEW_AND_OLD_IMAGES"`.

- **Error:** `ttl.enabled = true` without `attribute_name`  
  **Fix:** set a non-empty TTL attribute name.

---

## Minimal module call template

```hcl
module "dynamodb" {
  source = "./aws_dynamodb"

  table_name = "<table-name>"
  hash_key   = "<partition-key>"
  range_key  = null # optional

  billing_mode   = "PAY_PER_REQUEST" # or PROVISIONED
  read_capacity  = null               # required only for PROVISIONED
  write_capacity = null               # required only for PROVISIONED

  attributes = [
    { name = "<partition-key>", type = "S" }
  ]

  global_secondary_indexes = []
  local_secondary_indexes  = []
  replicas                 = []

  ttl = {
    enabled        = false
    attribute_name = null
  }

  stream_enabled   = false
  stream_view_type = null

  point_in_time_recovery_enabled = true

  server_side_encryption = {
    enabled     = true
    kms_key_arn = null
  }

  deletion_protection_enabled = false
  table_class                 = "STANDARD"
  tags                        = {}
}
```