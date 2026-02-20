# AWS DynamoDB Terraform Module

Comprehensive Terraform module for provisioning an AWS DynamoDB table with optional indexes, streams, TTL, encryption, recovery, deletion protection, Global Tables replicas, auto-scaling, and full observability.

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
- Deletion protection (defaults to **enabled** for production safety)
- Table class selection
- Global Tables replicas (multi-region)
- **Application Auto Scaling** for PROVISIONED mode (table + GSI read/write capacity)
- Dynamic CloudWatch metric alarms (including default presets)
  - ThrottledRequests, UserErrors, SystemErrors, ConditionalCheckFailedRequests, SuccessfulRequestLatency p95
  - Per-GSI ReadThrottleEvents / WriteThrottleEvents
  - Capacity utilization alarms for PROVISIONED mode
- CloudWatch anomaly detection alarms
- **CloudWatch Dashboard** with table and per-GSI metrics
- Contributor Insights (table and GSI) for hot-key tracing/analysis
- Optional CloudTrail data-event logging for table audit logs (with optional CloudWatch Logs + KMS)
- Input validation and lifecycle preconditions for safer plans

---

## Prerequisites

- Terraform >= 1.5
- AWS provider >= 5.0
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

Boolean-first setup (recommended):

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

  observability = {
    enabled                                         = true
    enable_default_alarms                           = true
    enable_anomaly_detection_alarms                 = true
    enable_contributor_insights_table               = true
    enable_contributor_insights_all_global_secondary_indexes = true
    enable_cloudtrail_data_events                   = true
    cloudtrail_s3_bucket_name                       = "my-cloudtrail-audit-logs"
    default_alarm_actions                           = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
  }

  cloudtrail_data_events = {
    cloud_watch_logs_enabled          = true
    create_cloud_watch_logs_role      = true
    cloud_watch_logs_retention_in_days = 90
    kms_key_id                        = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }
}
```

Fully custom setup (advanced):

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

  cloudwatch_metric_anomaly_alarms = {
    read_capacity_anomaly = {
      comparison_operator      = "GreaterThanUpperThreshold"
      evaluation_periods       = 2
      metric_name              = "ConsumedReadCapacityUnits"
      period                   = 300
      statistic                = "Sum"
      anomaly_detection_stddev = 2
      treat_missing_data       = "notBreaching"
      alarm_actions            = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
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
    kms_key_id      = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    cloud_watch_logs_enabled = true
    create_cloud_watch_logs_role = false
    cloud_watch_logs_role_arn = "arn:aws:iam::123456789012:role/external-cloudtrail-cwlogs"
    cloud_watch_logs_group_name = "/aws/cloudtrail/orders-data-events"
  }
}
```

Notes:
- Metrics/alarms: module injects `TableName=<table name>` into alarm dimensions.
- Preset alarms: when `observability.enabled = true` and `observability.enable_default_alarms = true`, defaults are created for `ThrottledRequests`, `UserErrors`, `SystemErrors`, `ConditionalCheckFailedRequests`, and `SuccessfulRequestLatency` (p95). For PROVISIONED billing mode, `read_capacity_utilization` and `write_capacity_utilization` alarms are also created. Per-GSI `ReadThrottleEvents` and `WriteThrottleEvents` alarms are created for each GSI.
- Anomaly alarms: use CloudWatch `ANOMALY_DETECTION_BAND` via `cloudwatch_metric_anomaly_alarms`.
- Dashboard: set `observability.enable_dashboard = true` to create a CloudWatch dashboard with consumed capacity, throttle, latency, error, and per-GSI widgets.
- Tracing/insights: DynamoDB does not support native X-Ray segment tracing for table operations; Contributor Insights is the closest built-in per-table/per-GSI hot-key analysis feature.
- Logging: CloudTrail data events provide API audit logging for table reads/writes, with optional CloudWatch Logs delivery.
- IAM mode for CloudTrail -> CloudWatch Logs is explicit: set `create_cloud_watch_logs_role = true` to let the module create role/policy, or set it to `false` and provide `cloud_watch_logs_role_arn` from external IAM.
- Contributor Insights precedence: if `contributor_insights` is explicitly configured, it is respected; observability booleans apply defaults only when `contributor_insights` is not explicitly set.

### 6) Observability combination reference

Use this section as a quick chooser. Assume standard required table inputs are already set (`table_name`, `hash_key`, `attributes`, etc.).

| Combination | `observability` block | Additional blocks | When to use |
|---|---|---|---|
| No observability | omit or `enabled = false` | none | App/dev environments where external tooling handles everything |
| Preset alarms only | `enabled = true`, `enable_default_alarms = true` | optional shared actions | Fast baseline alerts |
| Preset + custom alarm override | same as above | `cloudwatch_metric_alarms` for overrides/additions | Keep defaults, tune specific thresholds |
| Anomaly alarms only | `enabled = true`, `enable_default_alarms = false`, `enable_anomaly_detection_alarms = true` | optional `cloudwatch_metric_anomaly_alarms` | Dynamic baselines for variable traffic |
| Contributor Insights only | `enabled = true`, CI booleans true, others false | optional `contributor_insights` | Hot-partition / hot-key analysis only |
| CloudTrail only (S3) | `enabled = true`, `enable_cloudtrail_data_events = true` | `cloudtrail_data_events` with S3 values | API audit logs without CW Logs |
| CloudTrail + CW Logs (module IAM) | same as above | `cloudtrail_data_events.cloud_watch_logs_enabled = true`, `create_cloud_watch_logs_role = true` | One-module setup |
| CloudTrail + CW Logs (external IAM) | same as above | `create_cloud_watch_logs_role = false`, pass `cloud_watch_logs_role_arn` | Centralized IAM ownership |

#### A) No observability

```hcl
observability = {
  enabled = false
}
```

#### B) Preset alarms only (boolean-first)

```hcl
observability = {
  enabled                   = true
  enable_default_alarms     = true
  enable_anomaly_detection_alarms = false
  enable_contributor_insights_table = false
  enable_contributor_insights_all_global_secondary_indexes = false
  enable_cloudtrail_data_events = false
  default_alarm_actions = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
}
```

#### C) Preset alarms + override one threshold + add custom metric alarm

```hcl
observability = {
  enabled               = true
  enable_default_alarms = true
}

cloudwatch_metric_alarms = {
  throttled_requests = {
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 1
    metric_name         = "ThrottledRequests"
    period              = 60
    statistic           = "Sum"
    threshold           = 5
    treat_missing_data  = "notBreaching"
  }

  conditional_check_failed = {
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 1
    metric_name         = "ConditionalCheckFailedRequests"
    period              = 60
    statistic           = "Sum"
    threshold           = 20
    treat_missing_data  = "notBreaching"
  }
}
```

#### D) Anomaly alarms only

```hcl
observability = {
  enabled                         = true
  enable_default_alarms           = false
  enable_anomaly_detection_alarms = true
  enable_cloudtrail_data_events   = false
}
```

#### E) Contributor Insights only (selected GSIs)

```hcl
observability = {
  enabled       = true
  enable_default_alarms = false
  enable_anomaly_detection_alarms = false
  enable_contributor_insights_table = true
  enable_contributor_insights_all_global_secondary_indexes = false
  enable_cloudtrail_data_events = false
}

contributor_insights = {
  table_enabled                 = true
  global_secondary_index_names = ["gsi_category", "gsi_status"]
}
```

#### F) CloudTrail data events only (S3 audit)

```hcl
observability = {
  enabled                       = true
  enable_default_alarms         = false
  enable_anomaly_detection_alarms = false
  enable_contributor_insights_table = false
  enable_cloudtrail_data_events = true
  cloudtrail_s3_bucket_name     = "my-cloudtrail-audit-logs"
}

cloudtrail_data_events = {
  read_write_type = "All"
}
```

#### G) CloudTrail + CloudWatch Logs with module-managed IAM role

```hcl
observability = {
  enabled                       = true
  enable_cloudtrail_data_events = true
  cloudtrail_s3_bucket_name     = "my-cloudtrail-audit-logs"
}

cloudtrail_data_events = {
  cloud_watch_logs_enabled      = true
  create_cloud_watch_logs_role  = true
  cloud_watch_logs_retention_in_days = 90
}
```

#### H) CloudTrail + CloudWatch Logs with external IAM role

```hcl
observability = {
  enabled                       = true
  enable_cloudtrail_data_events = true
  cloudtrail_s3_bucket_name     = "my-cloudtrail-audit-logs"
}

cloudtrail_data_events = {
  cloud_watch_logs_enabled = true
  create_cloud_watch_logs_role = false
  cloud_watch_logs_role_arn = "arn:aws:iam::123456789012:role/external-cloudtrail-cwlogs"
  cloud_watch_logs_group_name = "/aws/cloudtrail/orders-data-events"
}
```

#### I) Full explicit mode (no `observability` block)

```hcl
cloudwatch_metric_alarms = {
  throttled_requests = {
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = 1
    metric_name         = "ThrottledRequests"
    period              = 60
    statistic           = "Sum"
    threshold           = 1
  }
}

contributor_insights = {
  table_enabled                         = true
  all_global_secondary_indexes_enabled = true
}

cloudtrail_data_events = {
  enabled            = true
  s3_bucket_name     = "my-cloudtrail-audit-logs"
  cloud_watch_logs_enabled = true
  create_cloud_watch_logs_role = false
  cloud_watch_logs_role_arn = "arn:aws:iam::123456789012:role/external-cloudtrail-cwlogs"
}
```

### 7) Auto-scaling (PROVISIONED billing mode)

Enable auto-scaling for table and GSI read/write capacity with target tracking policies.

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
    { name = "category", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name            = "gsi_category"
      hash_key        = "category"
      projection_type = "ALL"
      read_capacity   = 5
      write_capacity  = 5
    }
  ]

  autoscaling = {
    enabled                  = true
    read_min_capacity        = 5
    read_max_capacity        = 200
    write_min_capacity       = 5
    write_max_capacity       = 200
    read_target_utilization  = 70
    write_target_utilization = 70
    scale_in_cooldown        = 60
    scale_out_cooldown       = 60

    # Optional: override defaults for GSIs
    gsi_defaults = {
      read_min_capacity  = 3
      read_max_capacity  = 100
      write_min_capacity = 3
      write_max_capacity = 100
    }
  }

  tags = {
    Environment = "prod"
    Service     = "catalog"
  }
}
```

Notes:
- Auto-scaling is only valid with `billing_mode = "PROVISIONED"`. A precondition enforces this.
- Table and all GSIs get auto-scaling targets and policies.
- `gsi_defaults` lets you override capacity bounds/targets for GSIs independently. Any field omitted falls back to the table-level setting.

### 8) CloudWatch Dashboard

Enable a pre-built CloudWatch dashboard with table and per-GSI observability widgets.

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

  observability = {
    enabled                   = true
    enable_default_alarms     = true
    enable_dashboard          = true
    default_alarm_actions     = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
  }
}
```

The dashboard includes:
- **Consumed Capacity Units** (Read/Write) — time series
- **Throttled Requests** (ThrottledRequests, ReadThrottleEvents, WriteThrottleEvents) — time series
- **Request Latency** (Average, p95, p99) — time series
- **Errors** (UserErrors, SystemErrors, ConditionalCheckFailedRequests) — time series
- **Per-GSI widgets** (consumed capacity + throttle events) — one widget per GSI

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
| `deletion_protection_enabled` | `bool` | `true` | Enable deletion protection (defaults to true for production safety) |
| `table_class` | `string` | `"STANDARD"` | `STANDARD` or `STANDARD_INFREQUENT_ACCESS` |
| `tags` | `map(string)` | `{}` | Tags to apply |
| `observability` | `object({ enabled, enable_default_alarms, enable_anomaly_detection_alarms, enable_contributor_insights_table, enable_contributor_insights_all_global_secondary_indexes, enable_cloudtrail_data_events, enable_dashboard, cloudtrail_s3_bucket_name, default_alarm_actions, default_ok_actions, default_insufficient_data_actions })` | disabled | Boolean-first observability toggles and shared alarm actions |
| `cloudwatch_metric_alarms` | `map(object(...))` | `{}` | CloudWatch metric alarms for DynamoDB table metrics |
| `cloudwatch_metric_anomaly_alarms` | `map(object(...))` | `{}` | CloudWatch anomaly detection alarms for DynamoDB table metrics |
| `contributor_insights` | `object({ table_enabled, all_global_secondary_indexes_enabled, global_secondary_index_names })` | `{ table_enabled = false, all_global_secondary_indexes_enabled = false, global_secondary_index_names = [] }` | Contributor Insights tracing/analysis settings |
| `cloudtrail_data_events` | `object({ enabled, trail_name, s3_bucket_name, kms_key_id, enable_log_file_validation, include_management_events, read_write_type, cloud_watch_logs_enabled, create_cloud_watch_logs_role, cloud_watch_logs_group_name, cloud_watch_logs_retention_in_days, cloud_watch_logs_role_arn, tags })` | disabled | CloudTrail data-event logging settings for table audit logs |
| `autoscaling` | `object({ enabled, read_min_capacity, read_max_capacity, write_min_capacity, write_max_capacity, read_target_utilization, write_target_utilization, scale_in_cooldown, scale_out_cooldown, gsi_defaults })` | `{ enabled = false }` | Application Auto Scaling for PROVISIONED billing mode |

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
| `cloudwatch_metric_anomaly_alarm_arns` | Map of anomaly alarm ARNs keyed by `cloudwatch_metric_anomaly_alarms` key |
| `cloudwatch_metric_anomaly_alarm_names` | Map of anomaly alarm names keyed by `cloudwatch_metric_anomaly_alarms` key |
| `contributor_insights_table_enabled` | Whether table Contributor Insights is enabled |
| `contributor_insights_gsi_names` | GSI names with Contributor Insights enabled |
| `cloudtrail_data_events_trail_arn` | CloudTrail ARN when data-event logging is enabled |
| `cloudtrail_data_events_trail_name` | CloudTrail name when data-event logging is enabled |
| `cloudtrail_data_events_cloudwatch_log_group_name` | CloudWatch Log Group name used by CloudTrail logs delivery |
| `cloudtrail_data_events_cloudwatch_logs_role_arn` | IAM role ARN used by CloudTrail to publish into CloudWatch Logs |
| `autoscaling_enabled` | Whether auto-scaling is enabled for the table |
| `autoscaling_table_read_target_arn` | Application Auto Scaling read target resource ID |
| `autoscaling_table_write_target_arn` | Application Auto Scaling write target resource ID |
| `autoscaling_gsi_read_targets` | Map of GSI name to Auto Scaling read target resource IDs |
| `autoscaling_gsi_write_targets` | Map of GSI name to Auto Scaling write target resource IDs |
| `dashboard_name` | CloudWatch dashboard name (or `null` if disabled) |
| `dashboard_arn` | CloudWatch dashboard ARN (or `null` if disabled) |

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
- `contributor_insights.all_global_secondary_indexes_enabled` and `contributor_insights.global_secondary_index_names` cannot be set together
- `table_class` must be `STANDARD` or `STANDARD_INFREQUENT_ACCESS`
- KMS ARNs (table SSE and replicas) are format-validated when provided
- `autoscaling.enabled = true` requires `billing_mode = "PROVISIONED"`
- `autoscaling.read_min_capacity` must be <= `read_max_capacity`
- `autoscaling.read_target_utilization` must be between 1 and 100

---

## Behavior notes

- `attributes` in Terraform DynamoDB definitions represent key schema attributes (table/index keys), not every item attribute.
- `table_stream_arn` and `table_stream_label` are available only when streams are enabled.
- Enabling replicas configures DynamoDB Global Tables v2 style replication through the table resource.

---

## Best practices

- Prefer `PAY_PER_REQUEST` for variable or unknown traffic patterns.
- Use `PROVISIONED` with `autoscaling.enabled = true` when you need cost predictability with auto-scaling.
- Keep index count and projected attributes minimal to control costs.
- Enable PITR for production workloads.
- Use customer-managed KMS keys for stricter compliance requirements.
- Add tags for ownership, cost allocation, and environment segmentation.
- Enable `observability.enable_dashboard = true` for at-a-glance table health.
- `deletion_protection_enabled` defaults to `true`; explicitly set `false` only for dev/test environments.

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

- **Error:** `autoscaling.enabled = true` with `PAY_PER_REQUEST` billing  
  **Fix:** set `billing_mode = "PROVISIONED"` or disable autoscaling.

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

  deletion_protection_enabled = true
  table_class                 = "STANDARD"
  tags                        = {}

  # Auto-scaling (PROVISIONED mode only)
  # autoscaling = {
  #   enabled                  = true
  #   read_min_capacity        = 5
  #   read_max_capacity        = 100
  #   write_min_capacity       = 5
  #   write_max_capacity       = 100
  #   read_target_utilization  = 70
  #   write_target_utilization = 70
  # }
}
```