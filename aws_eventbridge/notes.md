# AWS EventBridge — Deep Reference Notes

> **Audience:** Cloud engineers building and maintaining EventBridge infrastructure.
> Every section includes the relevant Terraform resource / argument reference and operational notes.

---

## Table of Contents

1. [Service Overview](#1-service-overview)
2. [Core Concepts & Architecture](#2-core-concepts--architecture)
3. [Event Buses](#3-event-buses)
4. [Events — Structure & Schema](#4-events--structure--schema)
5. [Event Pattern Matching](#5-event-pattern-matching)
6. [Rules](#6-rules)
7. [Schedule Expressions](#7-schedule-expressions)
8. [Targets](#8-targets)
9. [Input Transformation](#9-input-transformation)
10. [Dead-Letter Queues (DLQ)](#10-dead-letter-queues-dlq)
11. [Retry Policy](#11-retry-policy)
12. [Event Archives & Replay](#12-event-archives--replay)
13. [Cross-Account & Cross-Region Routing](#13-cross-account--cross-region-routing)
14. [EventBridge Pipes](#14-eventbridge-pipes)
15. [EventBridge Scheduler](#15-eventbridge-scheduler)
16. [Schema Registry & Discovery](#16-schema-registry--discovery)
17. [IAM & Security](#17-iam--security)
18. [Encryption (KMS)](#18-encryption-kms)
19. [Service Limits & Quotas](#19-service-limits--quotas)
20. [CloudWatch Metrics](#20-cloudwatch-metrics)
21. [Observability — Alarms](#21-observability--alarms)
22. [Observability — Event Logging](#22-observability--event-logging)
23. [Observability — Dashboard](#23-observability--dashboard)
24. [Debugging & Troubleshooting](#24-debugging--troubleshooting)
25. [Terraform Resource Reference](#25-terraform-resource-reference)
26. [Best Practices & Patterns](#26-best-practices--patterns)
27. [This Module — Design Notes](#27-this-module--design-notes)

---

## 1. Service Overview

AWS EventBridge is a **serverless event bus** service that makes it easy to connect applications using events. It was originally Amazon CloudWatch Events (the `aws_cloudwatch_event_*` Terraform resources retain this naming for backwards compatibility).

| Feature | Detail |
|---|---|
| Delivery model | At-least-once, near real-time (usually < 500 ms) |
| Durability | Events in flight are persisted; targets are retried on failure |
| Throughput | Default bus: 10,000 events/s per region. Custom buses: configurable soft limit |
| Pricing | $1.00 per million custom events; schema discovery, Pipes, and Scheduler priced separately |
| Global service | Available in all commercial AWS regions; events do not cross regions automatically |

**Key differentiators from SNS/SQS:**

- Content-based filtering via JSON patterns (not attribute-based like SNS)
- Native integration with 200+ AWS services as both event sources and targets
- Event Replay via Archives
- Schema Registry with code binding generation
- EventBridge Pipes for point-to-point enrichment pipelines
- EventBridge Scheduler for one-off and recurring schedules at scale

---

## 2. Core Concepts & Architecture

```
Event Producer
     │
     ▼
 Event Bus  ──── Rule (Pattern Match / Schedule) ───▶ Target(s)
     │                                                     │
     │                                                     ├── Lambda
     │                                                     ├── SQS
     │                                                     ├── SNS
     │                                                     ├── Step Functions
     │                                                     ├── API Gateway
     │                                                     ├── Another Event Bus
     │                                                     └── 200+ more
     │
     └──── Archive ──▶ Replay
```

**Flow:**
1. Producer sends an event to an Event Bus (`PutEvents` API).
2. EventBridge evaluates the event against all rules on that bus.
3. Each matching rule invokes its configured targets.
4. If target invocation fails, the retry policy governs retries; undeliverable events go to DLQ.

---

## 3. Event Buses

### Types

| Type | Description |
|---|---|
| **Default** | One per account per region. Receives events from AWS services. Named `default`. Cannot be deleted. |
| **Custom** | User-created buses for application events. Up to 100 per region (soft limit). |
| **Partner** | Created by SaaS partners (Zendesk, Datadog, etc.) via EventBridge Partner Event Sources. |

### Key Properties

| Property | Notes |
|---|---|
| `name` | 1–256 chars. Letters, numbers, `.`, `-`, `_`, `/`. No colons. |
| `arn` | `arn:aws:events:<region>:<account>:event-bus/<name>` |
| `policy` | Resource-based policy for cross-account access (see §13) |
| `kms_key_identifier` | KMS key for server-side encryption at rest |
| `tags` | Standard AWS tags |

### Terraform — `aws_cloudwatch_event_bus`

```hcl
resource "aws_cloudwatch_event_bus" "this" {
  name              = "my-app-events"
  kms_key_identifier = aws_kms_key.eb.arn   # optional; enables SSE
  tags              = { Environment = "prod" }
}
```

**Key outputs:** `arn`, `name`

**Important:** Do NOT create a resource for the `default` bus — it exists automatically. Attach rules to it by setting `event_bus_name = "default"` (or omitting it) on the rule.

---

## 4. Events — Structure & Schema

### Standard Event Envelope

Every event published to EventBridge has this top-level structure:

```json
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "source": "com.myapp.orders",
  "account": "123456789012",
  "time": "2026-02-20T10:00:00Z",
  "region": "us-east-1",
  "resources": ["arn:aws:..."],
  "detail-type": "OrderPlaced",
  "detail": {
    "orderId": "ORD-001",
    "amount": 42.50,
    "currency": "USD"
  }
}
```

| Field | Max Size | Notes |
|---|---|---|
| `source` | — | Reverse-domain convention (`com.myapp.orders`). AWS services use `aws.*` |
| `detail-type` | — | Human-readable event type. Free-form string. |
| `detail` | 256 KB total event size | Arbitrary JSON. Can reference nested paths in patterns and input transformers. |
| `resources` | Array of strings | ARNs of resources involved in the event. |
| `time` | ISO 8601 | Defaults to `PutEvents` call time if omitted. |

**Total event size limit: 256 KB.** EventBridge rejects larger events at the `PutEvents` API.

### Sending Events — `PutEvents` API

```bash
aws events put-events --entries '[{
  "Source": "com.myapp.orders",
  "DetailType": "OrderPlaced",
  "Detail": "{\"orderId\":\"ORD-001\"}",
  "EventBusName": "my-app-events"
}]'
```

**Batch size:** Up to 10 entries per `PutEvents` call.
**Partial failures:** The API returns per-entry `FailedEntryCount`. Always check the response — HTTP 200 does not mean all events were accepted.

---

## 5. Event Pattern Matching

Patterns are JSON objects that describe which event fields must match. An event matches only if **all** specified fields match.

### Matching Types

| Type | Syntax | Example |
|---|---|---|
| **Exact match** | `"value"` | `"source": ["com.myapp"]` |
| **Prefix match** | `{"prefix": "str"}` | `"source": [{"prefix": "com.myapp"}]` |
| **Suffix match** | `{"suffix": "str"}` | `"detail-type": [{"suffix": "Created"}]` |
| **Anything-but** | `{"anything-but": [...]}` | `"status": [{"anything-but": ["DELETED"]}]` |
| **Numeric range** | `{"numeric": ["op", n, ...]}` | `"detail.amount": [{"numeric": [">", 0, "<=", 100]}]` |
| **Null** | `{"exists": false}` | Match if field is absent / null |
| **Exists** | `{"exists": true}` | Match if field is present (any value) |
| **Wildcard** | `{"wildcard": "str*"}` | `"source": [{"wildcard": "com.myapp.*"}]` |
| **IP CIDR** | `{"cidr": "x.x.x.x/y"}` | Match IP addresses in CIDR range |
| **OR (same field)** | Multiple array elements | `"source": ["a", "b"]` = a OR b |
| **AND (different fields)** | Multiple keys | `"source": [...], "detail-type": [...]` = AND |

### Example — Complex Pattern

```json
{
  "source": ["com.myapp.orders"],
  "detail-type": ["OrderPlaced", "OrderUpdated"],
  "detail": {
    "amount": [{"numeric": [">", 100]}],
    "currency": ["USD", "EUR"],
    "status": [{"anything-but": ["CANCELLED"]}]
  }
}
```

### Important Behaviours

- Patterns match against the **entire event envelope** including `source`, `account`, `region`, `detail-type`, `resources`, and `detail`.
- Array notation means the actual value must equal **at least one** of the listed values.
- Nested paths in `detail` are expressed as nested JSON objects, not dot notation in patterns.
- Pattern matching is case-**sensitive** for strings.
- A rule with no `event_pattern` and no `schedule_expression` is invalid.

### Terraform — Pattern as String

```hcl
resource "aws_cloudwatch_event_rule" "this" {
  event_pattern = jsonencode({
    source      = ["com.myapp.orders"]
    detail-type = ["OrderPlaced"]
    detail = {
      amount = [{ numeric = [">", 100] }]
    }
  })
}
```

**Use `jsonencode()`** to keep patterns as HCL objects — avoids escaping issues and keeps formatting consistent.

---

## 6. Rules

Rules evaluate incoming events and route matching ones to targets. A rule is attached to exactly one bus.

### Properties

| Property | Notes |
|---|---|
| `name` | 1–64 chars. Letters, numbers, `.`, `-`, `_`. Unique per bus. |
| `event_bus_name` | Bus name or ARN. Omit or set to `"default"` for the default bus. |
| `event_pattern` | Mutually exclusive with `schedule_expression`. |
| `schedule_expression` | Mutually exclusive with `event_pattern`. Only valid on the `default` bus. |
| `state` | `ENABLED` or `DISABLED`. |
| `description` | Optional free-text. |

### Terraform — `aws_cloudwatch_event_rule`

```hcl
resource "aws_cloudwatch_event_rule" "order_placed" {
  name           = "order-placed"
  event_bus_name = aws_cloudwatch_event_bus.app.name
  description    = "Fires when an order is placed"

  event_pattern = jsonencode({
    source      = ["com.myapp.orders"]
    detail-type = ["OrderPlaced"]
  })

  state = "ENABLED"
  tags  = { Environment = "prod" }
}
```

**Key outputs:** `arn`, `name`

The `arn` is required as `source_arn` in `aws_lambda_permission` to restrict which rule can invoke the Lambda.

---

## 7. Schedule Expressions

Schedule rules fire at a specific time or interval. They are **only valid on the default bus**.

### Rate Expressions

```
rate(value unit)
```

| Unit values | `minute`, `minutes`, `hour`, `hours`, `day`, `days` |
|---|---|
| Minimum | `rate(1 minute)` |
| Examples | `rate(5 minutes)`, `rate(1 hour)`, `rate(7 days)` |

### Cron Expressions

```
cron(minutes hours day-of-month month day-of-week year)
```

| Field | Values | Wildcards |
|---|---|---|
| Minutes | 0–59 | `,`, `-`, `*`, `/` |
| Hours | 0–23 | `,`, `-`, `*`, `/` |
| Day-of-month | 1–31 | `,`, `-`, `*`, `?`, `/`, `L`, `W` |
| Month | 1–12 or JAN–DEC | `,`, `-`, `*`, `/` |
| Day-of-week | 1–7 or SUN–SAT | `,`, `-`, `*`, `?`, `/`, `L`, `#` |
| Year | 1970–2199 | `,`, `-`, `*`, `/` |

**Note:** Day-of-month and Day-of-week cannot both be specified — one must be `?`.

```
cron(0 2 * * ? *)          # Every day at 02:00 UTC
cron(0 8 ? * MON-FRI *)    # Weekdays at 08:00 UTC
cron(0 0 1 * ? *)          # First day of every month at midnight UTC
cron(0/15 * * * ? *)       # Every 15 minutes
```

**All cron times are UTC.** There is no timezone support in EventBridge rules — use EventBridge Scheduler (§15) for timezone-aware schedules.

### Terraform

```hcl
resource "aws_cloudwatch_event_rule" "daily" {
  name                = "daily-cleanup"
  schedule_expression = "cron(0 2 * * ? *)"
  # event_bus_name omitted → attaches to default bus
}
```

---

## 8. Targets

Each rule can have up to **5 targets** (soft limit; can be raised to 100). When a rule matches, EventBridge invokes all targets concurrently.

### Target Configuration

| Field | Notes |
|---|---|
| `arn` | ARN of the destination service. |
| `id` | 1–64 chars. Unique per rule. Identifies the target within the rule. |
| `role_arn` | IAM role EventBridge assumes to call the target. Required for most non-Lambda targets. |
| `input` | Static JSON string to send instead of the original event. |
| `input_path` | JSONPath expression to extract a portion of the event as input. |
| `input_transformer` | Extract fields via JSONPath and build a custom input payload. |
| `dead_letter_config.arn` | SQS queue ARN for undeliverable events. |
| `retry_policy` | Max retries and event age before giving up (see §11). |

### Supported Target Services (common)

| Service | Requires `role_arn` | Notes |
|---|---|---|
| AWS Lambda | No (uses resource-based policy) | Most common target. `aws_lambda_permission` required. |
| Amazon SQS | Yes (for encrypted queues) | Standard and FIFO queues supported. |
| Amazon SNS | No (uses resource policy) | Topic access controlled by SNS policy. |
| AWS Step Functions | Yes | State machine ARN. Starts new execution. |
| Amazon Kinesis Data Streams | Yes | Puts records into the stream. |
| Amazon Kinesis Firehose | Yes | Delivers to S3/Redshift/etc. |
| API Gateway (REST/HTTP) | Yes | Calls a specific endpoint. |
| Amazon ECS Task | Yes | Runs a task in a cluster. |
| AWS Batch Job | Yes | Submits a batch job. |
| Amazon SageMaker Pipeline | Yes | Starts pipeline execution. |
| CloudWatch Log Group | No | Delivers event JSON to a log group. |
| Another Event Bus | Yes (cross-account) | Forwards to same-account or cross-account bus. |
| AWS SSM | Yes | Run Automation documents or Send Commands. |

### Terraform — `aws_cloudwatch_event_target`

```hcl
resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.order_placed.name
  event_bus_name = aws_cloudwatch_event_bus.app.name
  target_id      = "process-order"
  arn            = aws_lambda_function.processor.arn
  role_arn       = null  # Lambda uses resource-based policy, not role_arn

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600   # 1 hour
    maximum_retry_attempts       = 10
  }
}
```

### Lambda Permissions

EventBridge invokes Lambda using a **resource-based policy**, not an IAM role. You must grant `lambda:InvokeFunction` permission with `Principal = "events.amazonaws.com"` and `SourceArn` scoped to the rule ARN.

```hcl
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_placed.arn
  # qualifier   = "prod"  # optional: restrict to alias or version
}
```

**Scoping `source_arn` to the rule ARN (not bus ARN) is a security best practice** — it ensures only that specific rule can invoke the function.

---

## 9. Input Transformation

Input transformation lets you reshape the event before delivering it to a target. Three mutually exclusive options:

### Option 1 — `input` (static payload)

Replaces the entire event with a static JSON string:

```hcl
input = jsonencode({ message = "Event received" })
```

### Option 2 — `input_path` (JSONPath extraction)

Extracts a single field from the event using JSONPath:

```hcl
input_path = "$.detail"          # sends only the detail object
input_path = "$.detail.orderId"  # sends the scalar value
```

### Option 3 — `input_transformer` (template-based reshaping)

Extracts multiple fields and renders them into a custom template:

```hcl
input_transformer {
  input_paths_map = {
    orderId   = "$.detail.orderId"
    email     = "$.detail.customerEmail"
    timestamp = "$.time"
  }
  input_template = <<-JSON
    {
      "order": "<orderId>",
      "notify": "<email>",
      "at": "<timestamp>"
    }
  JSON
}
```

**Rules:**
- `input_paths_map` keys are referenced in `input_template` as `<key>`.
- If the template is a quoted string (not an object), values are injected as plain strings.
- Extracted values are JSON-typed — strings are quoted, numbers are not.
- Maximum 100 variables in `input_paths_map`.
- Maximum 8,192 characters in `input_template`.

### JSONPath Syntax

| Expression | Meaning |
|---|---|
| `$.source` | Top-level field |
| `$.detail.orderId` | Nested field |
| `$.detail.items[0]` | First array element |
| `$.detail.items[0].sku` | Nested in array element |
| `$.resources[0]` | First resource ARN |

---

## 10. Dead-Letter Queues (DLQ)

When EventBridge exhausts retries (or `maximum_event_age_in_seconds` expires), the event is sent to the DLQ if configured.

### DLQ Message Structure

The SQS message body is the **original event JSON**. EventBridge adds these message attributes:

| Attribute | Type | Description |
|---|---|---|
| `ERROR_CODE` | String | `NO_PERMISSION`, `RESOURCE_NOT_FOUND`, `THROTTLE`, etc. |
| `ERROR_MESSAGE` | String | Human-readable error description |
| `RULE_ARN` | String | ARN of the rule that triggered the delivery |
| `TARGET_ARN` | String | ARN of the failed target |
| `TARGET_ID` | String | Target ID within the rule |
| `APPROXIMATE_FIRST_RECEIVE_TIMESTAMP` | Number | Unix epoch milliseconds |

### Requirements

- DLQ must be an **SQS standard queue** (not FIFO).
- EventBridge must have `sqs:SendMessage` permission on the queue.
- If the queue is encrypted with a customer-managed KMS key, EventBridge must have `kms:GenerateDataKey` and `kms:Decrypt` on that key.
- DLQ is configured **per target**, not per rule.

### SQS Queue Policy for EventBridge DLQ

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowEventBridgeSendMessage",
    "Effect": "Allow",
    "Principal": { "Service": "events.amazonaws.com" },
    "Action": "sqs:SendMessage",
    "Resource": "arn:aws:sqs:<region>:<account>:<queue-name>",
    "Condition": {
      "ArnEquals": {
        "aws:SourceArn": "arn:aws:events:<region>:<account>:rule/<bus-name>/<rule-name>"
      }
    }
  }]
}
```

### Critical Metric — `InvocationsFailedToBeSentToDLQ`

If EventBridge **cannot reach the DLQ itself** (permissions issue, queue deleted, etc.), the event is **silently dropped** — it never appears in the DLQ and there is no automatic notification. This is one of the most dangerous silent failure modes. **Always alarm on this metric.**

### Terraform

```hcl
resource "aws_sqs_queue" "dlq" {
  name = "my-rule-dlq"
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridge"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
    }]
  })
}
```

---

## 11. Retry Policy

Controls how EventBridge retries failed target invocations.

| Parameter | Default | Range | Notes |
|---|---|---|---|
| `maximum_retry_attempts` | 185 | 0–185 | 0 = no retries; event goes to DLQ immediately on first failure. |
| `maximum_event_age_in_seconds` | 86400 (24 h) | 60–86400 | EventBridge stops retrying after this window even if retry count is not exhausted. |

### Retry Behaviour

- EventBridge uses **exponential backoff with jitter** between retries.
- The retry clock starts at the event's `time` field, not the delivery attempt time.
- A target invocation counts as failed if the service returns an error (e.g., Lambda throws an unhandled exception, SQS returns throttle error, etc.).
- Lambda throttles (`TooManyRequestsException`) are retried separately with up to 24 hours of built-in retry by EventBridge before counting against the configured limits.

### Terraform

```hcl
retry_policy {
  maximum_event_age_in_seconds = 3600   # abandon after 1 hour
  maximum_retry_attempts       = 3      # max 3 delivery attempts
}
```

---

## 12. Event Archives & Replay

### Archives

Archives record events from a bus (or a filtered subset) to an EventBridge-managed store.

| Property | Notes |
|---|---|
| `event_source_arn` | The bus ARN whose events to archive. |
| `event_pattern` | Optional filter — archive only matching events. Null = archive everything. |
| `retention_days` | 0 = indefinite. > 0 = days before automatic expiry. |
| Storage | Managed by AWS; priced per GB per month. |

```hcl
resource "aws_cloudwatch_event_archive" "this" {
  name             = "order-events-archive"
  event_source_arn = aws_cloudwatch_event_bus.app.arn
  retention_days   = 90

  event_pattern = jsonencode({
    source = ["com.myapp.orders"]
  })
}
```

**Key outputs:** `arn`, `name`

### Replay

Replay re-processes archived events through the bus's current rules and targets. Useful for:
- Recovering from target failures (re-deliver missed events)
- Backfilling after deploying new rules/targets
- Testing new consumers against historical data

**Replay is initiated via the AWS Console or API/CLI — it is not managed by a Terraform resource as of the current provider.**

```bash
aws events start-replay \
  --replay-name "backfill-2026-02-01" \
  --event-source-arn "arn:aws:events:us-east-1:123456789012:archive/order-events-archive" \
  --event-start-time "2026-02-01T00:00:00Z" \
  --event-end-time   "2026-02-10T00:00:00Z" \
  --destination '{
    "Arn": "arn:aws:events:us-east-1:123456789012:event-bus/my-app-events"
  }'
```

**Replay considerations:**
- Replayed events have a `replay-name` field in the envelope so consumers can detect and skip them if needed.
- Targets must be idempotent to safely handle replays.
- Replay throughput is throttled; large replays may take significant time.

---

## 13. Cross-Account & Cross-Region Routing

### Cross-Account (same region)

1. Attach a **resource-based policy** to the target bus in Account B granting Account A `events:PutEvents`.
2. Create a rule in Account A targeting the bus ARN in Account B using an IAM role.

**Target bus policy (Account B):**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowAccountAEvents",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::ACCOUNT_A_ID:root" },
    "Action": "events:PutEvents",
    "Resource": "arn:aws:events:us-east-1:ACCOUNT_B_ID:event-bus/central-bus"
  }]
}
```

**Terraform — `aws_cloudwatch_event_bus_policy`:**

```hcl
resource "aws_cloudwatch_event_bus_policy" "cross_account" {
  event_bus_name = aws_cloudwatch_event_bus.central.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAccount"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::111122223333:root" }
      Action    = "events:PutEvents"
      Resource  = aws_cloudwatch_event_bus.central.arn
    }]
  })
}
```

**Rule target in Account A pointing to Account B bus:**

```hcl
resource "aws_cloudwatch_event_target" "cross_account" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "cross-account-bus"
  arn       = "arn:aws:events:us-east-1:ACCOUNT_B_ID:event-bus/central-bus"
  role_arn  = aws_iam_role.eb_cross_account.arn  # must have events:PutEvents on target bus
}
```

### Cross-Region

EventBridge does not natively forward events across regions. To route cross-region:

1. Use a Lambda target that calls `PutEvents` to the target region.
2. Or use EventBridge Pipes with an enrichment step.

**Global EventBridge (as of 2024)** — AWS announced Global EventBridge for routing to buses in other regions natively, available in preview in some regions. Check the latest AWS docs before using.

---

## 14. EventBridge Pipes

Pipes provide **point-to-point** integrations with filtering, enrichment, and transformation between a source and a target.

**Key difference from Rules:** Rules are one-to-many fan-out from a bus. Pipes are one-to-one with stateful processing (polling sources, batching, enrichment).

### Components

```
Source → [Filter] → [Enrichment] → [Transform] → Target
```

| Component | Description |
|---|---|
| **Source** | Kinesis, DynamoDB Streams, SQS, Kafka, ActiveMQ, RabbitMQ |
| **Filter** | JSON pattern filter — same syntax as EventBridge rules |
| **Enrichment** | Lambda, Step Functions, API Gateway, API Destination (optional) |
| **Target** | 14+ targets including Lambda, SQS, SNS, EventBridge buses, HTTP endpoints |

### Terraform — `aws_pipes_pipe`

```hcl
resource "aws_pipes_pipe" "this" {
  name     = "sqs-to-lambda"
  role_arn = aws_iam_role.pipe.arn

  source     = aws_sqs_queue.source.arn
  target     = aws_lambda_function.processor.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 5
    }
    filter_criteria {
      filter {
        pattern = jsonencode({
          body = { eventType = ["ORDER_CREATED"] }
        })
      }
    }
  }

  enrichment = aws_lambda_function.enricher.arn

  target_parameters {
    lambda_function_parameters {
      invocation_type = "FIRE_AND_FORGET"  # or REQUEST_RESPONSE
    }
  }
}
```

---

## 15. EventBridge Scheduler

A **separate service** from EventBridge Events for creating millions of scheduled invocations. Distinct from EventBridge Rules schedules.

### Key Differences vs EventBridge Rules Schedules

| Feature | EventBridge Rules | EventBridge Scheduler |
|---|---|---|
| Scale | Hundreds of rules | Millions of schedules |
| Timezone support | UTC only | All IANA timezones |
| One-time schedules | No | Yes (`at(...)`) |
| Flexible time windows | No | Yes |
| State management | Rules are always "on" | Individual schedule enable/disable |
| Drift compensation | No | Yes (flexible window) |

### Terraform — `aws_scheduler_schedule`

```hcl
resource "aws_scheduler_schedule" "this" {
  name       = "daily-report"
  group_name = "my-app"

  flexible_time_window {
    mode                      = "FLEXIBLE"  # or OFF
    maximum_window_in_minutes = 30
  }

  schedule_expression          = "cron(0 9 * * ? *)"
  schedule_expression_timezone = "America/New_York"
  start_date                   = "2026-03-01T00:00:00Z"
  end_date                     = "2027-03-01T00:00:00Z"
  state                        = "ENABLED"

  target {
    arn      = aws_lambda_function.reporter.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({ report_type = "daily" })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }

    dead_letter_config {
      arn = aws_sqs_queue.dlq.arn
    }
  }
}
```

### Schedule Formats (Scheduler)

- `rate(5 minutes)` — interval
- `cron(0 9 * * ? *)` — standard cron
- `at(2026-12-31T23:59:59)` — one-time future schedule

### IAM for Scheduler

```hcl
resource "aws_iam_role" "scheduler" {
  name = "eventbridge-scheduler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
```

---

## 16. Schema Registry & Discovery

EventBridge Schema Registry automatically discovers event schemas from your buses and stores them.

### Features

| Feature | Description |
|---|---|
| Auto-discovery | Enable on a bus → EventBridge infers schemas from real events |
| Schema versioning | Each update creates a new version; previous versions retained |
| Code bindings | Download strongly-typed bindings for Java, Python, TypeScript |
| Pre-built schemas | 100+ AWS service event schemas available in `aws.events` registry |

### Terraform — Schema Discovery

```hcl
resource "aws_schemas_discoverer" "this" {
  source_arn  = aws_cloudwatch_event_bus.app.arn
  description = "Auto-discover schemas for app-events bus"
  tags        = { Environment = "prod" }
}
```

### Terraform — Schema (manual)

```hcl
resource "aws_schemas_schema" "order_placed" {
  name          = "com.myapp.orders@OrderPlaced"
  registry_name = "discovered-schemas"
  type          = "OpenApi3"
  description   = "Schema for OrderPlaced events"

  content = jsonencode({
    openapi = "3.0.0"
    info = { version = "1.0.0", title = "OrderPlaced" }
    paths = {}
    components = {
      schemas = {
        AWSEvent = {
          type = "object"
          properties = {
            detail = { "$ref" = "#/components/schemas/OrderPlaced" }
          }
        }
        OrderPlaced = {
          type = "object"
          properties = {
            orderId = { type = "string" }
            amount  = { type = "number" }
          }
        }
      }
    }
  })
}
```

---

## 17. IAM & Security

### Permissions Required to Publish Events

```json
{
  "Effect": "Allow",
  "Action": "events:PutEvents",
  "Resource": "arn:aws:events:<region>:<account>:event-bus/<bus-name>"
}
```

Scope to specific bus ARNs — do not use `*`.

### Permissions Required by EventBridge to Invoke Targets

**Lambda:** Resource-based policy (see §8).

**SQS, Kinesis, SNS, Step Functions (and most others):** IAM role assumed by EventBridge:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "events.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

Attach a policy granting the appropriate actions on the target resource to this role.

### Least-Privilege Patterns

| Scenario | Recommendation |
|---|---|
| Lambda targets | Use `source_arn` scoped to the rule ARN in `aws_lambda_permission` |
| SQS targets | One IAM role per bus or per group of related rules |
| Cross-account | Use `aws:SourceAccount` condition in trust policies |
| PutEvents from app | Scope `Resource` to the specific bus ARN; never `*` |

### VPC Endpoint for EventBridge

EventBridge supports a VPC Interface Endpoint (`com.amazonaws.<region>.events`). Use this when your producers run in a VPC and you want traffic to stay on the AWS network:

```hcl
resource "aws_vpc_endpoint" "events" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.events"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true
}
```

---

## 18. Encryption (KMS)

### Encryption at Rest

Custom event buses can be encrypted with a customer-managed KMS key:

```hcl
resource "aws_cloudwatch_event_bus" "this" {
  name               = "secure-bus"
  kms_key_identifier = aws_kms_key.eb.arn
}
```

**Key policy additions required:**

```json
{
  "Sid": "AllowEventBridgeToUseKey",
  "Effect": "Allow",
  "Principal": { "Service": "events.amazonaws.com" },
  "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
  "Resource": "*"
}
```

### Event Archives

Archives use AWS-managed encryption by default. There is no option to specify a customer-managed KMS key for archives at this time.

### CloudWatch Logs (Event Logging)

When using the event logging feature, the CloudWatch Log Group can be encrypted with a KMS key:

```hcl
resource "aws_cloudwatch_log_group" "event_logs" {
  name       = "/aws/events/my-bus"
  kms_key_id = aws_kms_key.logs.arn
}
```

The KMS key must grant CWL service permissions (`logs.amazonaws.com`):

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "logs.<region>.amazonaws.com" },
  "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:DescribeKey"],
  "Resource": "*"
}
```

---

## 19. Service Limits & Quotas

| Limit | Default | Adjustable |
|---|---|---|
| Custom event buses per region | 100 | Yes |
| Rules per event bus | 300 | Yes |
| Targets per rule | 5 | Yes (up to 100) |
| Event size | 256 KB | No |
| PutEvents batch size | 10 entries | No |
| Invocations per second (default bus) | 18,750 (equals 10,000 rules × 1.875) | Yes |
| PutEvents throughput | 10,000 events/s | Yes |
| Archives | 100 per region | Yes |
| Concurrent replays | 1 | No |
| Schema registries | 10 | Yes |
| Schemas per registry | 100 | Yes |
| Input transformer variables | 100 | No |
| Input template characters | 8,192 | No |

---

## 20. CloudWatch Metrics

All EventBridge metrics are published to the `AWS/Events` namespace.

### Rule & Bus Metrics

| Metric | Dimensions | Description | Alert? |
|---|---|---|---|
| `MatchedEvents` | `RuleName`, `EventBusName` | Events matching the rule pattern | Informational |
| `TriggeredRules` | `EventBusName` | Rules triggered at least once in the period | Informational |
| `Invocations` | `RuleName`, `EventBusName` | Target invocation attempts | Informational |
| `FailedInvocations` | `RuleName`, `EventBusName` | Invocations that failed after all retries | **Yes — critical** |
| `ThrottledRules` | `EventBusName` | Rules throttled due to concurrent invocation limit | Yes |
| `InvocationsSentToDLQ` | `EventBusName` `RuleName`, `TargetArn` | Events successfully sent to DLQ | Yes |
| `InvocationsFailedToBeSentToDLQ` | `EventBusName` | Events that failed to reach DLQ (SILENT DROPS) | **Yes — critical** |
| `DeadLetterInvocations` | `RuleName`, `EventBusName` | Alias for `InvocationsSentToDLQ` in older docs | — |

### Schedule-Specific Metrics

| Metric | Dimensions | Description |
|---|---|---|
| `ScheduledEventCount` | `ScheduleName` | Number of scheduled events triggered |
| `ScheduledEventFailures` | `ScheduleName` | Failures for scheduled events |

### Metrics Availability

- Metrics are published with **1-minute granularity** and stored for 15 months.
- Dimensions: can alarm at bus level (no `RuleName` dimension) or rule level (with `RuleName`).
- Zero-data periods: if no events match a rule, `MatchedEvents` is not published (not zero). Use `treat_missing_data = "notBreaching"` for most alarms.

---

## 21. Observability — Alarms

### Recommended Alarm Set

#### Per-Bus Alarms

| Alarm | Metric | Threshold | Danger Level |
|---|---|---|---|
| Throttled rules | `ThrottledRules` | ≥ 1 | High |
| DLQ deliveries | `InvocationsSentToDLQ` | ≥ 1 | Medium (events failing) |
| DLQ unreachable | `InvocationsFailedToBeSentToDLQ` | ≥ 1 | **Critical (silent data loss)** |

#### Per-Rule Alarms

| Alarm | Metric | Threshold | Danger Level |
|---|---|---|---|
| Failed invocations | `FailedInvocations` | ≥ 1 | High |

#### DLQ Alarms (SQS `AWS/SQS` namespace)

| Alarm | Metric | Threshold | Notes |
|---|---|---|---|
| DLQ depth | `ApproximateNumberOfMessagesVisible` | ≥ 1 | Indicates events awaiting investigation |
| DLQ message age | `ApproximateAgeOfOldestMessage` | > 3600 s | Events sitting unprocessed |

### Terraform — Standard Alarm

```hcl
resource "aws_cloudwatch_metric_alarm" "failed_invocations" {
  alarm_name          = "eb-failed-invocations-order-placed"
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    EventBusName = "my-app-events"
    RuleName     = "order-placed"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

### Anomaly Detection Alarm

Useful when you do not have a static baseline (bursty traffic patterns):

```hcl
resource "aws_cloudwatch_metric_alarm" "invocations_anomaly" {
  alarm_name          = "eb-invocations-anomaly"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "ad1"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "Invocations anomaly band"
    return_data = true
  }

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Events"
      period      = 300
      stat        = "Sum"
      dimensions = {
        EventBusName = "my-app-events"
        RuleName     = "order-placed"
      }
    }
  }
}
```

---

## 22. Observability — Event Logging

The most powerful debugging tool: route ALL events from a bus to a CloudWatch Log Group via a catch-all rule.

### Implementation

```hcl
# 1. Log Group
resource "aws_cloudwatch_log_group" "event_logs" {
  name              = "/aws/events/my-app-events"
  retention_in_days = 14
}

# 2. Resource policy allowing EventBridge to write logs
resource "aws_cloudwatch_log_resource_policy" "event_logs" {
  policy_name = "eventbridge-to-cwl"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.event_logs.arn}:*"
    }]
  })
}

# 3. Catch-all rule
resource "aws_cloudwatch_event_rule" "catch_all" {
  name           = "catch-all-for-logging"
  event_bus_name = aws_cloudwatch_event_bus.app.name
  event_pattern  = jsonencode({ source = [{ prefix = "" }] })
}

# 4. Target — CWL log group
resource "aws_cloudwatch_event_target" "catch_all" {
  rule           = aws_cloudwatch_event_rule.catch_all.name
  event_bus_name = aws_cloudwatch_event_bus.app.name
  target_id      = "cloudwatch-logs"
  arn            = aws_cloudwatch_log_group.event_logs.arn
}
```

### Querying Logs

```
# CloudWatch Logs Insights — find all OrderPlaced events in last hour
fields @timestamp, source, `detail-type`, detail.orderId
| filter `detail-type` = "OrderPlaced"
| sort @timestamp desc
| limit 50
```

```
# Find failed delivery events (look for missing downstream calls)
fields @timestamp, source, `detail-type`
| filter source like /com.myapp.orders/
| sort @timestamp desc
```

**Cost consideration:** Every event on the bus is written to CWL. For high-throughput buses this can be expensive. Use a filtered `event_pattern` on the catch-all rule to limit what is logged, or restrict to non-production environments.

---

## 23. Observability — Dashboard

A CloudWatch Dashboard provides a unified operational view across all bus metrics.

### Recommended Widgets

| Widget | Metrics | Purpose |
|---|---|---|
| MatchedEvents (per rule) | `MatchedEvents` by `RuleName` | Verify events are flowing |
| Invocations (per rule) | `Invocations` by `RuleName` | Verify targets are being called |
| FailedInvocations | `FailedInvocations` bus + per rule | Delivery health |
| ThrottledRules | `ThrottledRules` | Throughput health |
| DLQ depth | SQS `ApproximateNumberOfMessagesVisible` | Backlog check |
| InvocationsSentToDLQ | `InvocationsSentToDLQ` | DLQ traffic |
| InvocationsFailedToBeSentToDLQ | `InvocationsFailedToBeSentToDLQ` | **Silent drop detection** |

### Terraform — `aws_cloudwatch_dashboard`

```hcl
resource "aws_cloudwatch_dashboard" "eventbridge" {
  dashboard_name = "my-app-eventbridge"
  dashboard_body = jsonencode({
    widgets = [{
      type   = "metric"
      x = 0; y = 0; width = 12; height = 6
      properties = {
        title   = "MatchedEvents"
        region  = "us-east-1"
        stat    = "Sum"
        period  = 60
        metrics = [
          ["AWS/Events", "MatchedEvents", "RuleName", "order-placed", "EventBusName", "app-events"]
        ]
      }
    }]
  })
}
```

---

## 24. Debugging & Troubleshooting

### Problem: Events published but rule not triggering

1. **Check the event pattern** — Use the EventBridge Console → Event buses → "Send events" to test with a sample payload. The console provides a pattern tester.
2. **Check `source` field** — AWS service events use `aws.` prefix. Custom events use your custom source. Pattern and event source must match exactly (case-sensitive).
3. **Verify `event_bus_name`** — Rule and `PutEvents` call must reference the same bus.
4. **Check `MatchedEvents` metric** — If zero, the event is not matching the pattern. If > 0 but `Invocations` is zero, there may be a target configuration issue.

### Problem: Rule matches but Lambda not invoked

1. **Check `aws_lambda_permission`** — Lambda resource-based policy must exist with `Principal = "events.amazonaws.com"` and `SourceArn` pointing to the rule ARN.
2. **Check Lambda concurrency limits** — Throttling causes EventBridge to retry with backoff; monitor `ThrottledRules` metric.
3. **Check Lambda function state** — Function must not be in failed/pending state.

### Problem: `FailedInvocations` alarm firing

1. Check the **DLQ** for the affected target — the `ERROR_CODE` attribute reveals the root cause.
2. Check **CloudWatch Logs** for the Lambda function or target for application errors.
3. Common error codes:
   | `ERROR_CODE` | Meaning |
   |---|---|
   | `NO_PERMISSION` | EventBridge lacks permission to invoke target |
   | `RESOURCE_NOT_FOUND` | Target resource deleted or wrong ARN |
   | `THROTTLE` | Target is throttling EventBridge |
   | `SDK_CLIENT_ERROR` | Network or SDK-level error |
   | `BAD_ENDPOINT` | API destination URL unreachable |

### Problem: Events silently dropped (`InvocationsFailedToBeSentToDLQ`)

1. **DLQ does not exist** — queue was deleted after target was configured.
2. **Missing SQS queue policy** — EventBridge cannot authenticate to send the message.
3. **KMS key issue** — queue is encrypted; EventBridge lacks `kms:GenerateDataKey`.
4. Resolution: Fix the DLQ, then replay from archive if one is configured.

### Problem: Scheduled rule not firing

1. **Schedule rules only work on the default bus** — verify `event_bus_name` is `default` or omitted.
2. **Check rule state** — must be `ENABLED`.
3. **Check `ScheduledEventCount` metric** — if it's firing but the target is not invoked, see the target troubleshooting steps above.
4. **Cron timezone** — all times are UTC. Verify the hour matches your intended UTC time.

### Testing Tools

**EventBridge Console — Event pattern tester:**
Console → EventBridge → Event buses → [bus] → "Test event pattern" — paste a sample event and pattern; immediately shows match/no-match.

**AWS CLI — Send test event:**
```bash
aws events put-events --entries '[{
  "Source": "test.source",
  "DetailType": "TestEvent",
  "Detail": "{\"key\": \"value\"}",
  "EventBusName": "my-app-events"
}]'
```

**EventBridge Sandbox (Console):**
EventBridge → Sandbox — interactive environment to test event patterns and input transformers visually.

**CloudWatch Logs Insights (with catch-all logging enabled):**
```
fields @timestamp, source, `detail-type`, @message
| filter source = "com.myapp.orders"
| sort @timestamp desc
| limit 20
```

### Common Configuration Mistakes

| Mistake | Effect | Fix |
|---|---|---|
| `event_bus_name` mismatch between rule and target | Target never receives events | Ensure rule and target reference same bus |
| Missing `aws_lambda_permission` | Lambda silently not invoked; `FailedInvocations` fires | Add `aws_lambda_permission` for the rule ARN |
| Schedule rule on custom bus | Rule created but never fires | Move schedule to `default` bus |
| `input`, `input_path`, `input_transformer` all set | Terraform validation error | Use exactly one |
| DLQ queue policy missing | DLQ receives no messages; `InvocationsFailedToBeSentToDLQ` | Add SQS resource policy |
| KMS on DLQ without EventBridge key permissions | Same as above | Add `kms:GenerateDataKey` to key policy |
| Overly broad event pattern (`{}`) | Every event on the bus triggers the rule | Scope pattern to `source` and `detail-type` |
| `maximum_event_age_in_seconds < 60` | Terraform validation error | Minimum is 60 seconds |

---

## 25. Terraform Resource Reference

### Resources Used in This Module

| Resource | Purpose | Terraform Docs |
|---|---|---|
| `aws_cloudwatch_event_bus` | Create custom event bus | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus) |
| `aws_cloudwatch_event_rule` | Create event rule (pattern or schedule) | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) |
| `aws_cloudwatch_event_target` | Attach target to rule | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) |
| `aws_lambda_permission` | Grant EventBridge invoke on Lambda | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) |
| `aws_cloudwatch_event_archive` | Archive events from a bus | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_archive) |
| `aws_cloudwatch_event_bus_policy` | Resource-based policy on a bus | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus_policy) |
| `aws_cloudwatch_metric_alarm` | CloudWatch alarms for metrics | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) |
| `aws_cloudwatch_log_group` | Log group for event logging | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) |
| `aws_cloudwatch_log_resource_policy` | Allow EventBridge to write to CWL | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) |
| `aws_cloudwatch_dashboard` | CloudWatch dashboard | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) |

### Related Resources (Not in Module — Reference)

| Resource | Purpose | Terraform Docs |
|---|---|---|
| `aws_pipes_pipe` | EventBridge Pipes | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/pipes_pipe) |
| `aws_scheduler_schedule` | EventBridge Scheduler | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) |
| `aws_scheduler_schedule_group` | Scheduler schedule group | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule_group) |
| `aws_schemas_discoverer` | Schema Registry discoverer | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/schemas_discoverer) |
| `aws_schemas_schema` | Schema definition | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/schemas_schema) |
| `aws_schemas_registry` | Custom schema registry | [registry.terraform.io/...](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/schemas_registry) |

### Key Argument Details

#### `aws_cloudwatch_event_rule`

```
name                  string     required   Rule name, unique per bus
event_bus_name        string     optional   Omit = default bus
event_pattern         string     optional*  Mutually exclusive with schedule_expression
schedule_expression   string     optional*  Mutually exclusive with event_pattern; default bus only
state                 string     optional   ENABLED (default) | DISABLED
description           string     optional
role_arn              string     optional   Required if pattern must be evaluated with cross-account perms
tags                  map        optional

* exactly one must be set
```

#### `aws_cloudwatch_event_target`

```
rule             string     required   Rule name (not ARN)
target_id        string     required   Unique ID within the rule, 1-64 chars
arn              string     required   Target resource ARN
event_bus_name   string     optional   Must match the rule's bus
role_arn         string     optional   IAM role EventBridge assumes; not needed for Lambda
input            string     optional*  Static JSON payload
input_path       string     optional*  JSONPath expression
input_transformer block     optional*  input_paths_map + input_template

* at most one may be set

dead_letter_config {
  arn              string     required   SQS queue ARN
}

retry_policy {
  maximum_event_age_in_seconds   number   60–86400
  maximum_retry_attempts         number   0–185
}
```

#### `aws_cloudwatch_event_archive`

```
name             string     required
event_source_arn string     required   Source bus ARN
event_pattern    string     optional   Filter; null = archive everything
retention_days   number     optional   0 = indefinite (default)
description      string     optional
```

#### `aws_cloudwatch_metric_alarm` (EventBridge-specific)

```
namespace    = "AWS/Events"

# Key dimensions:
dimensions = {
  EventBusName = "my-app-events"  # required for most metrics
  RuleName     = "order-placed"   # optional; omit for bus-level metrics
}

# Key metrics:
metric_name in [
  "MatchedEvents",
  "Invocations",
  "FailedInvocations",
  "ThrottledRules",
  "TriggeredRules",
  "InvocationsSentToDLQ",
  "InvocationsFailedToBeSentToDLQ"
]
```

---

## 26. Best Practices & Patterns

### Event Design

- **Use reverse-domain `source` naming** — `com.mycompany.service`. Never reuse the `aws.` prefix.
- **Use descriptive `detail-type`** — `OrderPlaced`, `UserRegistered`, `PaymentFailed`. Past-tense verb-noun convention.
- **Include correlation IDs** in `detail` — `requestId`, `traceId`, `correlationId` for distributed tracing.
- **Version your events explicitly** — add `detail.eventVersion = "1.0"` to enable forward-compatible schema evolution.
- **Keep events small** — store large payloads in S3 and reference them by presigned URL or S3 path in the event. Saves cost and stays under the 256 KB limit.

### Rule & Target Patterns

- **One target type per rule** — avoids coupling unrelated consumers. Easier to manage permissions and retries independently.
- **Scope event patterns tightly** — include `source`, `detail-type`, and key `detail` fields to avoid unintended rule matches.
- **Name rules semantically** — `order-placed-process`, `user-registered-notify`. Avoid generic names like `rule-1`.
- **Always configure DLQ on production targets** — no excuse for silent drops.
- **Set `maximum_retry_attempts = 0` for idempotent-unsafe targets** — if the target cannot safely be called twice, drop on first failure and route straight to DLQ.

### Security

- **Scope `source_arn` in Lambda permissions** — use rule ARN, not bus ARN.
- **Use IAM conditions on PutEvents** — restrict publishers to specific `events:source` values using `events:source` condition key.
- **Enable SSE on custom buses** with customer-managed KMS for compliance workloads.
- **Rotate and monitor cross-account bus policies** — audit with `aws events describe-event-bus` regularly.
- **Never log raw events** to CWL if events contain PII — filter the catch-all pattern or obfuscate at target.

### Reliability

- **Archive all production buses** with at least 30 days retention — enables replay for incident recovery.
- **Test replay periodically** — know before an incident that replay works correctly and targets are idempotent.
- **Alarm on `InvocationsFailedToBeSentToDLQ`** — treat as P1; means events are silently dropped.
- **Alarm on `ThrottledRules`** — indicates you need a concurrency limit increase.
- **Monitor DLQ depth** — DLQ growth means events are failing and piling up.

### Cost Optimisation

- **Custom bus events vs default bus** — custom bus events cost $1/million. Default bus receives free AWS service events but custom events sent to it also cost $1/million.
- **Disable event logging** (catch-all rule) in non-production after debugging sessions — CWL ingestion and storage cost adds up quickly.
- **Filter archives** — archive only the subset of events you need to replay, not everything.
- **Use Scheduler over Rules for cron** — if you have many (>50) fixed schedules, EventBridge Scheduler is more scalable and avoids the 300 rules/bus limit.

---

## 27. This Module — Design Notes

### Architecture Decisions

| Decision | Rationale |
|---|---|
| `for_each` over `count` for all resources | Enables safe add/remove of individual buses, rules, and targets without destroying/recreating unrelated resources |
| Composite key `bus:rule` and `bus:rule:target` | Provides globally unique, human-readable keys across the module; colons are prohibited in names to avoid key collisions |
| `local.bus_name_map` | Abstracts whether a bus is module-managed or the default bus; rules and targets always reference the resolved name |
| `create_lambda_permission` toggle per target | Allows consumers to manage their own `aws_lambda_permission` when this module does not own the Lambda |
| `observability.enabled` master switch | Single toggle to activate or deactivate all observability resources, making it safe to disable in dev/test |
| Default alarms auto-populated | Reduces configuration burden for common alarm patterns; users can override or supplement via `cloudwatch_metric_alarms` |
| `InvocationsFailedToBeSentToDLQ` included in default alarms | This critical silent-drop metric is often missed; the module ensures it is always alarmed when observability is enabled |
| Catch-all rule uses `{"source": [{"prefix": ""}]}` | Matches all events regardless of source, satisfying the EventBridge requirement for non-null patterns |
| Dashboard name truncated at 243 chars with MD5 suffix | CloudWatch dashboard names have a 255-char limit; long bus name combinations are safely handled |

### Module Inputs Quick Reference

| Variable | Purpose |
|---|---|
| `event_buses` | All buses, rules, and targets (nested structure) |
| `archives` | Event archives (separate from bus config for clean separation) |
| `bus_policies` | Resource-based policies for cross-account access |
| `observability` | Master switch + toggles for alarms, logging, dashboard |
| `cloudwatch_metric_alarms` | Additional custom metric alarms (merged with auto-defaults) |
| `dlq_cloudwatch_metric_alarms` | SQS DLQ alarms linked to targets via `target_key` |
| `cloudwatch_metric_anomaly_alarms` | Anomaly detection alarms for dynamic thresholding |
| `lambda_permission_statement_id_prefix` | Prefix for auto-generated Lambda permission statement IDs |
| `tags` | Tags merged into all taggable resources |

### Module Outputs Quick Reference

| Output | Type | Key Format |
|---|---|---|
| `event_bus_arns` | `map(string)` | `bus_name` |
| `event_bus_names` | `map(string)` | `bus_name` |
| `event_rule_arns` | `map(string)` | `bus_name:rule_name` |
| `event_rule_names` | `map(string)` | `bus_name:rule_name` |
| `target_arns` | `map(string)` | `bus_name:rule_name:target_id` |
| `lambda_permission_statement_ids` | `map(string)` | `bus_name:rule_name:target_id` |
| `archive_arns` | `map(string)` | `archive_name` |
| `bus_policy_ids` | `map(string)` | `bus_name` |
| `cloudwatch_metric_alarm_arns` | `map(string)` | alarm key |
| `dlq_cloudwatch_metric_alarm_arns` | `map(string)` | alarm key |
| `anomaly_alarm_arns` | `map(string)` | alarm key |
| `dashboard_name` | `string` | — |
| `event_log_group_arns` | `map(string)` | `bus_name` |

### Validation Guards Built Into the Module

- Bus names unique and non-empty; no colons; valid characters only
- Rule names unique per bus; no colons; exactly one of `event_pattern` / `schedule_expression`
- `event_pattern` must be valid JSON when set
- `schedule_expression` must match `rate(...)` or `cron(...)`; only on default bus
- Target IDs unique per rule; no colons; non-empty
- `input`, `input_path`, `input_transformer` mutually exclusive per target
- Target ARNs start with `arn:`; `role_arn` format validated; `dead_letter_arn` format validated
- `retry_policy` values within allowed ranges (60–86400 and 0–185)
- `lambda_permission_statement_id` format: 1-100 chars, alphanumeric + `-_`
- Observability: SNS ARNs validated; `event_log_retention_in_days` must be a valid CWL retention value; KMS ARN format validated
- `cloudwatch_metric_alarms.comparison_operator` must be a valid CW operator
- `cloudwatch_metric_alarms.rule_key` must follow `bus_name:rule_name` format
- Anomaly alarm `band_width > 0` and `evaluation_periods >= 1`

---

## References

- [AWS EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS EventBridge API Reference](https://docs.aws.amazon.com/eventbridge/latest/APIReference/)
- [EventBridge event patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
- [EventBridge Pipes](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes.html)
- [EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/)
- [EventBridge Schema Registry](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schema.html)
- [Terraform: aws_cloudwatch_event_bus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus)
- [Terraform: aws_cloudwatch_event_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule)
- [Terraform: aws_cloudwatch_event_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target)
- [Terraform: aws_cloudwatch_event_archive](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_archive)
- [Terraform: aws_pipes_pipe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/pipes_pipe)
- [Terraform: aws_scheduler_schedule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule)
- [Terraform: aws_schemas_discoverer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/schemas_discoverer)
- [CloudWatch EventBridge metrics](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring.html)
- [EventBridge quotas](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-quota.html)
