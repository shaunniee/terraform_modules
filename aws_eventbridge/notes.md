# AWS EventBridge — Complete Engineering Reference Notes
> For use inside Terraform modules. Covers Event Buses, Rules, Pipes, Scheduler, Schema Registry, Archive/Replay, and every integration pattern with full Terraform references.

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Event Buses](#2-event-buses)
3. [Event Structure](#3-event-structure)
4. [Rules & Event Patterns](#4-rules--event-patterns)
5. [Targets](#5-targets)
6. [Input Transformation](#6-input-transformation)
7. [Scheduling (EventBridge Scheduler)](#7-scheduling-eventbridge-scheduler)
8. [EventBridge Pipes](#8-eventbridge-pipes)
9. [Schema Registry & Discovery](#9-schema-registry--discovery)
10. [Archive & Replay](#10-archive--replay)
11. [Cross-Account & Cross-Region Events](#11-cross-account--cross-region-events)
12. [API Destinations](#12-api-destinations)
13. [Dead Letter Queues & Error Handling](#13-dead-letter-queues--error-handling)
14. [IAM & Permissions](#14-iam--permissions)
15. [Observability — Metrics & Alarms](#15-observability--metrics--alarms)
16. [Observability — Logging](#16-observability--logging)
17. [Observability — X-Ray](#17-observability--x-ray)
18. [Debugging & Troubleshooting](#18-debugging--troubleshooting)
19. [Cost Model](#19-cost-model)
20. [Limits & Quotas](#20-limits--quotas)
21. [Best Practices & Patterns](#21-best-practices--patterns)
22. [Terraform Full Resource Reference](#22-terraform-full-resource-reference)

---

## 1. Core Concepts

### What EventBridge Is
- **Serverless event bus** — routes events between AWS services, SaaS apps, and custom applications.
- Near-real-time event delivery (typically <1 second; SLA <500ms for most targets).
- Fully managed, scales automatically, no infrastructure to manage.
- Decouples producers from consumers — producers don't know about consumers.
- Events are JSON objects up to **256 KB**.
- At-least-once delivery with retry logic.

### EventBridge Components

| Component | Description |
|---|---|
| **Event Bus** | Named channel that receives events. Events are matched against rules. |
| **Rule** | Pattern matcher + target router. Matches events and routes to 1-5 targets. |
| **Event** | JSON payload. Always has a standard envelope with detail fields. |
| **Target** | Destination for matched events (Lambda, SQS, SNS, Step Functions, etc.). |
| **Schema Registry** | Stores and discovers event schemas. Enables code binding generation. |
| **Archive** | Stores all or filtered events for replay. |
| **Pipes** | Point-to-point event integration with optional filtering + enrichment. |
| **Scheduler** | Create one-time or recurring scheduled tasks (replaces CloudWatch Events cron). |
| **API Destination** | Send events to any HTTP endpoint (SaaS, webhooks). |
| **Connection** | Auth config (API key, OAuth, Basic) for API Destinations. |

### Three Bus Types

| Bus | Description | Use Case |
|---|---|---|
| **Default** | `default` — receives all AWS service events | AWS service integrations |
| **Custom** | User-created named buses | Application domain events |
| **Partner** | SaaS partner events (Zendesk, Datadog, etc.) | SaaS integrations |

### Event Flow
```
Producer (AWS Service / App / SaaS Partner)
  └─→ Event Bus
        └─→ Rule (pattern matching)
              ├─→ Target 1 (Lambda)
              ├─→ Target 2 (SQS)
              └─→ Target 3 (Step Functions)
```

### EventBridge vs SNS vs SQS

| Feature | EventBridge | SNS | SQS |
|---|---|---|---|
| Pattern matching | ✅ Rich JSON patterns | ❌ Simple attribute filters | ❌ |
| Max targets per event | 5 per rule (unlimited rules) | Unlimited subscribers | 1 consumer at a time |
| Schema registry | ✅ | ❌ | ❌ |
| Archive & replay | ✅ | ❌ | ❌ |
| Cross-account | ✅ Native | ✅ | Limited |
| SaaS integrations | ✅ Native | ❌ | ❌ |
| Ordering | ❌ | ❌ | ✅ FIFO |
| Deduplication | ❌ | ❌ | ✅ FIFO |
| Batch processing | ❌ | ❌ | ✅ |
| Delivery guarantee | At-least-once | At-least-once | At-least-once |
| Max event/message size | 256 KB | 256 KB | 256 KB |

---

## 2. Event Buses

### Default Event Bus
- Automatically exists in every region.
- Receives events from all AWS services in the account.
- Cannot be deleted.
- Name: `default`

### Custom Event Bus
```hcl
resource "aws_cloudwatch_event_bus" "this" {
  name = "${var.app_name}-${var.environment}"
  # name cannot be "default" — reserved
  # name cannot start with "aws." — reserved for AWS

  tags = var.tags
}

output "event_bus_arn" {
  value = aws_cloudwatch_event_bus.this.arn
}
```

### Event Bus Resource Policy (cross-account publishing)
```hcl
resource "aws_cloudwatch_event_bus_policy" "this" {
  event_bus_name = aws_cloudwatch_event_bus.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow specific account to publish
        Sid    = "AllowAccountPublish"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.producer_account_id}:root" }
        Action   = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.this.arn
      },
      {
        # Allow entire AWS organization to publish
        Sid    = "AllowOrgPublish"
        Effect = "Allow"
        Principal = { AWS = "*" }
        Action   = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.this.arn
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = var.organization_id
          }
        }
      }
    ]
  })
}
```

### Partner Event Bus (SaaS)
```hcl
# Partner event buses are created by accepting a partner invite
# Terraform resource for reading partner event source:
data "aws_cloudwatch_event_source" "zendesk" {
  name_prefix = "aws.partner/zendesk.com"
}

resource "aws_cloudwatch_event_bus" "partner" {
  name              = data.aws_cloudwatch_event_source.zendesk.name
  event_source_name = data.aws_cloudwatch_event_source.zendesk.name
}
```

---

## 3. Event Structure

### Standard Event Envelope
Every EventBridge event has this structure:
```json
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "source": "com.myapp.orders",
  "account": "123456789012",
  "time": "2024-06-01T12:00:00Z",
  "region": "us-east-1",
  "resources": [
    "arn:aws:dynamodb:us-east-1:123456789012:table/orders"
  ],
  "detail-type": "OrderPlaced",
  "detail": {
    "orderId": "ORD-789",
    "userId": "USER-123",
    "total": 99.99,
    "items": [
      {"productId": "PROD-456", "quantity": 2}
    ],
    "status": "PLACED"
  }
}
```

### Key Fields

| Field | Max Size | Description |
|---|---|---|
| `version` | — | Always `"0"` |
| `id` | — | UUID; auto-generated by EventBridge |
| `source` | 256 chars | Event source identifier. Custom: use reverse domain like `com.myapp.service` |
| `detail-type` | 128 chars | Human-readable event type. Use `PascalCase` convention |
| `detail` | ~256 KB total | Event payload (arbitrary JSON) |
| `time` | — | ISO 8601. Auto-set to `PutEvents` time if omitted |
| `resources` | — | List of ARNs of resources related to the event |
| `account` | — | Auto-populated from caller identity |
| `region` | — | Auto-populated from endpoint |

### Publishing Custom Events (Python)
```python
import boto3
import json
from datetime import datetime, timezone

client = boto3.client("events")

def publish_event(event_bus_name, source, detail_type, detail):
    response = client.put_events(
        Entries=[
            {
                "EventBusName": event_bus_name,
                "Source": source,
                "DetailType": detail_type,
                "Detail": json.dumps(detail),
                "Time": datetime.now(timezone.utc),
                "Resources": [],  # optional ARNs
            }
        ]
    )

    failed = response.get("FailedEntryCount", 0)
    if failed > 0:
        for entry in response["Entries"]:
            if "ErrorCode" in entry:
                raise Exception(f"Failed: {entry['ErrorCode']}: {entry['ErrorMessage']}")

    return response["Entries"][0]["EventId"]

# Batch (up to 10 events per PutEvents call)
def publish_events_batch(event_bus_name, events):
    entries = [
        {
            "EventBusName": event_bus_name,
            "Source": e["source"],
            "DetailType": e["detail_type"],
            "Detail": json.dumps(e["detail"]),
        }
        for e in events
    ]

    # Process in batches of 10
    for i in range(0, len(entries), 10):
        batch = entries[i:i+10]
        response = client.put_events(Entries=batch)
        # Handle FailedEntryCount...
```

### Naming Conventions
- `source`: reverse domain notation — `com.mycompany.orders`, `com.mycompany.users`
- `detail-type`: PascalCase noun phrase — `OrderPlaced`, `UserCreated`, `PaymentFailed`
- AWS services use: `source = "aws.s3"`, `detail-type = "Object Created"`

---

## 4. Rules & Event Patterns

### Rule Basics
- Rules live on an event bus and are evaluated against every event.
- A rule matches or doesn't match — no partial matches.
- Multiple rules can match the same event (fanout).
- Up to 5 targets per rule.
- Max 300 rules per event bus (soft limit, adjustable).

### Event Pattern Matching Logic
- **All listed fields must match** (implicit AND).
- **Array values are OR** — any value in the array matches.
- Missing fields in the pattern = match anything (wildcard).
- Matching is **case-sensitive**.

```hcl
resource "aws_cloudwatch_event_rule" "this" {
  name           = "${var.app_name}-order-placed"
  description    = "Matches OrderPlaced events"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  state          = "ENABLED"  # "ENABLED" or "DISABLED"

  event_pattern = jsonencode({
    source      = ["com.myapp.orders"]
    detail-type = ["OrderPlaced"]
    detail = {
      status = ["PLACED", "CONFIRMED"]
      total  = [{ numeric = [">", 100] }]
    }
  })

  tags = var.tags
}
```

### Pattern Matching Rules

#### Exact Match
```json
{ "source": ["com.myapp.orders"] }
```

#### Prefix Match
```json
{ "source": [{ "prefix": "com.myapp" }] }
```

#### Suffix Match
```json
{ "detail": { "filename": [{ "suffix": ".csv" }] } }
```

#### Anything-but (exclusion)
```json
{ "detail": { "status": [{ "anything-but": ["CANCELLED", "FAILED"] }] } }
```

#### Numeric Matching
```json
{ "detail": { "total": [{ "numeric": [">", 0, "<=", 1000] }] } }
{ "detail": { "age":   [{ "numeric": ["=", 18] }] } }
{ "detail": { "score": [{ "numeric": [">=", 50, "<", 100] }] } }
```

#### Exists / Does Not Exist
```json
{ "detail": { "errorCode": [{ "exists": true }] } }
{ "detail": { "optional_field": [{ "exists": false }] } }
```

#### IP Address CIDR Match
```json
{ "detail": { "sourceIp": [{ "cidr": "10.0.0.0/8" }] } }
```

#### Wildcard String Match
```json
{ "detail": { "eventName": [{ "wildcard": "s3:Object*" }] } }
```

#### Equals-ignore-case
```json
{ "detail": { "status": [{ "equals-ignore-case": "active" }] } }
```

#### Combined (AND within object, OR within array)
```json
{
  "source": ["com.myapp.orders"],
  "detail-type": ["OrderPlaced", "OrderUpdated"],
  "detail": {
    "status": [{ "anything-but": "CANCELLED" }],
    "total": [{ "numeric": [">", 0] }],
    "region": [{ "prefix": "us-" }]
  }
}
```

### AWS Service Event Patterns (default bus)

#### S3 Event
```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": { "name": ["my-bucket"] },
    "object": { "key": [{ "prefix": "uploads/" }] }
  }
}
```

#### EC2 State Change
```json
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {
    "state": ["stopped", "terminated"]
  }
}
```

#### CodePipeline State Change
```json
{
  "source": ["aws.codepipeline"],
  "detail-type": ["CodePipeline Pipeline Execution State Change"],
  "detail": {
    "state": ["FAILED"],
    "pipeline": ["my-pipeline"]
  }
}
```

#### ECS Task State Change
```json
{
  "source": ["aws.ecs"],
  "detail-type": ["ECS Task State Change"],
  "detail": {
    "lastStatus": ["STOPPED"],
    "stoppedReason": [{ "prefix": "Essential container" }]
  }
}
```

#### RDS Event
```json
{
  "source": ["aws.rds"],
  "detail-type": ["RDS DB Instance Event"],
  "detail": {
    "EventCategories": ["failure", "failover"]
  }
}
```

#### Health Dashboard (AWS Health)
```json
{
  "source": ["aws.health"],
  "detail-type": ["AWS Health Event"],
  "detail": {
    "service": ["EC2"],
    "eventTypeCategory": ["issue"]
  }
}
```

#### GuardDuty Finding
```json
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "severity": [{ "numeric": [">=", 7] }],
    "type": [{ "prefix": "UnauthorizedAccess" }]
  }
}
```

---

## 5. Targets

### Target Overview

| Target | Type | Notes |
|---|---|---|
| **Lambda** | Function | Most common. Async invocation. |
| **SQS** | Queue / FIFO Queue | FIFO requires `MessageGroupId` |
| **SNS** | Topic | Fan-out |
| **Step Functions** | State Machine | Start execution |
| **Kinesis Data Streams** | Stream | Requires `PartitionKey` |
| **Kinesis Firehose** | Delivery Stream | Direct to S3/Redshift/etc. |
| **DynamoDB** | (via API Destination or Lambda) | No native direct target |
| **EventBridge Bus** | Another event bus | Cross-account/region routing |
| **API Gateway** | REST API stage | HTTP endpoint |
| **API Destination** | HTTP endpoint | External SaaS/webhooks |
| **CloudWatch Log Group** | Log Group | Event storage/debugging |
| **ECS Task** | ECS Cluster | Run task on schedule/event |
| **CodeBuild** | Project | Start build |
| **CodePipeline** | Pipeline | Start pipeline |
| **Batch** | Job Queue | Submit job |
| **SSM Run Command** | EC2 instances | Run commands |
| **SSM Automation** | Runbook | Automation workflow |
| **SageMaker Pipeline** | ML pipeline | Start run |
| **Redshift** | Data API | SQL statement |
| **Inspector** | Assessment | Start assessment |

### Lambda Target
```hcl
resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "lambda-target"
  arn            = aws_lambda_function.processor.arn

  # Optional: retry policy
  retry_policy {
    maximum_event_age_in_seconds = 3600   # max 86400 (24 hrs)
    maximum_retry_attempts       = 3      # max 185
  }

  # Optional: DLQ
  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}
```

### SQS Target
```hcl
resource "aws_cloudwatch_event_target" "sqs" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "sqs-target"
  arn            = aws_sqs_queue.this.arn

  # SQS FIFO requires message group ID
  sqs_target {
    message_group_id = "order-events"  # only for FIFO queues
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

# SQS resource-based policy to allow EventBridge
resource "aws_sqs_queue_policy" "eventbridge" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgeSend"
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.this.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.this.arn }
      }
    }]
  })
}
```

### SNS Target
```hcl
resource "aws_cloudwatch_event_target" "sns" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "sns-target"
  arn            = aws_sns_topic.this.arn
}

resource "aws_sns_topic_policy" "eventbridge" {
  arn = aws_sns_topic.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgePublish"
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.this.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.this.arn }
      }
    }]
  })
}
```

### Step Functions Target
```hcl
resource "aws_iam_role" "eventbridge_sfn" {
  name = "${var.app_name}-eventbridge-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  role = aws_iam_role.eventbridge_sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.this.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "sfn" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "sfn-target"
  arn            = aws_sfn_state_machine.this.arn
  role_arn       = aws_iam_role.eventbridge_sfn.arn

  # Input transformation to map event fields to SFN input
  input_transformer {
    input_paths = {
      orderId = "$.detail.orderId"
      userId  = "$.detail.userId"
    }
    input_template = jsonencode({
      orderId = "<orderId>"
      userId  = "<userId>"
      source  = "eventbridge"
    })
  }
}
```

### EventBridge Bus Target (cross-bus routing)
```hcl
resource "aws_cloudwatch_event_target" "cross_bus" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "cross-bus-target"
  arn            = "arn:aws:events:us-east-1:${var.target_account_id}:event-bus/target-bus"
  role_arn       = aws_iam_role.eventbridge_cross_bus.arn
}
```

### Kinesis Target
```hcl
resource "aws_cloudwatch_event_target" "kinesis" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "kinesis-target"
  arn            = aws_kinesis_stream.this.arn
  role_arn       = aws_iam_role.eventbridge_kinesis.arn

  kinesis_target {
    partition_key_path = "$.detail.orderId"  # JSONPath for partition key
  }
}
```

### ECS Task Target (run task on event)
```hcl
resource "aws_cloudwatch_event_target" "ecs" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "ecs-target"
  arn            = aws_ecs_cluster.this.arn
  role_arn       = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.this.arn
    task_count          = 1
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [aws_security_group.ecs.id]
      assign_public_ip = false
    }

    # Pass container overrides via input transformer
    # container_overrides in input_transformer
  }

  input_transformer {
    input_paths = {
      orderId = "$.detail.orderId"
    }
    input_template = jsonencode({
      containerOverrides = [{
        name    = "my-container"
        command = ["process", "<orderId>"]
        environment = [{
          name  = "ORDER_ID"
          value = "<orderId>"
        }]
      }]
    })
  }
}
```

### CloudWatch Log Group Target (for debugging/storage)
```hcl
resource "aws_cloudwatch_log_group" "event_log" {
  name              = "/aws/events/${var.app_name}"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge" {
  policy_name = "eventbridge-${var.app_name}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"] }
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.event_log.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_target" "logs" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "cloudwatch-logs"
  arn            = aws_cloudwatch_log_group.event_log.arn
}
```

---

## 6. Input Transformation

### Three Modes

| Mode | Description | Terraform Attribute |
|---|---|---|
| **Matched Event** | Send full original event (default) | No `input*` attributes |
| **Constant JSON** | Send static JSON string | `input = jsonencode({...})` |
| **Input Transformer** | Extract fields + build new JSON | `input_transformer {}` block |

### Constant Input
```hcl
resource "aws_cloudwatch_event_target" "this" {
  # ...
  input = jsonencode({
    action  = "process"
    version = "v2"
  })
}
```

### Input Transformer
```hcl
resource "aws_cloudwatch_event_target" "this" {
  # ...
  input_transformer {
    # Step 1: Extract fields using JSONPath
    input_paths = {
      orderId   = "$.detail.orderId"
      userId    = "$.detail.userId"
      total     = "$.detail.total"
      eventTime = "$.time"
      source    = "$.source"
      region    = "$.region"
      account   = "$.account"
    }

    # Step 2: Build new JSON using <variable> placeholders
    # Must be valid JSON — use jsonencode for safety
    input_template = <<EOF
{
  "order_id": "<orderId>",
  "user_id": "<userId>",
  "amount": <total>,
  "processed_at": "<eventTime>",
  "event_source": "<source>",
  "aws_region": "<region>"
}
EOF
  }
}
```

### Input Path Rules
- Uses **JSONPath** syntax: `$.field`, `$.nested.field`, `$.array[0]`
- Variable names: alphanumeric + underscore, must start with letter.
- Up to 100 input paths per rule.
- `<aws.events.event.ingestion-time>` — special variable for ingestion timestamp.
- `<aws.events.event>` — entire event as JSON string.

### Common JSONPath Extractions
```json
{
  "id":          "$.id",
  "source":      "$.source",
  "detailType":  "$.detail-type",
  "region":      "$.region",
  "account":     "$.account",
  "time":        "$.time",
  "resources":   "$.resources[0]",
  "orderId":     "$.detail.orderId",
  "nestedField": "$.detail.nested.field"
}
```

---

## 7. Scheduling (EventBridge Scheduler)

### Scheduler vs CloudWatch Events Rules

| Feature | EventBridge Scheduler | CloudWatch Events Rules (cron) |
|---|---|---|
| One-time schedules | ✅ | ❌ |
| Flexible time windows | ✅ | ❌ |
| Schedule groups | ✅ | ❌ |
| Timezone support | ✅ | ❌ (UTC only) |
| Target count | 1 per schedule | 5 per rule |
| Max schedules | 1M+ | 300 per bus |
| Recommendation | Use for new work | Legacy |

### Schedule Expressions

| Type | Format | Example |
|---|---|---|
| Rate | `rate(value unit)` | `rate(5 minutes)`, `rate(1 hour)`, `rate(7 days)` |
| Cron | `cron(min hr dom mon dow yr)` | `cron(0 12 * * ? *)` = noon UTC daily |
| One-time | ISO 8601 datetime | `2024-12-31T23:59:00` |

### Cron Expression Reference
```
cron(minute hour day-of-month month day-of-week year)

minute:       0-59, * (any), , (list), - (range), / (increment)
hour:         0-23
day-of-month: 1-31, * (any), ? (no spec), L (last), W (weekday nearest)
month:        1-12 or JAN-DEC
day-of-week:  1-7 or SUN-SAT, ? (no spec), L (last X of month), # (nth weekday)
year:         1970-2199, * (any)

Note: day-of-month AND day-of-week cannot both be non-"?" at the same time

Examples:
cron(0 9 * * MON-FRI *)   → 9 AM UTC every weekday
cron(0 0 1 * ? *)          → midnight on the 1st of every month
cron(0/15 * * * ? *)       → every 15 minutes
cron(0 17 ? * FRI *)       → 5 PM UTC every Friday
cron(0 8 ? * 2#1 *)        → 8 AM UTC first Monday of month
cron(0 0 L * ? *)           → midnight on last day of month
```

### Terraform: EventBridge Scheduler
```hcl
resource "aws_scheduler_schedule_group" "this" {
  name = "${var.app_name}-${var.environment}"
  tags = var.tags
}

# Recurring schedule
resource "aws_scheduler_schedule" "recurring" {
  name       = "${var.app_name}-daily-report"
  group_name = aws_scheduler_schedule_group.this.name
  description = "Daily report generation"

  schedule_expression          = "cron(0 8 * * ? *)"   # 8 AM UTC daily
  schedule_expression_timezone = "America/New_York"      # timezone-aware

  state = "ENABLED"  # "ENABLED" or "DISABLED"

  # Flexible time window — invoke within window to smooth traffic
  flexible_time_window {
    mode                      = "FLEXIBLE"  # "OFF" or "FLEXIBLE"
    maximum_window_in_minutes = 15          # invoke within 15min of scheduled time
  }

  # OR: exact time window (no flexibility)
  # flexible_time_window { mode = "OFF" }

  target {
    arn      = aws_lambda_function.report.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      reportType = "daily"
      format     = "pdf"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }

    dead_letter_config {
      arn = aws_sqs_queue.dlq.arn
    }
  }
}

# One-time schedule
resource "aws_scheduler_schedule" "one_time" {
  name       = "${var.app_name}-migration-job"
  group_name = aws_scheduler_schedule_group.this.name

  schedule_expression = "at(2024-12-31T23:00:00)"   # one-time at specific time

  flexible_time_window { mode = "OFF" }

  # Auto-delete after completion
  # (no built-in auto-delete; manage with lifecycle or Lambda)

  target {
    arn      = aws_sfn_state_machine.migration.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({ migrationVersion = "v3" })
  }
}
```

### Scheduler IAM Role
```hcl
resource "aws_iam_role" "scheduler" {
  name = "${var.app_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.report.arn,
          "${aws_lambda_function.report.arn}:*",  # for aliases/versions
        ]
      },
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.migration.arn
      },
      # For DLQ:
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}
```

### Scheduler Targets (supports more than EventBridge Rules)
- Lambda, Step Functions, SQS, SNS, ECS Task, Kinesis, Firehose
- CodeBuild, CodePipeline, Inspector, Glue, SageMaker Pipeline
- EventBridge event bus (send event on schedule)
- **Universal targets** via `arn:aws:scheduler:::aws-sdk:*` — call any AWS API action on schedule

```hcl
# Universal target — call any AWS SDK action
resource "aws_scheduler_schedule" "rds_stop" {
  name = "stop-rds-dev-nights"

  schedule_expression          = "cron(0 22 * * ? *)"   # 10 PM UTC
  schedule_expression_timezone = "UTC"

  flexible_time_window { mode = "OFF" }

  target {
    # Universal target format: arn:aws:scheduler:::aws-sdk:service:action
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      DbInstanceIdentifier = var.rds_instance_id
    })
  }
}
```

---

## 8. EventBridge Pipes

### What Pipes Are
- **Point-to-point** integration between a source and a target.
- Optional **filtering**, **enrichment** (Lambda/API GW/Step Functions), and **transformation**.
- Managed polling from sources (SQS, Kinesis, DynamoDB Streams, MSK, Kafka).
- Simplifies the Lambda-as-glue pattern.

### Pipe Architecture
```
Source (poll-based or push)
  └─→ [Filter] (optional — reduce events before enrichment)
        └─→ [Enrichment] (optional — Lambda/APIGW/SFN/EventBridge)
              └─→ [Target Transformation] (optional)
                    └─→ Target
```

### Supported Sources

| Source | Notes |
|---|---|
| SQS | Polls the queue |
| Kinesis Data Streams | Polls shards |
| DynamoDB Streams | Polls stream |
| MSK (Amazon Managed Kafka) | Polls topics |
| Self-managed Kafka | Polls topics |
| Amazon MQ (RabbitMQ / ActiveMQ) | Polls queues/topics |

### Supported Targets (same as EventBridge Rules + more)
Lambda, Step Functions, SQS, SNS, Kinesis, Firehose, API Gateway, API Destination, EventBridge bus, CloudWatch Logs, ECS Task, Redshift, SageMaker Pipeline

### Terraform: EventBridge Pipe
```hcl
resource "aws_pipes_pipe" "this" {
  name        = "${var.app_name}-pipe"
  description = "SQS to Lambda with enrichment"
  role_arn    = aws_iam_role.pipe.arn

  source = aws_sqs_queue.source.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 10
      maximum_batching_window_in_seconds = 30
    }

    # Filter before enrichment (reduce Lambda invocations)
    filter_criteria {
      filter {
        pattern = jsonencode({
          body = {
            eventType = ["ORDER_PLACED"]
            amount    = [{ numeric = [">", 0] }]
          }
        })
      }
    }
  }

  # Enrichment (optional) — call Lambda to add data before target
  enrichment = aws_lambda_function.enricher.arn

  enrichment_parameters {
    input_template = jsonencode({
      orderId = "<$.body.orderId>"
      userId  = "<$.body.userId>"
    })
  }

  target = aws_sfn_state_machine.processor.arn

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"  # or "REQUEST_RESPONSE"
    }

    input_template = jsonencode({
      orderId     = "<$.body.orderId>"
      enrichedData = "<$.enrichmentResult>"
    })
  }

  tags = var.tags
}

resource "aws_iam_role" "pipe" {
  name = "${var.app_name}-pipe-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pipes.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "pipe" {
  role = aws_iam_role.pipe.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.source.arn
      },
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.enricher.arn
      },
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.processor.arn
      }
    ]
  })
}
```

### Pipe with Kinesis Source
```hcl
resource "aws_pipes_pipe" "kinesis" {
  name     = "${var.app_name}-kinesis-pipe"
  role_arn = aws_iam_role.pipe.arn

  source = aws_kinesis_stream.this.arn

  source_parameters {
    kinesis_stream_parameters {
      starting_position                   = "LATEST"  # or "TRIM_HORIZON", "AT_TIMESTAMP"
      batch_size                          = 100
      maximum_batching_window_in_seconds  = 30
      maximum_retry_attempts              = 3
      bisect_batch_on_function_error      = true
      maximum_record_age_in_seconds       = 3600
      parallelization_factor              = 5

      dead_letter_config {
        arn = aws_sqs_queue.dlq.arn
      }
    }
  }

  target = aws_lambda_function.processor.arn
}
```

---

## 9. Schema Registry & Discovery

### What Schema Registry Provides
- Stores event schemas in **OpenAPI 3.0** or **JSON Schema Draft4** format.
- **Schema discovery**: automatically discovers schemas from events on the event bus.
- **Code binding generation**: generate code (Python, Java, TypeScript, Go) for event types.
- Schemas for AWS services pre-built in the `aws.events` registry.

### Enable Schema Discovery
```hcl
resource "aws_schemas_discoverer" "this" {
  source_arn  = aws_cloudwatch_event_bus.this.arn
  description = "Auto-discover schemas from ${var.app_name} bus"
  cross_account = false  # true = discover from cross-account events too
  tags        = var.tags
}
```

### Create Schema Manually
```hcl
resource "aws_schemas_registry" "this" {
  name        = "${var.app_name}-registry"
  description = "Event schemas for ${var.app_name}"
  tags        = var.tags
}

resource "aws_schemas_schema" "order_placed" {
  name          = "com.myapp.orders@OrderPlaced"
  registry_name = aws_schemas_registry.this.name
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
          required = ["detail-type", "resources", "detail", "id", "source", "time", "region", "version", "account"]
          "x-amazon-events-detail-type"  = "OrderPlaced"
          "x-amazon-events-source"       = "com.myapp.orders"
          properties = {
            detail     = { "$ref" = "#/components/schemas/OrderPlaced" }
            account    = { type = "string" }
            "detail-type" = { type = "string" }
            id         = { type = "string" }
            region     = { type = "string" }
            resources  = { type = "array", items = { type = "string" } }
            source     = { type = "string" }
            time       = { type = "string", format = "date-time" }
            version    = { type = "string" }
          }
        }
        OrderPlaced = {
          type = "object"
          required = ["orderId", "userId", "total"]
          properties = {
            orderId = { type = "string" }
            userId  = { type = "string" }
            total   = { type = "number" }
            status  = { type = "string", enum = ["PLACED", "CONFIRMED"] }
            items   = { type = "array", items = { "$ref" = "#/components/schemas/OrderItem" } }
          }
        }
        OrderItem = {
          type = "object"
          properties = {
            productId = { type = "string" }
            quantity  = { type = "integer", minimum = 1 }
          }
        }
      }
    }
  })
}
```

---

## 10. Archive & Replay

### Archive
- Store events that match a pattern on an event bus.
- Infinite or configurable retention.
- Stored events can be replayed to any event bus.
- Use for: disaster recovery, debugging, re-processing after bug fixes.

```hcl
resource "aws_cloudwatch_event_archive" "this" {
  name             = "${var.app_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  description      = "Archive all events from ${var.app_name} bus"
  retention_days   = 30  # 0 = infinite retention

  # Optional: filter which events to archive
  event_pattern = jsonencode({
    source = ["com.myapp.orders"]
  })
}
```

### Replay
```hcl
# Replay archived events (typically via CLI or console)
# No direct Terraform resource for creating a replay (one-time operation)
# CLI:
# aws events start-replay \
#   --replay-name "replay-2024-06-01" \
#   --event-source-arn arn:aws:events:us-east-1:123456789012:archive/my-archive \
#   --event-start-time "2024-06-01T00:00:00Z" \
#   --event-end-time "2024-06-01T23:59:59Z" \
#   --destination '{
#     "Arn": "arn:aws:events:us-east-1:123456789012:event-bus/my-bus",
#     "FilterArns": ["arn:aws:events:us-east-1:123456789012:rule/my-bus/my-rule"]
#   }'
```

### Replay Considerations
- Replayed events have an additional field: `"replay-name"` in the event.
- Replay preserves original event `time` field.
- Rules can filter out replay events using: `{ "replay-name": [{ "exists": false }] }`.
- Replay throughput: up to 10,000 events/second.

---

## 11. Cross-Account & Cross-Region Events

### Cross-Account Pattern

**Producer Account** → **Consumer Account Event Bus** → **Rules** → **Targets**

```hcl
# ── Consumer Account ──────────────────────────────────────
# 1. Create receiving event bus
resource "aws_cloudwatch_event_bus" "receiver" {
  name = "cross-account-receiver"
}

# 2. Allow producer account to publish
resource "aws_cloudwatch_event_bus_policy" "allow_producer" {
  event_bus_name = aws_cloudwatch_event_bus.receiver.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowProducerAccount"
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.producer_account_id}:root" }
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.receiver.arn
    }]
  })
}

# 3. Create rule + target in consumer account
resource "aws_cloudwatch_event_rule" "cross_account" {
  event_bus_name = aws_cloudwatch_event_bus.receiver.name
  event_pattern  = jsonencode({ source = ["com.myapp.orders"] })
}

resource "aws_cloudwatch_event_target" "cross_account" {
  rule           = aws_cloudwatch_event_rule.cross_account.name
  event_bus_name = aws_cloudwatch_event_bus.receiver.name
  arn            = aws_lambda_function.processor.arn
}

# ── Producer Account ──────────────────────────────────────
# 4. Create rule to forward events to consumer bus
resource "aws_cloudwatch_event_rule" "forward" {
  event_bus_name = "default"
  event_pattern  = jsonencode({ source = ["com.myapp.orders"] })
}

resource "aws_iam_role" "eventbridge_cross_account" {
  name = "EventBridgeCrossAccountRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_cross_account" {
  role = aws_iam_role.eventbridge_cross_account.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = "arn:aws:events:us-east-1:${var.consumer_account_id}:event-bus/cross-account-receiver"
    }]
  })
}

resource "aws_cloudwatch_event_target" "cross_account_forward" {
  rule      = aws_cloudwatch_event_rule.forward.name
  target_id = "forward-to-consumer"
  arn       = "arn:aws:events:us-east-1:${var.consumer_account_id}:event-bus/cross-account-receiver"
  role_arn  = aws_iam_role.eventbridge_cross_account.arn
}
```

### Cross-Region Pattern
- Same as cross-account but targeting a bus in a different region.
- No special bus policy needed for same-account cross-region.
- Requires IAM role with `events:PutEvents` permission on the target bus.

```hcl
resource "aws_cloudwatch_event_target" "cross_region" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "forward-to-eu"
  arn       = "arn:aws:events:eu-west-1:${data.aws_caller_identity.current.account_id}:event-bus/eu-bus"
  role_arn  = aws_iam_role.eventbridge_cross_region.arn
}
```

---

## 12. API Destinations

### What API Destinations Are
- Send events to any **HTTP/HTTPS endpoint** (SaaS tools, webhooks, third-party APIs).
- Managed auth: API key, OAuth 2.0, Basic auth.
- Rate limiting per destination.
- EventBridge handles retries with backoff.

### Connection (Auth Config)
```hcl
# API Key Auth
resource "aws_cloudwatch_event_connection" "api_key" {
  name               = "${var.app_name}-api-key-connection"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "X-Api-Key"
      value = var.external_api_key  # stored in Secrets Manager by EventBridge
    }
  }
}

# OAuth 2.0
resource "aws_cloudwatch_event_connection" "oauth" {
  name               = "${var.app_name}-oauth-connection"
  authorization_type = "OAUTH_CLIENT_CREDENTIALS"

  auth_parameters {
    oauth {
      authorization_endpoint = "https://auth.example.com/oauth/token"
      http_method            = "POST"

      client_parameters {
        client_id     = var.oauth_client_id
        client_secret = var.oauth_client_secret
      }

      oauth_http_parameters {
        body {
          key             = "grant_type"
          value           = "client_credentials"
          is_value_secret = false
        }
        body {
          key             = "scope"
          value           = "events:write"
          is_value_secret = false
        }
      }
    }
  }
}

# Basic Auth
resource "aws_cloudwatch_event_connection" "basic" {
  name               = "${var.app_name}-basic-connection"
  authorization_type = "BASIC"

  auth_parameters {
    basic {
      username = var.api_username
      password = var.api_password
    }
  }
}
```

### API Destination
```hcl
resource "aws_cloudwatch_event_api_destination" "this" {
  name                             = "${var.app_name}-webhook"
  description                      = "Send events to external webhook"
  invocation_endpoint              = "https://webhook.example.com/events"
  http_method                      = "POST"  # GET, POST, PUT, PATCH, DELETE, HEAD
  connection_arn                   = aws_cloudwatch_event_connection.api_key.arn
  invocation_rate_limit_per_second = 300     # max requests/second to endpoint

}

resource "aws_cloudwatch_event_target" "api_dest" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "api-destination"
  arn            = aws_cloudwatch_event_api_destination.this.arn
  role_arn       = aws_iam_role.eventbridge_api_dest.arn

  # Transform event before sending
  input_transformer {
    input_paths = {
      orderId = "$.detail.orderId"
      total   = "$.detail.total"
    }
    input_template = jsonencode({
      event     = "order.placed"
      order_id  = "<orderId>"
      amount    = "<total>"
    })
  }

  # HTTP parameters added to the request
  http_target {
    path_parameter_values   = []
    query_string_parameters = { version = "v2", env = var.environment }
    header_parameters       = { "X-Source" = "eventbridge" }
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_iam_role" "eventbridge_api_dest" {
  name = "${var.app_name}-api-dest-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_api_dest" {
  role = aws_iam_role.eventbridge_api_dest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudwatch_event_api_destination.this.arn
    }]
  })
}
```

---

## 13. Dead Letter Queues & Error Handling

### Retry Behavior (Rules Targets)
- EventBridge retries failed target invocations.
- Default: retry for **24 hours** with exponential backoff.
- Configurable per target: `maximum_event_age_in_seconds` (60-86400) and `maximum_retry_attempts` (0-185).
- After exhausting retries → event goes to DLQ (if configured) or is dropped.

### DLQ per Target
```hcl
resource "aws_cloudwatch_event_target" "with_dlq" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "lambda-with-dlq"
  arn       = aws_lambda_function.processor.arn

  retry_policy {
    maximum_event_age_in_seconds = 7200  # 2 hours
    maximum_retry_attempts       = 5
  }

  dead_letter_config {
    arn = aws_sqs_queue.event_dlq.arn
  }
}

resource "aws_sqs_queue" "event_dlq" {
  name                       = "${var.app_name}-event-dlq"
  message_retention_seconds  = 1209600  # 14 days
  kms_master_key_id          = aws_kms_key.sqs.id
  tags                       = var.tags
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.event_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgeSendDLQ"
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.event_dlq.arn
    }]
  })
}
```

### DLQ Message Structure
When an event fails, the DLQ message contains:
```json
{
  "version": "1.0",
  "timestamp": "2024-06-01T12:00:00.000Z",
  "requestContext": {
    "requestId": "abc-123",
    "functionArn": "arn:aws:lambda:...",
    "condition": "RetryAttemptsExhausted",
    "approximateInvokeCount": 6
  },
  "requestPayload": {
    "version": "0",
    "source": "com.myapp.orders",
    "detail-type": "OrderPlaced",
    "detail": { "orderId": "ORD-789" }
  },
  "responseContext": {
    "statusCode": 500,
    "executedVersion": "$LATEST",
    "functionError": "Unhandled"
  },
  "responsePayload": { ... }
}
```

### Error Conditions that Trigger Retry
- Lambda returns error or throws exception.
- Lambda throttled (concurrency limit hit).
- Lambda function doesn't exist.
- SQS queue full or throttled.
- Target returns 5xx HTTP error (API Destinations).
- Target is not accessible.

### Error Conditions that DON'T Retry
- Lambda returns 200 but has application error in body.
- Target returns 4xx (except 429 Too Many Requests).
- Invalid event format.
- Permissions error (fix required — retrying won't help).

---

## 14. IAM & Permissions

### EventBridge Service Role (for targets requiring IAM)
Some targets require EventBridge to assume a role:
- Cross-account event bus
- Step Functions
- Kinesis Data Streams
- Kinesis Firehose
- ECS tasks
- API Destinations
- SSM Run Command / Automation

Lambda, SQS, SNS use **resource-based policies** (not role-based).

```hcl
# Generic EventBridge execution role
resource "aws_iam_role" "eventbridge" {
  name = "${var.app_name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge" {
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Step Functions
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = var.sfn_state_machine_arns
      },
      # Kinesis
      {
        Effect   = "Allow"
        Action   = ["kinesis:PutRecord", "kinesis:PutRecords"]
        Resource = var.kinesis_stream_arns
      },
      # Firehose
      {
        Effect   = "Allow"
        Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
        Resource = var.firehose_arns
      },
      # ECS
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = var.ecs_task_definition_arns
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = var.ecs_task_role_arns
        Condition = {
          StringLike = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
    ]
  })
}
```

### Lambda Resource Policy
```hcl
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke-${var.rule_name}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  qualifier     = aws_lambda_alias.live.name  # optional: target alias
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
  # Optionally restrict: source_account = data.aws_caller_identity.current.account_id
}
```

### IAM Policy for PutEvents (producer application)
```hcl
data "aws_iam_policy_document" "put_events" {
  statement {
    effect  = "Allow"
    actions = ["events:PutEvents"]
    resources = [
      aws_cloudwatch_event_bus.this.arn,
      # "arn:aws:events:${var.region}:${data.aws_caller_identity.current.account_id}:event-bus/default"
    ]
  }
}
```

---

## 15. Observability — Metrics & Alarms

### CloudWatch Metrics — EventBridge Rules (namespace: `AWS/Events`)

| Metric | Description | Stat |
|---|---|---|
| `Invocations` | Times a rule matched and invoked targets | Sum |
| `FailedInvocations` | Times a target invocation failed (all retries exhausted) | Sum |
| `ThrottledRules` | Times rules were throttled (account limit) | Sum |
| `MatchedEvents` | Events matched by at least one rule | Sum |
| `TriggeredRules` | Rules triggered (matched + attempted) | Sum |
| `DeadLetterInvocations` | Events sent to DLQ | Sum |

Dimensions: `RuleName`, `EventBusName`

### CloudWatch Metrics — EventBridge Scheduler (namespace: `AWS/Scheduler`)

| Metric | Description |
|---|---|
| `InvocationAttemptCount` | Invocation attempts |
| `InvocationThrottleCount` | Throttled invocations |
| `InvocationDroppedCount` | Dropped invocations |
| `TargetErrorCount` | Target invocation errors |
| `TargetErrorThrottledCount` | Throttled target errors |

### CloudWatch Alarms
```hcl
resource "aws_cloudwatch_metric_alarm" "failed_invocations" {
  alarm_name          = "${var.app_name}-eventbridge-failed-invocations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    RuleName     = aws_cloudwatch_event_rule.this.name
    EventBusName = aws_cloudwatch_event_bus.this.name
  }

  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.app_name}-eventbridge-dlq"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.event_dlq.name }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dead_letter_invocations" {
  alarm_name          = "${var.app_name}-dlq-invocations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeadLetterInvocations"
  namespace           = "AWS/Events"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    RuleName     = aws_cloudwatch_event_rule.this.name
    EventBusName = aws_cloudwatch_event_bus.this.name
  }

  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}
```

### CloudWatch Dashboard
```hcl
resource "aws_cloudwatch_dashboard" "eventbridge" {
  dashboard_name = "${var.app_name}-eventbridge"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title   = "Rule Invocations & Failures"
          period  = 60
          metrics = [
            ["AWS/Events", "Invocations",       "RuleName", var.rule_name, "EventBusName", var.bus_name, { stat = "Sum" }],
            ["AWS/Events", "FailedInvocations", "RuleName", var.rule_name, "EventBusName", var.bus_name, { stat = "Sum", color = "#d62728" }],
            ["AWS/Events", "DeadLetterInvocations", "RuleName", var.rule_name, "EventBusName", var.bus_name, { stat = "Sum", color = "#ff7f0e" }],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Matched Events"
          period  = 60
          metrics = [
            ["AWS/Events", "MatchedEvents", "EventBusName", var.bus_name, { stat = "Sum" }],
          ]
        }
      }
    ]
  })
}
```

---

## 16. Observability — Logging

### Log All Events to CloudWatch (Debugging)
```hcl
# Create a catch-all rule pointing to CloudWatch Logs
resource "aws_cloudwatch_event_rule" "log_all" {
  name           = "${var.app_name}-log-all"
  description    = "Log all events for debugging (disable in production)"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  state          = var.environment == "prod" ? "DISABLED" : "ENABLED"

  event_pattern = jsonencode({ source = [{ "anything-but": [] }] })  # match everything
  # OR simpler: event_pattern = "{}"  — matches all events
}

resource "aws_cloudwatch_event_target" "log_all" {
  rule           = aws_cloudwatch_event_rule.log_all.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "log-all-events"
  arn            = aws_cloudwatch_log_group.event_log.arn
}
```

### CloudWatch Logs Insights Queries
```
# Find all events from a specific source
fields @timestamp, source, `detail-type`, detail
| filter source = "com.myapp.orders"
| sort @timestamp desc
| limit 50

# Count events by type over time
fields @timestamp, `detail-type`
| stats count() as eventCount by `detail-type`, bin(5min)
| sort eventCount desc

# Find events for a specific ID
fields @timestamp, source, `detail-type`, detail.orderId
| filter detail.orderId = "ORD-789"
| sort @timestamp desc

# Event rate per source
stats count() as total by source
| sort total desc

# Failed events (if you log Lambda failures to CW)
fields @timestamp, `detail-type`, detail.errorMessage
| filter detail.errorMessage exists
| sort @timestamp desc
```

### CloudTrail for EventBridge Control Plane
```hcl
# CloudTrail captures: PutRule, DeleteRule, PutTargets, RemoveTargets,
# PutEvents (data event), CreateEventBus, DeleteEventBus
resource "aws_cloudtrail" "eventbridge" {
  # ... standard CloudTrail config

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Data events for PutEvents calls
    data_resource {
      type   = "AWS::Events::EventBus"
      values = [aws_cloudwatch_event_bus.this.arn]
    }
  }
}
```

---

## 17. Observability — X-Ray

### EventBridge + X-Ray
- EventBridge passes trace headers to targets automatically when X-Ray is enabled on the invoking Lambda.
- End-to-end trace: `Lambda (producer) → EventBridge → Lambda (consumer)`.
- EventBridge itself does not create X-Ray segments (unlike API GW).

```python
# Producer Lambda — enable X-Ray, events get trace context propagated
from aws_xray_sdk.core import xray_recorder, patch
patch(["boto3"])

def publish_order_event(order):
    client = boto3.client("events")
    # X-Ray automatically adds trace header to PutEvents call
    client.put_events(Entries=[{
        "EventBusName": os.environ["EVENT_BUS_NAME"],
        "Source": "com.myapp.orders",
        "DetailType": "OrderPlaced",
        "Detail": json.dumps(order),
    }])
```

### EventBridge Pipes X-Ray
- Pipes support X-Ray tracing.

```hcl
resource "aws_pipes_pipe" "this" {
  # ...
  log_configuration {
    cloudwatch_logs_log_destination {
      log_group_arn = aws_cloudwatch_log_group.pipe.arn
    }
    level           = "INFO"    # "OFF", "ERROR", "INFO", "TRACE"
    include_execution_data = ["ALL"]
  }
}
```

---

## 18. Debugging & Troubleshooting

### Common Issues

| Problem | Cause | Resolution |
|---|---|---|
| Events not delivered | Rule pattern doesn't match | Use Event Pattern Tester in console; verify JSON escaping |
| Events delivered but target fails | Target error / permissions | Check target CloudWatch Logs; check IAM |
| Rule triggering but Lambda not invoked | Missing Lambda resource-based policy | Add `aws_lambda_permission` |
| Cross-account events not received | Missing bus resource policy | Add `aws_cloudwatch_event_bus_policy` |
| Events go to DLQ | Target consistently failing | Inspect DLQ message; fix target error |
| Schedule not firing | Wrong cron expression / wrong timezone | Test cron in Scheduler console |
| High latency | Target warm-up / downstream bottleneck | Check target metrics; consider provisioned concurrency |
| Events lost silently | No DLQ configured + retries exhausted | Always configure DLQ on targets |
| API Destination 401/403 | Auth config incorrect | Verify Connection credentials |
| API Destination throttled (429) | `invocation_rate_limit_per_second` too high for endpoint | Reduce rate limit |

### Test Event Pattern (AWS CLI)
```bash
# Test if a pattern matches a specific event
aws events test-event-pattern \
  --event-pattern '{"source":["com.myapp.orders"],"detail-type":["OrderPlaced"]}' \
  --event '{
    "source": "com.myapp.orders",
    "detail-type": "OrderPlaced",
    "detail": {"orderId": "ORD-789", "total": 99.99}
  }'
# Returns: { "Result": true/false }
```

### Send Test Event (AWS CLI)
```bash
aws events put-events \
  --entries '[{
    "EventBusName": "my-event-bus",
    "Source": "com.myapp.orders",
    "DetailType": "OrderPlaced",
    "Detail": "{\"orderId\": \"ORD-TEST-001\", \"total\": 99.99, \"status\": \"PLACED\"}"
  }]'
```

### List Rules and Targets
```bash
# List all rules on a bus
aws events list-rules --event-bus-name my-bus

# List targets for a rule
aws events list-targets-by-rule \
  --rule my-rule \
  --event-bus-name my-bus

# Describe a specific rule
aws events describe-rule \
  --name my-rule \
  --event-bus-name my-bus

# List all event buses
aws events list-event-buses

# Check archive
aws events list-archives
aws events describe-archive --archive-name my-archive
```

### Inspect DLQ Message
```bash
# Receive message from DLQ
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/123456789012/my-event-dlq \
  --max-number-of-messages 1 \
  --attribute-names All

# The message body contains the original event + error context
```

### Common Pattern Mistakes
```json
// ❌ WRONG: String instead of array value
{ "source": "com.myapp.orders" }

// ✅ CORRECT: Array of values (even for single value)
{ "source": ["com.myapp.orders"] }

// ❌ WRONG: No equals sign, just field name
{ "detail": { "status" } }

// ✅ CORRECT: Field = array of valid values
{ "detail": { "status": ["PLACED", "CONFIRMED"] } }

// ❌ WRONG: Nested AND inside array
{ "source": ["com.myapp.orders", "com.myapp.users"] }
// This is actually OR — either source matches (correct behavior)

// ❌ WRONG: Using dot notation for detail-type field name in pattern
{ "detail.orderId": ["ORD-789"] }

// ✅ CORRECT: Nested JSON for nested fields
{ "detail": { "orderId": ["ORD-789"] } }
```

---

## 19. Cost Model

### EventBridge Rules
- **Custom/Partner events**: $1.00 per million events.
- **AWS service events** (default bus): Free.
- **Cross-region/cross-account**: charged in source region.
- Schema discovery: $0.10 per million events ingested for discovery.

### EventBridge Scheduler
- **Scheduler invocations**: $1.00 per million invocations.
- First 14,400,000 invocations per month free (always-free tier).
- Flexible time windows: no additional cost.

### EventBridge Pipes
- **Events processed**: $0.40 per million events (source poll or enrichment counts as events).
- Enrichment Lambda invocations billed separately.

### Other Costs
- **Schema registry storage**: $0.10 per schema per month.
- **Archive storage**: $0.10 per GB per month.
- **Replay**: $0.015 per GB replayed.
- **API Destinations**: $0.20 per million invocations.

### Cost Optimization
- Use pattern filtering to reduce events flowing to targets (reduce Lambda invocations).
- Use Scheduler instead of Lambda-based cron (cheaper at high schedule counts).
- Enable schema discovery only when needed (has per-event cost).
- Archive selectively — don't archive all events if storage cost is a concern.
- Use `KEYS_ONLY` projection or filter inputs to reduce payload size.
- Batch PutEvents calls (up to 10 events per call, cost is per event not per API call).

---

## 20. Limits & Quotas

| Resource | Limit | Adjustable |
|---|---|---|
| Event buses per account/region | 100 | Yes |
| Rules per event bus | 300 | Yes |
| Targets per rule | 5 | No |
| Event size | 256 KB | No |
| PutEvents entries per call | 10 | No |
| PutEvents total size per call | 256 KB | No |
| `source` field length | 256 chars | No |
| `detail-type` field length | 128 chars | No |
| Input transformer input paths | 100 | No |
| Input transformer output size | 8,192 chars | No |
| Event pattern size | 4,096 chars | No |
| Retry attempts (target) | 185 | No |
| Maximum event age (target) | 86,400 sec (24 hr) | No |
| Cross-account buses per policy | Unlimited | — |
| Schedules per account | 1,000,000 | Yes |
| Schedule groups | 500 | Yes |
| Pipes per account | 1,000 | Yes |
| API Destinations | 3,000 | Yes |
| Connections | 3,000 | Yes |
| Invocation rate per API Destination | 300/sec | Yes |
| Archive retention | Unlimited (0 = infinite) | — |
| Schema registries per account | 10 | Yes |
| Schemas per registry | 1,000 | Yes |

---

## 21. Best Practices & Patterns

### Event Design
- Use **reverse-domain `source`** naming: `com.mycompany.service`.
- Use **PascalCase** for `detail-type`: `OrderPlaced`, `PaymentFailed`.
- Keep events **immutable facts** — something that happened, not commands.
- Include **correlation IDs** in events for distributed tracing.
- Version your events (`detail.schemaVersion = "1.0"`) for backward compatibility.
- Don't put large payloads in events — use S3 reference pattern (Claim Check).

### Event Pattern Design
- Be **as specific as possible** in patterns to avoid spurious rule triggers.
- Always include `source` in pattern to avoid matching unintended events.
- Use `exists: false` to match events missing a field.
- Test patterns with `test-event-pattern` before deploying.

### Architecture Patterns

#### Fanout (one event, many consumers)
```
OrderPlaced event
  └─→ Rule 1: target = Lambda (send confirmation email)
  └─→ Rule 2: target = SQS (inventory update queue)
  └─→ Rule 3: target = Step Functions (fulfillment workflow)
  └─→ Rule 4: target = Kinesis (analytics stream)
```

#### Event Router (content-based routing)
```
Payment event bus
  └─→ Rule (amount > 10000): target = fraud-review Lambda
  └─→ Rule (currency = "EUR"): target = EU-processing Lambda
  └─→ Rule (method = "CARD"): target = card-processor Lambda
```

#### Claim Check Pattern (large payloads)
```python
# Instead of putting large data in event:
def publish_large_event(data):
    # 1. Store data in S3
    key = f"events/{uuid.uuid4()}.json"
    s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(data))

    # 2. Put lightweight event with reference
    events_client.put_events(Entries=[{
        "Source": "com.myapp.reports",
        "DetailType": "ReportGenerated",
        "Detail": json.dumps({
            "s3Bucket": BUCKET,
            "s3Key": key,
            "reportType": "monthly",
        })
    }])
```

#### Saga Pattern (distributed transactions via events)
```
OrderPlaced → Lambda (reserve inventory)
  → InventoryReserved → Lambda (charge payment)
    → PaymentCharged → Lambda (schedule delivery)
      → DeliveryScheduled → Lambda (send confirmation)

Compensating events:
  PaymentFailed → Lambda (release inventory)
  DeliveryFailed → Lambda (refund payment + release inventory)
```

#### Event Aggregator (combine multiple events)
- Use Step Functions with `.waitForTaskToken` to collect events.
- Or use DynamoDB to accumulate events, trigger processing at threshold.

### Operational Best Practices
- Always configure **DLQ on every target** — events are silently dropped after retries without it.
- Use **Archives** for all production buses — you'll want to replay eventually.
- Enable **schema discovery** in early development to auto-generate schemas.
- Set `state = "DISABLED"` on rules during maintenance, not delete.
- Monitor `FailedInvocations` and `DeadLetterInvocations` metrics with alarms.
- Tag all resources for cost attribution.
- Use separate event buses per domain (orders, payments, users) not one global bus.
- Log all events to CloudWatch Logs in development/staging; selective in production.

---

## 22. Terraform Full Resource Reference

### Complete EventBridge Module

```hcl
##############################################
# variables.tf
##############################################
variable "app_name"              { type = string }
variable "environment"           { type = string }
variable "enable_archive"        { default = true }
variable "archive_retention_days"{ default = 30 }
variable "enable_schema_discovery" { default = false }
variable "log_retention_days"    { default = 7 }
variable "alert_sns_arn"         { type = string }
variable "lambda_processor_arn"  { type = string }
variable "lambda_processor_name" { type = string }
variable "sqs_target_arn"        { type = string }
variable "tags"                  { default = {} }

##############################################
# main.tf
##############################################

# --- Event Bus ---
resource "aws_cloudwatch_event_bus" "this" {
  name = "${var.app_name}-${var.environment}"
  tags = var.tags
}

# --- Bus Policy ---
resource "aws_cloudwatch_event_bus_policy" "this" {
  event_bus_name = aws_cloudwatch_event_bus.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowAccountPublish"
      Effect = "Allow"
      Principal = { AWS = data.aws_caller_identity.current.arn }
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.this.arn
    }]
  })
}

# --- Schema Discovery ---
resource "aws_schemas_discoverer" "this" {
  count       = var.enable_schema_discovery ? 1 : 0
  source_arn  = aws_cloudwatch_event_bus.this.arn
  description = "Schema discovery for ${var.app_name}"
  tags        = var.tags
}

# --- Archive ---
resource "aws_cloudwatch_event_archive" "this" {
  count            = var.enable_archive ? 1 : 0
  name             = "${var.app_name}-${var.environment}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = var.archive_retention_days
}

# --- Log Group for Event Debugging ---
resource "aws_cloudwatch_log_group" "events" {
  name              = "/aws/events/${var.app_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_resource_policy" "events" {
  policy_name = "eventbridge-logs-${var.app_name}"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"] }
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.events.arn}:*"
    }]
  })
}

# --- DLQ ---
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.app_name}-${var.environment}-event-dlq"
  message_retention_seconds = 1209600  # 14 days
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.dlq.arn
      Condition = {
        ArnLike = { "aws:SourceArn" = "${aws_cloudwatch_event_bus.this.arn}" }
      }
    }]
  })
}

# --- Example Rule: Order Events ---
resource "aws_cloudwatch_event_rule" "order_placed" {
  name           = "${var.app_name}-order-placed"
  description    = "Route OrderPlaced events"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source      = ["com.${var.app_name}.orders"]
    detail-type = ["OrderPlaced"]
  })

  tags = var.tags
}

# --- Target: Lambda ---
resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.order_placed.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "lambda-processor"
  arn            = var.lambda_processor_arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_processor_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_placed.arn
}

# --- Target: Log All (dev/staging only) ---
resource "aws_cloudwatch_event_rule" "log_all" {
  count          = var.environment != "prod" ? 1 : 0
  name           = "${var.app_name}-log-all"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  state          = "ENABLED"
  event_pattern  = jsonencode({})
}

resource "aws_cloudwatch_event_target" "log_all" {
  count          = var.environment != "prod" ? 1 : 0
  rule           = aws_cloudwatch_event_rule.log_all[0].name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "log-all"
  arn            = aws_cloudwatch_log_group.events.arn
}

# --- Scheduler ---
resource "aws_scheduler_schedule_group" "this" {
  name = "${var.app_name}-${var.environment}"
  tags = var.tags
}

resource "aws_iam_role" "scheduler" {
  name = "${var.app_name}-${var.environment}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [var.lambda_processor_arn, "${var.lambda_processor_arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })
}

# --- Alarms ---
resource "aws_cloudwatch_metric_alarm" "failed_invocations" {
  alarm_name          = "${var.app_name}-eventbridge-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions = {
    RuleName     = aws_cloudwatch_event_rule.order_placed.name
    EventBusName = aws_cloudwatch_event_bus.this.name
  }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.app_name}-event-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  alarm_actions       = [var.alert_sns_arn]
  tags                = var.tags
}

##############################################
# outputs.tf
##############################################
output "event_bus_name"   { value = aws_cloudwatch_event_bus.this.name }
output "event_bus_arn"    { value = aws_cloudwatch_event_bus.this.arn }
output "dlq_arn"          { value = aws_sqs_queue.dlq.arn }
output "dlq_url"          { value = aws_sqs_queue.dlq.url }
output "log_group_name"   { value = aws_cloudwatch_log_group.events.name }
output "archive_arn"      { value = var.enable_archive ? aws_cloudwatch_event_archive.this[0].arn : null }
output "scheduler_group"  { value = aws_scheduler_schedule_group.this.name }
output "scheduler_role_arn" { value = aws_iam_role.scheduler.arn }
```

---

### Terraform Resource Quick Reference Table

| Resource | Purpose |
|---|---|
| `aws_cloudwatch_event_bus` | Custom event bus |
| `aws_cloudwatch_event_bus_policy` | Resource policy for cross-account publish |
| `aws_cloudwatch_event_rule` | Pattern-matching rule on event bus |
| `aws_cloudwatch_event_target` | Target for a rule (Lambda, SQS, SNS, SFN, etc.) |
| `aws_cloudwatch_event_archive` | Archive events for replay |
| `aws_cloudwatch_event_connection` | Auth config for API Destinations |
| `aws_cloudwatch_event_api_destination` | External HTTP endpoint target |
| `aws_cloudwatch_event_permission` | (Legacy) cross-account rule access |
| `aws_scheduler_schedule` | One-time or recurring schedule |
| `aws_scheduler_schedule_group` | Logical group of schedules |
| `aws_pipes_pipe` | Source → [filter] → [enrichment] → target pipe |
| `aws_schemas_discoverer` | Auto-discover schemas from event bus |
| `aws_schemas_registry` | Schema registry |
| `aws_schemas_schema` | Individual event schema |
| `aws_lambda_permission` | Allow EventBridge to invoke Lambda |
| `aws_sqs_queue_policy` | Allow EventBridge to send to SQS |
| `aws_sns_topic_policy` | Allow EventBridge to publish to SNS |
| `aws_iam_role` | EventBridge execution role (for SFN, Kinesis, ECS targets) |
| `aws_iam_role_policy` | Policy on EventBridge role |
| `aws_cloudwatch_log_group` | Log group for event logging target |
| `aws_cloudwatch_log_resource_policy` | Allow EventBridge to write to CW Logs |
| `aws_cloudwatch_metric_alarm` | Failed invocations, DLQ depth alarms |
| `aws_cloudwatch_dashboard` | Operational dashboard |

---

*Last updated: February 2026*
*Next: SQS, Step Functions, ECS/Fargate, RDS, ElastiCache, S3, CloudFront*