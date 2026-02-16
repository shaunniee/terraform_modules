````markdown
# AWS SQS Terraform Module

Reusable module for creating an SQS queue with optional dead-letter queue (DLQ).

This module supports:
- Standard or FIFO queue creation
- Optional DLQ creation
- Automatic redrive policy from main queue to DLQ
- DLQ redrive allow policy for the main queue
- Queue-level tags

## Basic Usage

```hcl
module "sqs" {
  source = "./aws_sqs"

  name = "orders-queue"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Advanced Usage (FIFO + DLQ)

```hcl
module "sqs" {
  source = "./aws_sqs"

  name                       = "payments-events"
  fifo_queue                 = true
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20

  create_dlq        = true
  max_receive_count = 3

  tags = {
    Environment = "prod"
    Service     = "payments"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Base name for the queue |
| `fifo_queue` | bool | `false` | No | Create FIFO queue (`.fifo` is appended automatically) |
| `visibility_timeout_seconds` | number | `30` | No | Visibility timeout for queue messages |
| `message_retention_seconds` | number | `345600` | No | Message retention in seconds |
| `receive_wait_time_seconds` | number | `0` | No | Long polling wait time in seconds |
| `create_dlq` | bool | `false` | No | Create a dead-letter queue |
| `max_receive_count` | number | `5` | No | Receives before moving message to DLQ |
| `tags` | map(string) | `{}` | No | Tags applied to queues |

## Outputs

| Output | Description |
|--------|-------------|
| `queue_name` | Main queue name |
| `queue_arn` | Main queue ARN |
| `queue_url` | Main queue URL |
| `dlq_arn` | DLQ ARN (or `null` when DLQ disabled) |
| `dlq_url` | DLQ URL (or `null` when DLQ disabled) |

## Queue Naming Behavior

- Main queue name is:
  - `${name}` for standard queues
  - `${name}.fifo` for FIFO queues
- DLQ name is:
  - `${name}-dlq` for standard queues
  - `${name}-dlq.fifo` for FIFO queues

## DLQ Behavior

- When `create_dlq = true`:
  - Module creates a DLQ.
  - Module sets `redrive_policy` on main queue using `max_receive_count`.
  - Module creates `aws_sqs_queue_redrive_allow_policy` on DLQ for the main queue ARN.
- When `create_dlq = false`:
  - No DLQ resources are created.
  - `dlq_arn` and `dlq_url` outputs are `null`.

````
