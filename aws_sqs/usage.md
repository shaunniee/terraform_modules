
# AWS SQS Terraform Module

Production-grade module for creating SQS queues with optional dead-letter queue, encryption, queue policies, CloudWatch alarms, and dashboard.

## Features

- **Standard or FIFO** queues with automatic `.fifo` suffix
- **Encryption** — SQS-managed SSE (default) or customer-managed KMS key
- **Dead-letter queue** — managed DLQ or external DLQ ARN, with separate retention & tags
- **Queue policies** — IAM policies for cross-account access, SNS subscriptions, EventBridge targets
- **FIFO features** — content-based deduplication, deduplication scope, high-throughput mode
- **Observability** — toggleable CloudWatch alarms (queue depth, message age, DLQ depth) + dashboard
- **Custom alarms** — user-defined alarms with `extended_statistic` support, merged with defaults
- **Validations** — 30+ plan-time validations on all inputs

---

## 1 — Basic Standard Queue

```hcl
module "sqs" {
  source = "../aws_sqs"

  name = "orders-queue"
  tags = { Environment = "dev" }
}
```

## 2 — FIFO Queue with Content-Based Deduplication

```hcl
module "sqs_fifo" {
  source = "../aws_sqs"

  name                        = "payments-events"
  fifo_queue                  = true
  content_based_deduplication = true
  fifo_throughput_limit       = "perMessageGroupId"
  deduplication_scope         = "messageGroup"

  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20

  tags = { Environment = "prod", Service = "payments" }
}
```

## 3 — Queue with Managed DLQ + Observability

```hcl
module "sqs" {
  source = "../aws_sqs"

  name       = "order-processor"
  create_dlq = true
  max_receive_count             = 3
  dlq_message_retention_seconds = 1209600 # 14 days

  observability = {
    enabled               = true
    enable_default_alarms = true
    enable_dlq_alarm      = true
    enable_dashboard      = true

    queue_depth_threshold        = 500
    oldest_message_age_threshold = 1800   # 30 min
    dlq_depth_threshold          = 1

    default_alarm_actions = ["arn:aws:sns:us-east-1:123456789012:alerts"]
  }

  tags = { Environment = "prod" }
}
```

## 4 — KMS Encryption + External DLQ

```hcl
module "sqs" {
  source = "../aws_sqs"

  name                    = "sensitive-data"
  sqs_managed_sse_enabled = false
  kms_master_key_id       = "arn:aws:kms:us-east-1:123456789012:key/abc-def-123"
  kms_data_key_reuse_period_seconds = 600

  dlq_arn           = "arn:aws:sqs:us-east-1:123456789012:sensitive-data-dlq"
  max_receive_count = 5

  tags = { Compliance = "pci" }
}
```

## 5 — Queue with Queue Policy (SNS Subscription)

```hcl
module "sqs" {
  source = "../aws_sqs"

  name = "notifications"

  queue_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = "*"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = "arn:aws:sns:us-east-1:123456789012:order-events"
          }
        }
      }
    ]
  })

  tags = { Environment = "prod" }
}
```

## 6 — Custom Alarms with Extended Statistics

```hcl
module "sqs" {
  source = "../aws_sqs"

  name       = "analytics-queue"
  create_dlq = true

  observability = {
    enabled               = true
    enable_default_alarms = true
    default_alarm_actions = ["arn:aws:sns:us-east-1:123456789012:alerts"]
  }

  cloudwatch_metric_alarms = {
    sent_message_size_p99 = {
      queue               = "main"
      metric_name         = "SentMessageSize"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 200000
      extended_statistic  = "p99"
      alarm_description   = "P99 message size approaching 256KB limit"
    }
    dlq_age = {
      queue               = "dlq"
      metric_name         = "ApproximateAgeOfOldestMessage"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 86400
      statistic           = "Maximum"
      alarm_description   = "DLQ messages older than 24h — investigate and redrive"
    }
  }

  tags = { Environment = "prod" }
}
```

## 7 — FIFO Queue with DLQ, Encryption, and Full Observability

```hcl
module "sqs" {
  source = "../aws_sqs"

  name                        = "payment-events"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  visibility_timeout_seconds = 120
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  delay_seconds              = 5
  max_message_size           = 131072

  sqs_managed_sse_enabled = false
  kms_master_key_id       = "alias/sqs-payment"

  create_dlq                    = true
  max_receive_count             = 3
  dlq_message_retention_seconds = 1209600
  dlq_tags                      = { Purpose = "failed-payments" }

  queue_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = "*"
      }
    ]
  })

  observability = {
    enabled                      = true
    enable_default_alarms        = true
    enable_dlq_alarm             = true
    enable_dashboard             = true
    queue_depth_threshold        = 100
    oldest_message_age_threshold = 600
    dlq_depth_threshold          = 1
    default_alarm_actions        = ["arn:aws:sns:us-east-1:123456789012:payments-alerts"]
    default_ok_actions           = ["arn:aws:sns:us-east-1:123456789012:payments-ok"]
  }

  tags = { Service = "payments", Environment = "prod" }
}
```

---

## Variable Reference

### `name`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `string` | — | Base queue name. `.fifo` appended automatically for FIFO queues. 1–75 chars, alphanumeric + `-_`. |

### Queue Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `fifo_queue` | `bool` | `false` | Create a FIFO queue. |
| `visibility_timeout_seconds` | `number` | `30` | Visibility timeout (0–43200). |
| `message_retention_seconds` | `number` | `345600` | Message retention (60–1209600). Default 4 days. |
| `receive_wait_time_seconds` | `number` | `0` | Long-poll wait time (0–20). |
| `delay_seconds` | `number` | `0` | Delivery delay (0–900). |
| `max_message_size` | `number` | `262144` | Max message size in bytes (1024–262144). |

### FIFO Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `content_based_deduplication` | `bool` | `false` | Use message body SHA-256 as dedup ID. Requires `fifo_queue = true`. |
| `deduplication_scope` | `string` | `null` | `messageGroup` or `queue`. Requires `fifo_queue = true`. |
| `fifo_throughput_limit` | `string` | `null` | `perQueue` or `perMessageGroupId`. Requires `fifo_queue = true`. |

### Encryption

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `sqs_managed_sse_enabled` | `bool` | `true` | Enable SQS-managed SSE. Mutually exclusive with `kms_master_key_id`. |
| `kms_master_key_id` | `string` | `null` | KMS key ID/ARN/alias for SSE-KMS. Mutually exclusive with `sqs_managed_sse_enabled`. |
| `kms_data_key_reuse_period_seconds` | `number` | `300` | KMS data key reuse period (60–86400). |

### Dead-Letter Queue

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_dlq` | `bool` | `false` | Create a managed DLQ. Mutually exclusive with `dlq_arn`. |
| `dlq_arn` | `string` | `null` | External DLQ ARN. Mutually exclusive with `create_dlq`. |
| `max_receive_count` | `number` | `5` | Receives before moving to DLQ (1–1000). |
| `dlq_message_retention_seconds` | `number` | `1209600` | DLQ retention (60–1209600). Default 14 days. |
| `dlq_tags` | `map(string)` | `{}` | Additional tags for the managed DLQ (merged with `tags`). |

### Queue Policies

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `queue_policy` | `string` | `null` | IAM policy JSON for the main queue. |
| `dlq_queue_policy` | `string` | `null` | IAM policy JSON for the managed DLQ. |

### `observability`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Master switch for all observability resources. |
| `enable_default_alarms` | `bool` | `true` | Create default queue depth + message age alarms. |
| `enable_dlq_alarm` | `bool` | `true` | Create DLQ depth alarm (requires a DLQ). |
| `enable_zero_sends_alarm` | `bool` | `false` | Opt-in alarm when no messages are sent (silent producer failure). |
| `enable_dashboard` | `bool` | `true` | Create CloudWatch dashboard. |
| `queue_depth_threshold` | `number` | `1000` | Threshold for `ApproximateNumberOfMessagesVisible`. |
| `oldest_message_age_threshold` | `number` | `3600` | Threshold for `ApproximateAgeOfOldestMessage` (seconds). |
| `dlq_depth_threshold` | `number` | `1` | Threshold for DLQ `ApproximateNumberOfMessagesVisible`. |
| `zero_sends_evaluation_periods` | `number` | `3` | Consecutive 5-min periods with 0 sends before zero-sends alarm fires. |
| `default_alarm_actions` | `list(string)` | `[]` | SNS ARNs for ALARM state. |
| `default_ok_actions` | `list(string)` | `[]` | SNS ARNs for OK state. |
| `default_insufficient_data_actions` | `list(string)` | `[]` | SNS ARNs for INSUFFICIENT_DATA. |

### `cloudwatch_metric_alarms`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `queue` | `string` | `"main"` | Target queue: `"main"` or `"dlq"`. |
| `metric_name` | `string` | — | SQS metric name. |
| `comparison_operator` | `string` | — | CloudWatch comparison operator. |
| `threshold` | `number` | `null` | Alarm threshold. |
| `evaluation_periods` | `number` | `2` | Consecutive periods before alarm fires. |
| `period` | `number` | `300` | Evaluation period (seconds). |
| `statistic` | `string` | `"Sum"` | Statistic. Mutually exclusive with `extended_statistic`. |
| `extended_statistic` | `string` | `null` | Percentile (e.g. `"p95"`). Mutually exclusive with `statistic`. |
| `treat_missing_data` | `string` | `"notBreaching"` | Missing data treatment. |
| `alarm_description` | `string` | `null` | Alarm description. |
| `alarm_actions` | `list(string)` | `null` | Override alarm actions. |
| `ok_actions` | `list(string)` | `null` | Override OK actions. |
| `insufficient_data_actions` | `list(string)` | `null` | Override insufficient data actions. |
| `tags` | `map(string)` | `{}` | Alarm tags. |

---

## Outputs

| Output | Description |
|--------|-------------|
| `queue_name` | Main queue name. |
| `queue_arn` | Main queue ARN. |
| `queue_url` | Main queue URL. |
| `queue_id` | Main queue ID (same as URL). |
| `dlq_name` | Managed DLQ name (null if no managed DLQ). |
| `dlq_arn` | DLQ ARN — managed or external (null if no DLQ). |
| `dlq_url` | Managed DLQ URL (null if no managed DLQ). |
| `alarm_arns` | Map of main queue alarm ARNs by key. |
| `alarm_names` | Map of main queue alarm names by key. |
| `dlq_alarm_arns` | Map of DLQ alarm ARNs by key. |
| `dlq_alarm_names` | Map of DLQ alarm names by key. |
| `dashboard_name` | Dashboard name (null if not created). |
| `dashboard_arn` | Dashboard ARN (null if not created). |
| `observability` | Summary: `enabled`, `total_alarms_created`, `dashboard_enabled`, `dlq_alarm_enabled`. |

---

## Queue Naming

| Queue | Standard | FIFO |
|-------|----------|------|
| Main | `${name}` | `${name}.fifo` |
| DLQ | `${name}-dlq` | `${name}-dlq.fifo` |

---

## Validations

The module enforces these at plan time:

1. Queue name: 1–75 chars, alphanumeric + `-_`
2. `visibility_timeout_seconds`: 0–43200
3. `message_retention_seconds`: 60–1209600
4. `receive_wait_time_seconds`: 0–20
5. `delay_seconds`: 0–900
6. `max_message_size`: 1024–262144
7. `deduplication_scope`: `messageGroup` or `queue`
8. `fifo_throughput_limit`: `perQueue` or `perMessageGroupId`
9. FIFO features require `fifo_queue = true`
10. `sqs_managed_sse_enabled` and `kms_master_key_id` are mutually exclusive
11. `kms_master_key_id`: non-empty when provided
12. `kms_data_key_reuse_period_seconds`: 60–86400
13. `create_dlq` and `dlq_arn` are mutually exclusive
14. `dlq_arn`: valid ARN format when provided
15. `max_receive_count`: 1–1000
16. `dlq_message_retention_seconds`: 60–1209600
17. `queue_policy`: valid JSON when provided
18. `dlq_queue_policy`: valid JSON when provided
19. Observability action ARNs: must start with `arn:`
20. `queue_depth_threshold`: >= 1
21. `oldest_message_age_threshold`: >= 1
22. `dlq_depth_threshold`: >= 1
23. Custom alarm `comparison_operator`: valid CloudWatch operator
24. Custom alarm `treat_missing_data`: valid value
25. Custom alarm `statistic`/`extended_statistic`: mutually exclusive
26. Custom alarm `evaluation_periods`: >= 1
27. Custom alarm `period`: >= 10
28. Custom alarm `queue`: must be `"main"` or `"dlq"`
29. DLQ alarm requires a DLQ when observability is enabled
30. `zero_sends_evaluation_periods`: >= 1

---

## Default Alarms

When `observability.enabled = true` and `enable_default_alarms = true`:

| Alarm Key | Metric | Threshold | Description |
|-----------|--------|-----------|-------------|
| `queue_depth` | `ApproximateNumberOfMessagesVisible` | `queue_depth_threshold` (default 1000) | Queue backing up |
| `oldest_message_age` | `ApproximateAgeOfOldestMessage` | `oldest_message_age_threshold` (default 3600s) | Processing stalled |

When `enable_zero_sends_alarm = true` (opt-in):

| Alarm Key | Metric | Threshold | Eval Periods | Description |
|-----------|--------|-----------|-------------|-------------|
| `zero_sends` | `NumberOfMessagesSent` | 0 | `zero_sends_evaluation_periods` (default 3 = 15min) | Silent producer failure — `treat_missing_data = breaching` |

When `enable_dlq_alarm = true` and a DLQ is configured:

| Alarm Key | Metric | Threshold | Eval Periods | Description |
|-----------|--------|-----------|-------------|-------------|
| `dlq_depth` | `ApproximateNumberOfMessagesVisible` | `dlq_depth_threshold` (default 1) | 1 (immediate) | Failed messages detected — uses `evaluation_periods = 1` for urgency |

---

## Best Practices

- **Always enable encryption** — SQS-managed SSE is on by default; use KMS for compliance/audit requirements
- **Always create a DLQ** for production queues — unprocessable messages need a safety net
- **Set `dlq_depth_threshold = 1`** — even a single DLQ message indicates a processing failure worth investigating
- **DLQ retention defaults to 14 days** — this gives you maximum time to investigate and redrive before messages expire
- **Set `visibility_timeout_seconds` >= your consumer's max processing time** — prevents duplicate processing
- **Enable long polling** (`receive_wait_time_seconds = 20`) to reduce empty receives and cost
- **Use `delay_seconds`** for rate-limiting or to allow dependent systems to catch up
- **FIFO high-throughput mode** — set `fifo_throughput_limit = "perMessageGroupId"` + `deduplication_scope = "messageGroup"` for up to 30,000 msg/s per API action
- **Use `queue_policy`** for SNS subscriptions, EventBridge targets, or cross-account access — avoid inline IAM policies
- **Custom alarms override defaults on key collision** — use key names `queue_depth`, `oldest_message_age`, or `dlq_depth` to replace defaults with custom thresholds
- **Use `extended_statistic`** (e.g. `"p99"`) for `SentMessageSize` alarms to catch outlier payloads before hitting the 256KB limit
- **DLQ alarm uses `evaluation_periods = 1`** intentionally — even a single DLQ message is urgent and should alert immediately, unlike main queue alarms which use `2` to reduce flapping
- **Enable `enable_zero_sends_alarm`** for queues where you expect continuous producer traffic — detects silent producer failures within 15 minutes (default 3 × 5-min periods). Uses `treat_missing_data = breaching` so a missing metric also triggers the alarm.
- **External DLQ** — when using `dlq_arn`, the module looks up the external queue via data source for robust name/URL resolution. The external DLQ's `redrive_allow_policy` must be configured separately on that queue.
- **Dashboard includes DLQ widget** automatically when any DLQ is configured
