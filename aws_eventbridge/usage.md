# aws_eventbridge module usage

Reusable EventBridge module that supports:
- Multiple event buses + default bus rules (no `aws_cloudwatch_event_bus` created for `"default"`)
- Rules with `event_pattern` or `schedule_expression`
- Multiple targets per rule with `input`, `input_path`, or `input_transformer`
- Target dead-letter queue, retry policy, and IAM role
- Separate `target_dlq_arns` variable for DLQ ARNs unknown at plan time
- Automatic Lambda invoke permissions (toggleable per target)
- Event archives with optional event pattern filtering
- Cross-account bus policies
- Observability: boolean-toggled default alarms, per-rule alarms, CloudWatch Dashboard
- Module-level `tags` merged into all taggable resources
- Custom CloudWatch metric alarms (rule-level + DLQ)

---

## 1 — Basic example (custom bus)

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  tags = { Project = "acme", Environment = "dev" }

  event_buses = [
    {
      name = "app-events"
      tags = { Team = "backend" }
      rules = [
        {
          name                = "nightly-job"
          description         = "Runs nightly"
          schedule_expression = "cron(0 2 * * ? *)"
          targets = [
            {
              id              = "nightly-lambda"
              arn             = "arn:aws:lambda:us-east-1:123456789012:function:nightly-job"
              dead_letter_arn = "arn:aws:sqs:us-east-1:123456789012:nightly-job-dlq"
            }
          ]
        }
      ]
    }
  ]
}
```

## 2 — Default bus with schedule rule

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "default"
      rules = [
        {
          name                = "daily-cleanup"
          schedule_expression = "rate(1 day)"
          targets = [
            {
              id  = "cleanup-lambda"
              arn = "arn:aws:lambda:us-east-1:123456789012:function:cleanup"
            }
          ]
        }
      ]
    }
  ]
}
```

## 3 — Input transformer

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "order-events"
      rules = [
        {
          name = "order-placed"
          event_pattern = jsonencode({
            source      = ["ecommerce.orders"]
            detail-type = ["OrderPlaced"]
          })
          targets = [
            {
              id  = "notify-lambda"
              arn = "arn:aws:lambda:us-east-1:123456789012:function:order-notifier"
              input_transformer = {
                input_paths_map = {
                  orderId    = "$.detail.orderId"
                  customerEmail = "$.detail.email"
                }
                input_template = "\"Order <orderId> placed for <customerEmail>\""
              }
            }
          ]
        }
      ]
    }
  ]
}
```

## 4 — Observability with boolean toggles

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  tags = { Project = "acme" }

  observability = {
    enabled                                  = true       # master switch
    enable_default_alarms                    = true       # ThrottledRules + InvocationsSentToDLQ + InvocationsFailedToBeSentToDLQ per bus
    enable_per_rule_failed_invocation_alarms = true       # FailedInvocations per rule
    enable_dropped_events_alarm              = true       # DroppedEvents per bus (events matching no rule)
    enable_dashboard                         = true       # CloudWatch dashboard
    enable_event_logging                     = true       # per-bus catch-all → CloudWatch Logs
    event_log_retention_in_days              = 30         # log retention (0 = never expire)
    # event_log_kms_key_arn                  = "arn:aws:kms:..."  # optional encryption
    default_alarm_actions                    = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    default_ok_actions                       = []
    default_insufficient_data_actions        = []
  }

  event_buses = [
    {
      name = "app-events"
      rules = [
        {
          name = "order-created"
          event_pattern = jsonencode({
            source      = ["ecommerce.orders"]
            detail-type = ["OrderCreated"]
          })
          targets = [
            {
              id  = "process-order"
              arn = "arn:aws:lambda:us-east-1:123456789012:function:process-order"
            }
          ]
        }
      ]
    }
  ]

  # You can still add manual alarms on top of auto-generated defaults:
  cloudwatch_metric_alarms = {
    invocations_spike = {
      rule_key            = "app-events:order-created"
      metric_name         = "Invocations"
      statistic           = "Sum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 1000
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }

  # Anomaly detection: alert on unusual invocation patterns
  cloudwatch_metric_anomaly_alarms = {
    invocations_anomaly = {
      rule_key           = "app-events:order-created"
      metric_name        = "Invocations"
      statistic          = "Sum"
      period             = 300
      evaluation_periods = 2
      band_width         = 2
      alarm_actions      = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }
}
```

## 5 — Event archive

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name            = "audit-events"
      prevent_destroy = true    # guard against accidental deletion
      rules           = []
    }
  ]

  archives = [
    {
      name           = "audit-archive"
      bus_name       = "audit-events"
      retention_days = 90
      event_pattern  = jsonencode({
        source = ["audit.service"]
      })
    }
  ]
}
```

## 6 — Cross-account bus policy

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "shared-events"
      rules = []
    }
  ]

  bus_policies = [
    {
      bus_name = "shared-events"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid       = "AllowCrossAccountPutEvents"
            Effect    = "Allow"
            Principal = { AWS = "arn:aws:iam::987654321098:root" }
            Action    = "events:PutEvents"
            Resource  = "*"
          }
        ]
      })
    }
  ]
}
```

## 7 — Advanced: DLQ alarms

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "app-events"
      rules = [
        {
          name                = "nightly-job"
          schedule_expression = "cron(0 2 * * ? *)"
          targets = [
            {
              id  = "nightly-lambda"
              arn = "arn:aws:lambda:us-east-1:123456789012:function:nightly-job"
            }
          ]
        }
      ]
    }
  ]

  # DLQ ARNs passed separately to avoid unknown-at-plan-time for_each errors.
  # Keys use the format: <bus_name>:<rule_name>:<target_id>
  target_dlq_arns = {
    "app-events:nightly-job:nightly-lambda" = "arn:aws:sqs:us-east-1:123456789012:nightly-job-dlq"
  }

  dlq_cloudwatch_metric_alarms = {
    dlq_visible_messages = {
      target_key          = "app-events:nightly-job:nightly-lambda"
      metric_name         = "ApproximateNumberOfMessagesVisible"
      statistic           = "Maximum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    dlq_oldest_message_age = {
      target_key          = "app-events:nightly-job:nightly-lambda"
      metric_name         = "ApproximateAgeOfOldestMessage"
      statistic           = "Maximum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 300
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }
}
```

## 7a — DLQ ARNs from resource outputs (`target_dlq_arns`)

When the DLQ ARN comes from a resource created in the same plan (e.g., an `aws_sqs_queue`),
use `target_dlq_arns` instead of `dead_letter_arn` inside the target definition. This avoids
Terraform's "for_each depends on resource attributes that cannot be determined until apply"
error caused by unknown values leaking into `for_each` keys.

```hcl
module "dlq" {
  source = "../aws_sqs"
  # ... creates the DLQ queue
}

module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "order-events"
      rules = [
        {
          name = "process-order"
          event_pattern = jsonencode({
            source      = ["ecommerce.orders"]
            detail-type = ["OrderPlaced"]
          })
          targets = [
            {
              id  = "order-processor"
              arn = "arn:aws:lambda:us-east-1:123456789012:function:process-order"
              # Do NOT set dead_letter_arn here when the value is unknown at plan time.
            }
          ]
        }
      ]
    }
  ]

  # Pass DLQ ARNs separately — keys are <bus_name>:<rule_name>:<target_id>
  target_dlq_arns = {
    "order-events:process-order:order-processor" = module.dlq.queue_arn
  }
}
```

## 8 — ECS Fargate target

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "app-events"
      rules = [
        {
          name = "process-batch"
          event_pattern = jsonencode({
            source      = ["batch.processor"]
            detail-type = ["BatchReady"]
          })
          targets = [
            {
              id       = "ecs-task"
              arn      = "arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster"
              role_arn = "arn:aws:iam::123456789012:role/ecsEventsRole"
              create_lambda_permission = false
              ecs_target = {
                task_definition_arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/batch-processor:1"
                task_count          = 1
                launch_type         = "FARGATE"
                network_configuration = {
                  subnets          = ["subnet-abc123", "subnet-def456"]
                  security_groups  = ["sg-12345"]
                  assign_public_ip = false
                }
              }
            }
          ]
        }
      ]
    }
  ]
}
```

## 9 — Connection + API Destination (webhook target)

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "webhook-events"
      rules = [
        {
          name = "notify-slack"
          event_pattern = jsonencode({
            source      = ["app.notifications"]
            detail-type = ["AlertTriggered"]
          })
          targets = [
            {
              id       = "slack-webhook"
              arn      = module.eventbridge.api_destination_arns["slack-webhook"]
              role_arn = "arn:aws:iam::123456789012:role/eventbridge-api-dest-role"
              create_lambda_permission = false
              http_target = {
                header_parameters = { "Content-Type" = "application/json" }
              }
            }
          ]
        }
      ]
    }
  ]

  connections = {
    slack = {
      authorization_type = "API_KEY"
      auth_parameters = {
        api_key = {
          key   = "Authorization"
          value = "Bearer xoxb-your-slack-token"
        }
      }
    }
  }

  api_destinations = {
    slack-webhook = {
      invocation_endpoint              = "https://hooks.slack.com/services/T00/B00/xxx"
      http_method                      = "POST"
      invocation_rate_limit_per_second = 10
      connection_key                   = "slack"
    }
  }
}
```

## 10 — Schema Registry & Discovery

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  tags = { Project = "acme" }

  event_buses = [
    {
      name = "order-events"
      rules = []
    }
  ]

  # Create a custom schema registry
  schema_registries = {
    orders = {
      description = "Event schemas for the orders domain"
      tags        = { Domain = "orders" }
    }
  }

  # Define event contracts as schemas
  schemas = {
    "ecommerce.orders@OrderCreated" = {
      registry_key = "orders"
      type         = "OpenApi3"
      description  = "Published when a new order is placed"
      content = jsonencode({
        openapi = "3.0.0"
        info    = { title = "OrderCreated", version = "1.0.0" }
        paths   = {}
        components = {
          schemas = {
            OrderCreated = {
              type = "object"
              properties = {
                orderId     = { type = "string" }
                customerId  = { type = "string" }
                totalAmount = { type = "number" }
                currency    = { type = "string", enum = ["USD", "EUR", "GBP"] }
              }
              required = ["orderId", "customerId", "totalAmount"]
            }
          }
        }
      })
    }
  }

  # Auto-discover schemas from events flowing through the bus
  schema_discoverers = {
    order-bus-discoverer = {
      bus_name    = "order-events"
      description = "Auto-discover event schemas on the order-events bus"
    }
  }
}
```

---

## 11 — EventBridge Pipe (SQS → Lambda with Filtering)

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  tags = { Project = "acme" }

  event_buses = [
    {
      name        = "default"
      description = "Default bus"
      rules       = []
    }
  ]

  pipes = {
    order-processor = {
      description   = "Process orders from SQS queue through Lambda"
      role_arn      = "arn:aws:iam::123456789012:role/pipes-order-processor"
      desired_state = "RUNNING"
      source        = "arn:aws:sqs:us-east-1:123456789012:order-queue"
      target        = "arn:aws:lambda:us-east-1:123456789012:function:process-order"

      source_parameters = {
        filter_criteria = {
          filters = [
            { pattern = jsonencode({ body = { orderType = ["PREMIUM"] } }) }
          ]
        }
        sqs = {
          batch_size                         = 5
          maximum_batching_window_in_seconds = 10
        }
      }

      target_parameters = {
        lambda_function = {
          invocation_type = "REQUEST_RESPONSE"
        }
      }

      log_configuration = {
        level = "ERROR"
        cloudwatch_logs_log_destination = {
          log_group_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/pipes/order-processor"
        }
      }
    }
  }
}
```

---

## 12 — EventBridge Pipe (DynamoDB Streams → Step Functions with Enrichment)

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  tags = { Project = "acme" }

  event_buses = [
    { name = "default", rules = [] }
  ]

  pipes = {
    stream-to-workflow = {
      description   = "Process DynamoDB stream changes through Step Functions"
      role_arn      = "arn:aws:iam::123456789012:role/pipes-stream-workflow"
      source        = "arn:aws:dynamodb:us-east-1:123456789012:table/orders/stream/2024-01-01T00:00:00.000"
      target        = "arn:aws:states:us-east-1:123456789012:stateMachine:process-order"
      enrichment    = "arn:aws:lambda:us-east-1:123456789012:function:enrich-order"

      source_parameters = {
        dynamodb_stream = {
          starting_position = "LATEST"
          batch_size        = 10
        }
        filter_criteria = {
          filters = [
            { pattern = jsonencode({ eventName = ["INSERT", "MODIFY"] }) }
          ]
        }
      }

      enrichment_parameters = {
        input_template = jsonencode({
          orderId = "<$.dynamodb.Keys.pk.S>"
          action  = "<$.eventName>"
        })
      }

      target_parameters = {
        step_function = {
          invocation_type = "FIRE_AND_FORGET"
        }
      }
    }
  }
}
```

---

### `event_buses`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `string` | — | Bus name. Use `"default"` for the default bus (no resource created). |
| `description` | `string` | `null` | Description for the custom event bus. |
| `tags` | `map(string)` | `{}` | Tags for the bus resource. |
| `prevent_destroy` | `bool` | `false` | Guard against accidental bus deletion (precondition check). |
| `rules` | `list(object)` | `[]` | Rules attached to this bus. |

### `event_buses[].rules[]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `string` | — | Rule name (unique per bus, no colons). |
| `description` | `string` | `null` | Rule description. |
| `is_enabled` | `bool` | `true` | Enable/disable rule (maps to ENABLED/DISABLED state). |
| `event_pattern` | `string` | `null` | JSON event pattern. Mutually exclusive with `schedule_expression`. |
| `schedule_expression` | `string` | `null` | `rate(...)` or `cron(...)`. Only on default bus. |
| `tags` | `map(string)` | `{}` | Tags for the rule resource (merged with module `tags`). |
| `targets` | `list(object)` | `[]` | Targets for the rule. |

### `event_buses[].rules[].targets[]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `string` | — | Target ID (unique per rule, no colons). |
| `arn` | `string` | — | Target ARN (`arn:...`). |
| `input` | `string` | `null` | Static JSON input. Mutually exclusive with `input_path` and `input_transformer`. |
| `input_path` | `string` | `null` | JSONPath from event. Mutually exclusive with `input` and `input_transformer`. |
| `input_transformer` | `object` | `null` | `{ input_paths_map, input_template }`. Mutually exclusive with `input` and `input_path`. |
| `role_arn` | `string` | `null` | IAM role ARN EventBridge assumes (must be `arn:aws:iam::<acct>:role/...`). |
| `dead_letter_arn` | `string` | `null` | SQS DLQ ARN for failed deliveries. For apply-time unknown values, use `target_dlq_arns` instead. |
| `retry_policy.maximum_event_age_in_seconds` | `number` | `null` | 60–86400. |
| `retry_policy.maximum_retry_attempts` | `number` | `null` | 0–185. |
| `create_lambda_permission` | `bool` | `true` | Auto-create `aws_lambda_permission` for Lambda targets. |
| `lambda_permission_statement_id` | `string` | `null` | Custom statement ID. |
| `lambda_function_name` | `string` | `null` | Override function name for permission. |
| `lambda_qualifier` | `string` | `null` | Lambda version/alias qualifier. |
| `ecs_target` | `object` | `null` | ECS target config: `task_definition_arn`, `task_count`, `launch_type`, `network_configuration`, etc. |
| `kinesis_target` | `object` | `null` | Kinesis target config: `partition_key_path`. |
| `sqs_target` | `object` | `null` | SQS target config: `message_group_id` (FIFO queues). |
| `http_target` | `object` | `null` | HTTP/API Destination target config: `header_parameters`, `query_string_parameters`, `path_parameter_values`. |
| `batch_target` | `object` | `null` | AWS Batch target config: `job_definition`, `job_name`, `array_size`, `job_attempts`. |

### `observability`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Master switch — enables all observability features. |
| `enable_default_alarms` | `bool` | `true` | Auto-create bus-level ThrottledRules + InvocationsSentToDLQ + InvocationsFailedToBeSentToDLQ alarms. |
| `enable_per_rule_failed_invocation_alarms` | `bool` | `true` | Auto-create per-rule FailedInvocations alarms. |
| `enable_dropped_events_alarm` | `bool` | `true` | Auto-create per-bus DroppedEvents alarm (events matching no rule). |
| `enable_dashboard` | `bool` | `false` | Create a CloudWatch dashboard. |
| `enable_event_logging` | `bool` | `false` | Create per-bus catch-all rules that send all events to CloudWatch Logs. |
| `event_log_retention_in_days` | `number` | `14` | Retention for event log groups (0 = never expire). |
| `event_log_kms_key_arn` | `string` | `null` | KMS key ARN for event log group encryption. |
| `default_alarm_actions` | `list(string)` | `[]` | SNS ARNs for ALARM state. |
| `default_ok_actions` | `list(string)` | `[]` | SNS ARNs for OK state. |
| `default_insufficient_data_actions` | `list(string)` | `[]` | SNS ARNs for INSUFFICIENT_DATA. |

### `pipes`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `description` | `string` | `null` | Pipe description. |
| `desired_state` | `string` | `"RUNNING"` | `RUNNING` or `STOPPED`. |
| `role_arn` | `string` | — | IAM role ARN the pipe assumes. |
| `source` | `string` | — | Source resource ARN (SQS, Kinesis, DynamoDB, MSK, etc.). |
| `target` | `string` | — | Target resource ARN (Lambda, Step Functions, SQS, ECS, etc.). |
| `enrichment` | `string` | `null` | Enrichment ARN (Lambda, API Gateway, Step Functions, API Destination). |
| `tags` | `map(string)` | `{}` | Tags for the pipe resource. |
| `source_parameters` | `object` | `null` | Source-specific config: `filter_criteria`, `sqs`, `kinesis_stream`, `dynamodb_stream`, `managed_streaming_kafka`, `self_managed_kafka`, `activemq_broker`, `rabbitmq_broker`. |
| `target_parameters` | `object` | `null` | Target-specific config: `input_template`, `lambda_function`, `step_function`, `sqs`, `kinesis_stream`, `eventbridge_event_bus`, `ecs_task`, `cloudwatch_logs`, `http`, `sagemaker_pipeline`, `batch_job`, `redshift_data`. |
| `enrichment_parameters` | `object` | `null` | Enrichment config: `input_template`, `http` (headers, query strings, path params). |
| `log_configuration` | `object` | `null` | Logging config: `level` (OFF/ERROR/INFO/TRACE), `cloudwatch_logs_log_destination`, `firehose_log_destination`, `s3_log_destination`. |

### Other top-level variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `tags` | `map(string)` | `{}` | Tags applied to all taggable resources. |
| `target_dlq_arns` | `map(string)` | `{}` | Map of `<bus_name>:<rule_name>:<target_id>` → SQS DLQ ARN. Use instead of inline `dead_letter_arn` when the ARN is unknown at plan time (e.g., resource output). |
| `lambda_permission_statement_id_prefix` | `string` | `"AllowExecutionFromEventBridge"` | Prefix for generated Lambda permission statement IDs. |
| `archives` | `list(object)` | `[]` | Event archives. Each needs `name` + (`bus_name` or `event_source_arn`). |
| `bus_policies` | `list(object)` | `[]` | Resource policies (one per bus). Each needs `bus_name` + `policy` (JSON). |
| `connections` | `map(object)` | `{}` | EventBridge connections for API destinations (API_KEY, BASIC, OAUTH). |
| `api_destinations` | `map(object)` | `{}` | API destinations for HTTP/webhook targets. Each needs `connection_key`, `invocation_endpoint`, `http_method`. |
| `schema_registries` | `map(object)` | `{}` | Schema registries (namespaces). Cannot use reserved names `aws.events` or `discovered-schemas`. |
| `schemas` | `map(object)` | `{}` | Schemas within registries. Each needs `registry_key`, `type` (OpenApi3/JSONSchemaDraft4), `content`. |
| `schema_discoverers` | `map(object)` | `{}` | Discoverers that auto-detect schemas from bus events. Each needs `bus_name`. |
| `pipes` | `map(object)` | `{}` | EventBridge Pipes. Each needs `source`, `target`, `role_arn`. Supports filtering, enrichment, logging, 8 source types, 11 target types. |
| `cloudwatch_metric_alarms` | `map(object)` | `{}` | Custom CloudWatch alarms (AWS/Events namespace). Supports `extended_statistic` for percentile alarms. |
| `dlq_cloudwatch_metric_alarms` | `map(object)` | `{}` | DLQ alarms (AWS/SQS namespace). Supports `extended_statistic` for percentile alarms. |
| `cloudwatch_metric_anomaly_alarms` | `map(object)` | `{}` | Anomaly detection alarms (ANOMALY_DETECTION_BAND). |

---

## Outputs

| Output | Description |
|--------|-------------|
| `event_rule_arns` | Map of rule ARNs by `<bus_name>:<rule_name>`. |
| `event_rule_names` | Map of rule names by `<bus_name>:<rule_name>`. |
| `event_bus_arns` | Map of custom bus ARNs by name (excludes `default`). |
| `event_bus_names` | Map of all bus names (includes `default` if used). |
| `target_arns` | Map of target ARNs by `<bus_name>:<rule_name>:<target_id>`. |
| `lambda_permission_statement_ids` | Map of statement IDs by target key. |
| `archive_arns` | Map of archive ARNs by name. |
| `bus_policy_ids` | Map of bus policy IDs by bus name. |
| `cloudwatch_metric_alarm_arns` | Map of alarm ARNs by key. |
| `cloudwatch_metric_alarm_names` | Map of alarm names by key. |
| `dlq_cloudwatch_metric_alarm_arns` | Map of DLQ alarm ARNs by key. |
| `dlq_cloudwatch_metric_alarm_names` | Map of DLQ alarm names by key. |
| `cloudwatch_metric_anomaly_alarm_arns` | Map of anomaly detection alarm ARNs by key. |
| `cloudwatch_metric_anomaly_alarm_names` | Map of anomaly detection alarm names by key. |
| `dashboard_name` | Dashboard name (`null` if not created). |
| `dashboard_arn` | Dashboard ARN (`null` if not created). |
| `event_log_group_names` | Map of event log group names by bus name. |
| `event_log_group_arns` | Map of event log group ARNs by bus name. |
| `event_log_rule_arns` | Map of catch-all logging rule ARNs by bus name. |
| `connection_arns` | Map of connection ARNs by name. |
| `connection_names` | Map of connection names by name. |
| `api_destination_arns` | Map of API destination ARNs by name. |
| `api_destination_names` | Map of API destination names by name. |
| `schema_registry_arns` | Map of schema registry ARNs by name. |
| `schema_registry_names` | Map of schema registry names by name. |
| `schema_arns` | Map of schema ARNs by name. |
| `schema_versions` | Map of latest schema version numbers by name. |
| `schema_discoverer_ids` | Map of schema discoverer IDs by name. |
| `schema_discoverer_arns` | Map of schema discoverer ARNs by name. |
| `pipe_arns` | Map of EventBridge Pipe ARNs by name. |
| `pipe_names` | Map of EventBridge Pipe names by key. |
| `pipe_states` | Map of EventBridge Pipe desired states by key. |
| `observability` | Summary object: `enabled`, `total_alarms_created`, `default_alarms_created`, `anomaly_alarms_created`, `dashboard_enabled`, `event_logging_enabled`, `event_log_groups_created`. |

---

## Validations

The module enforces these validations at plan time:

1. Bus names: unique, non-empty, no colons, valid characters (or `"default"`)
2. Rule names: unique per bus, non-empty, no colons
3. Target IDs: unique per rule, non-empty, no colons
4. `event_pattern` xor `schedule_expression` (exactly one, non-empty)
5. `event_pattern` must be valid JSON
6. `schedule_expression` must match `rate(...)` or `cron(...)` and only on default bus
7. `input`, `input_path`, `input_transformer` are mutually exclusive (at most one)
8. Target `arn` starts with `arn:`
9. `role_arn` is valid IAM role ARN format
10. `dead_letter_arn` starts with `arn:`
11. `retry_policy.maximum_event_age_in_seconds`: 60–86400
12. `retry_policy.maximum_retry_attempts`: 0–185
13. `lambda_permission_statement_id`: 1–100 chars (A-Z, 0-9, -, _)
14. `lambda_permission_statement_id_prefix`: 1–80 chars
15. Alarm `comparison_operator`: valid CloudWatch operators
16. Alarm `treat_missing_data`: `breaching|notBreaching|ignore|missing`
17. Alarm `rule_key` format: `<bus_name>:<rule_name>`
18. DLQ alarm `target_key` format: `<bus_name>:<rule_name>:<target_id>`
19. Archive names unique, valid JSON pattern, `retention_days >= 0`
20. Bus policies: one per bus, valid JSON policy
21. Observability action ARNs must start with `arn:`
22. Anomaly alarm `rule_key` format: `<bus_name>:<rule_name>`
23. Anomaly alarm `band_width` must be > 0
24. Anomaly alarm `evaluation_periods` must be >= 1
25. Event log `event_log_retention_in_days` must be a valid CloudWatch Logs retention value
26. Event log `event_log_kms_key_arn` must be a valid KMS ARN when provided
27. `statistic` and `extended_statistic` are mutually exclusive (per alarm)
28. Connection `authorization_type` must be API_KEY, BASIC, or OAUTH_CLIENT_CREDENTIALS
29. API destination `http_method` must be a valid HTTP method
30. API destination `invocation_rate_limit_per_second`: 1–300
31. API destination `invocation_endpoint` must start with `https://`
32. Schema registry names: no reserved names (`aws.events`, `discovered-schemas`), valid characters
33. Schema names: start with a letter, 1–385 chars, valid characters
34. Schema `type`: must be `OpenApi3` or `JSONSchemaDraft4`
35. Schema `content`: must be non-empty
36. Schema discoverer `bus_name`: must be non-empty
37. Pipe `desired_state`: must be `RUNNING` or `STOPPED`
38. Pipe `role_arn`: must start with `arn:`
39. Pipe `source`: must start with `arn:`
40. Pipe `target`: must start with `arn:`
41. Pipe `enrichment`: must start with `arn:` when provided
42. Pipe `log_configuration.level`: must be `OFF`, `ERROR`, `INFO`, or `TRACE`
43. Pipe map keys: 1–64 chars, alphanumeric with `.`, `-`, `_`
44. Pipe `source_parameters.sqs.batch_size`: 1–10000
45. Pipe `source_parameters.kinesis_stream.starting_position`: `TRIM_HORIZON`, `AT_TIMESTAMP`, or `LATEST`
46. Pipe `source_parameters.dynamodb_stream.starting_position`: `TRIM_HORIZON` or `LATEST`
47. Pipe `target_parameters.lambda_function.invocation_type`: `REQUEST_RESPONSE` or `FIRE_AND_FORGET`
48. Pipe `target_parameters.step_function.invocation_type`: `REQUEST_RESPONSE` or `FIRE_AND_FORGET`

## DLQ logging note

SQS DLQs expose CloudWatch metrics natively, but message-level logs are not emitted to CloudWatch Logs automatically.
For DLQ logging, attach a DLQ consumer (Lambda or worker) and log payloads there, then create log-based metrics/alarms from that consumer log group.

## Best practices

- **Always enable observability** for production workloads — set `observability.enabled = true` and provide at least `default_alarm_actions`
- **Enable event logging** for audit/debug — set `observability.enable_event_logging = true` to create per-bus catch-all rules that stream all events to `/aws/events/<bus_name>` log groups, queryable via CloudWatch Logs Insights
- **`InvocationsFailedToBeSentToDLQ` is critical** — this alarm catches events silently dropped when the DLQ itself is unreachable. It's auto-created with `enable_default_alarms = true`.
- **Use anomaly detection** (`cloudwatch_metric_anomaly_alarms`) for Invocations and FailedInvocations to catch unusual patterns without knowing the right static threshold
- **Use `extended_statistic`** (e.g., `"p95"`, `"p99"`) in custom alarms for latency-sensitive metrics
- **Default alarms use `evaluation_periods = 2`** to reduce flapping from transient spikes — override if you need instant alerts
- **Use the default bus** for schedule-based rules (AWS requirement) and custom buses for domain events
- **Set `dead_letter_arn`** on every critical target to capture failed deliveries
- **Use `target_dlq_arns`** instead of inline `dead_letter_arn` when the DLQ ARN comes from a resource in the same plan (e.g., `module.dlq.queue_arn`). This avoids Terraform's "for_each depends on resource attributes that cannot be determined until apply" error.
- **Use `input_transformer`** instead of `input` when you need partial extraction from the event
- **Create archives** for audit/compliance buses where you may need event replay
- **Dashboard name** is auto-truncated to 255 chars with a hash suffix for many-bus deployments
- **Event log cost** — catch-all rules log every event; for high-volume buses, use `event_log_retention_in_days` aggressively and consider KMS encryption for compliance
- **CloudWatch Log resource policy limit** — CW Log resource policies are limited to **5120 bytes per account per region** and are global (not scoped to the module). If you have many buses or existing policies in the account, the event logging resource policy may exceed this limit. Consider consolidating or disabling logging for low-priority buses.
- **Use `prevent_destroy = true`** on production buses to guard against accidental deletion from variable changes
- **Use connections + API destinations** for HTTP/webhook targets instead of a Lambda intermediary — it's simpler and has built-in rate limiting
- **Use schema registries** to document event contracts — define OpenApi3 or JSONSchemaDraft4 schemas for every event type to enable code generation and cross-team discovery
- **Enable schema discoverers** on non-production buses to auto-detect event shapes, then codify them as explicit schemas for production
- **Avoid colons** in bus, rule, and target names — they are used as internal composite keys
- **Use EventBridge Pipes** to connect sources directly to targets point-to-point without rules — ideal for SQS→Lambda, DynamoDB Streams→Step Functions, Kinesis→EventBridge patterns
- **Pipe IAM roles need both source and target permissions** — create a role with `pipes.amazonaws.com` trust policy, then attach policies for reading from source and invoking target
- **Enable pipe logging** (`log_configuration.level = "ERROR"`) for production pipes — logs go to CloudWatch Logs, Firehose, or S3
- **Use `filter_criteria`** in pipes to process only matching events at the source level, reducing target invocations and cost
- **Use enrichment** sparingly — every pipe invocation calls the enrichment function, adding latency and cost; prefer transforming in the target when possible
- **Set `desired_state = "STOPPED"`** when deploying a new pipe for testing before enabling it in production
