# AWS Step Functions — Complete Engineering Reference Notes
> For use inside Terraform modules. Every detail, feature, config, and Terraform resource reference included.

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Workflow Types](#2-workflow-types)
3. [Amazon States Language (ASL)](#3-amazon-states-language-asl)
4. [State Types](#4-state-types)
5. [Service Integrations](#5-service-integrations)
6. [IAM & Permissions](#6-iam--permissions)
7. [Versioning & Aliases](#7-versioning--aliases)
8. [Error Handling & Retries](#8-error-handling--retries)
9. [Input/Output Processing](#9-inputoutput-processing)
10. [Encryption](#10-encryption)
11. [Observability — Logging](#11-observability--logging)
12. [Observability — Metrics](#12-observability--metrics)
13. [Observability — Tracing (X-Ray)](#13-observability--tracing-x-ray)
14. [Express vs Standard Deep Dive](#14-express-vs-standard-deep-dive)
15. [Concurrency & Throttling](#15-concurrency--throttling)
16. [Map State & Distributed Map](#16-map-state--distributed-map)
17. [Activity Tasks](#17-activity-tasks)
18. [Callback Pattern (waitForTaskToken)](#18-callback-pattern-waitfortasktoken)
19. [Cost Model](#19-cost-model)
20. [Limits & Quotas](#20-limits--quotas)
21. [Security Best Practices](#21-security-best-practices)
22. [Terraform Full Resource Reference](#22-terraform-full-resource-reference)

---

## 1. Core Concepts

### What Step Functions Is
- **Serverless orchestration service** — coordinate distributed applications and microservices using visual workflows.
- Workflows are defined using **Amazon States Language (ASL)**, a JSON-based structured language.
- Two workflow types: **Standard** (long-running, exactly-once) and **Express** (high-volume, at-least-once).
- State machines manage state transitions, error handling, retries, and parallel execution automatically.
- Integrates natively with 220+ AWS services via optimized and SDK integrations.

### Execution Models
| Feature | Standard | Express |
|---|---|---|
| **Max duration** | 1 year | 5 minutes |
| **Execution semantics** | Exactly-once | At-least-once (Synchronous Express: at-most-once) |
| **Execution history** | Stored for 90 days in console | Must use CloudWatch Logs |
| **Pricing** | Per state transition | Per execution + duration + memory |
| **Max start rate** | 2,000/sec (burst) | 100,000/sec |
| **Execution concurrency** | 1,000,000 | Unlimited |

---

## 2. Workflow Types

### Standard Workflows
- Durable, long-running (up to 365 days).
- Exactly-once execution of each state.
- Execution history viewable in AWS Console for 90 days.
- Best for: orchestration, human approval steps, long batch jobs, ETL pipelines.
- Priced per state transition ($0.025 per 1,000 transitions).

### Express Workflows
- High-volume, short-duration (up to 5 minutes).
- At-least-once execution (idempotent design required).
- **Synchronous Express**: caller waits for result (API Gateway integration).
- **Asynchronous Express**: fire-and-forget; results in CloudWatch Logs.
- Priced per request + duration + memory ($1.00 per 1M requests + $0.00001667 per GB-second).
- **Requires CloudWatch logging** for any debugging/visibility.

---

## 3. Amazon States Language (ASL)

### Structure
```json
{
  "Comment": "Description of the state machine",
  "StartAt": "FirstState",
  "States": {
    "FirstState": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...",
      "Next": "SecondState"
    },
    "SecondState": {
      "Type": "Succeed"
    }
  }
}
```

### Top-Level Fields
| Field | Type | Required | Description |
|---|---|---|---|
| `Comment` | string | No | Human-readable description |
| `StartAt` | string | Yes | Name of the first state to execute |
| `States` | object | Yes | Map of state name → state definition |
| `TimeoutSeconds` | integer | No | Execution timeout for the entire workflow |
| `Version` | string | No | ASL version (default: "1.0") |

---

## 4. State Types

### Task
Executes work (Lambda, SDK integration, Activity, etc.).
```json
{
  "Type": "Task",
  "Resource": "arn:aws:states:::lambda:invoke",
  "Parameters": {
    "FunctionName": "my-function",
    "Payload.$": "$"
  },
  "ResultPath": "$.taskResult",
  "Retry": [...],
  "Catch": [...],
  "TimeoutSeconds": 300,
  "HeartbeatSeconds": 60,
  "Next": "NextState"
}
```

### Pass
Passes input to output (optionally transforming).
```json
{ "Type": "Pass", "Result": {"status": "ok"}, "Next": "NextState" }
```

### Choice
Branching logic based on input comparison.
```json
{
  "Type": "Choice",
  "Choices": [
    { "Variable": "$.status", "StringEquals": "APPROVED", "Next": "ProcessOrder" },
    { "Variable": "$.amount", "NumericGreaterThan": 1000, "Next": "ManualReview" }
  ],
  "Default": "DefaultHandler"
}
```

### Wait
Delays execution for a fixed time or until a timestamp.
```json
{ "Type": "Wait", "Seconds": 60, "Next": "NextState" }
{ "Type": "Wait", "Timestamp": "2025-01-01T00:00:00Z", "Next": "NextState" }
{ "Type": "Wait", "SecondsPath": "$.waitTime", "Next": "NextState" }
```

### Parallel
Executes multiple branches concurrently.
```json
{
  "Type": "Parallel",
  "Branches": [
    { "StartAt": "BranchA", "States": { "BranchA": { "Type": "Pass", "End": true } } },
    { "StartAt": "BranchB", "States": { "BranchB": { "Type": "Pass", "End": true } } }
  ],
  "Next": "MergeResults"
}
```

### Map
Iterates over an array, executing a sub-workflow for each item.
```json
{
  "Type": "Map",
  "ItemsPath": "$.items",
  "MaxConcurrency": 10,
  "Iterator": {
    "StartAt": "ProcessItem",
    "States": {
      "ProcessItem": { "Type": "Task", "Resource": "arn:aws:lambda:...", "End": true }
    }
  },
  "Next": "Done"
}
```

### Succeed / Fail
Terminal states.
```json
{ "Type": "Succeed" }
{ "Type": "Fail", "Error": "CustomError", "Cause": "Something went wrong" }
```

---

## 5. Service Integrations

### Integration Patterns
| Pattern | Suffix | Behavior |
|---|---|---|
| **Request Response** | (none) | Call API and continue immediately |
| **Run a Job (.sync)** | `.sync` | Wait for completion (Lambda, ECS, Glue, etc.) |
| **Wait for Callback (.waitForTaskToken)** | `.waitForTaskToken` | Pause until external callback via `SendTaskSuccess`/`SendTaskFailure` |

### Common Service Integrations
| Service | Resource ARN Pattern |
|---|---|
| Lambda | `arn:aws:states:::lambda:invoke` |
| DynamoDB | `arn:aws:states:::dynamodb:getItem` / `putItem` / `updateItem` / `deleteItem` |
| SQS | `arn:aws:states:::sqs:sendMessage` |
| SNS | `arn:aws:states:::sns:publish` |
| ECS/Fargate | `arn:aws:states:::ecs:runTask.sync` |
| Glue | `arn:aws:states:::glue:startJobRun.sync` |
| SageMaker | `arn:aws:states:::sagemaker:createTrainingJob.sync` |
| EventBridge | `arn:aws:states:::events:putEvents` |
| S3 | `arn:aws:states:::aws-sdk:s3:getObject` |
| Step Functions | `arn:aws:states:::states:startExecution.sync` (nested) |
| Bedrock | `arn:aws:states:::bedrock:invokeModel` |

### SDK Integrations (200+ services)
- `arn:aws:states:::aws-sdk:<service>:<apiAction>`
- Automatically maps to any AWS API action.
- Requires corresponding IAM permissions on the execution role.

---

## 6. IAM & Permissions

### Execution Role
- Every state machine requires an IAM role with `states.amazonaws.com` as the trusted principal.
- The role needs permissions for every service the state machine interacts with.
- Use `aws:SourceAccount` condition to prevent confused deputy attacks.

### Minimum Trust Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "states.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "<ACCOUNT_ID>"
        }
      }
    }
  ]
}
```

### Logging Permissions (Required for CloudWatch Logs)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogDelivery",
        "logs:CreateLogStream",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutLogEvents",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    }
  ]
}
```
> Note: Step Functions logging permissions require `Resource: "*"` because the service uses log delivery APIs that operate at the account level.

### X-Ray Tracing Permissions
Attach `arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess`.

### Per-Integration Permissions
Each service integration requires specific IAM actions:
- **Lambda**: `lambda:InvokeFunction`
- **DynamoDB**: `dynamodb:GetItem`, `dynamodb:PutItem`, etc.
- **SQS**: `sqs:SendMessage`
- **SNS**: `sns:Publish`
- **ECS**: `ecs:RunTask`, `ecs:StopTask`, `ecs:DescribeTasks`, `iam:PassRole`
- **EventBridge**: `events:PutEvents`

---

## 7. Versioning & Aliases

### Versions
- Created when `publish = true` on the state machine.
- Immutable snapshots of the state machine definition and configuration.
- Each version gets a unique ARN: `arn:aws:states:<region>:<account>:stateMachine:<name>:<version>`
- Previous versions are retained and can be referenced.

### Aliases
- Named pointers to one or two state machine versions.
- Support **weighted routing** for canary deployments.
- Alias ARN: `arn:aws:states:<region>:<account>:stateMachine:<name>:<alias-name>`
- Can be used in `StartExecution` API calls for traffic shifting.

### Terraform Resources
```hcl
resource "aws_sfn_state_machine" "this" {
  publish = true  # Creates a version
}

resource "aws_sfn_alias" "live" {
  name = "live"
  routing_configuration {
    state_machine_version_arn = aws_sfn_state_machine.this.state_machine_version_arn
    weight                    = 100
  }
}
```

---

## 8. Error Handling & Retries

### Retry
```json
{
  "Retry": [
    {
      "ErrorEquals": ["States.TaskFailed"],
      "IntervalSeconds": 2,
      "MaxAttempts": 3,
      "BackoffRate": 2.0,
      "MaxDelaySeconds": 60,
      "JitterStrategy": "FULL"
    }
  ]
}
```

| Field | Description |
|---|---|
| `ErrorEquals` | List of error names to match |
| `IntervalSeconds` | Initial retry delay |
| `MaxAttempts` | Maximum retry count (0 = no retries) |
| `BackoffRate` | Multiplier for delay between retries |
| `MaxDelaySeconds` | Cap on retry delay |
| `JitterStrategy` | `FULL` or `NONE` (randomize retry delay) |

### Catch
```json
{
  "Catch": [
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.error",
      "Next": "ErrorHandler"
    }
  ]
}
```

### Predefined Error Names
| Error | Description |
|---|---|
| `States.ALL` | Matches all errors |
| `States.TaskFailed` | Task returned failure |
| `States.Timeout` | State or execution timed out |
| `States.Permissions` | Insufficient IAM permissions |
| `States.ResultPathMatchFailure` | ResultPath cannot be applied |
| `States.ParameterPathFailure` | Parameter path resolution failed |
| `States.BranchFailed` | Parallel branch failed |
| `States.NoChoiceMatched` | No Choice rule matched |
| `States.IntrinsicFailure` | Intrinsic function failed |
| `States.HeartbeatTimeout` | Heartbeat not received in time |
| `States.ItemReaderFailed` | Distributed Map item reader failed |
| `States.ResultWriterFailed` | Distributed Map result writer failed |

---

## 9. Input/Output Processing

### Processing Order
1. `InputPath` — select subset of raw input
2. `Parameters` — construct new input (supports `.$` JSONPath references)
3. Task execution
4. `ResultSelector` — reshape task output
5. `ResultPath` — merge task output back into original input
6. `OutputPath` — select subset of combined result

### Intrinsic Functions
| Function | Description |
|---|---|
| `States.Format('template', arg1, ...)` | String formatting |
| `States.StringToJson(string)` | Parse JSON string |
| `States.JsonToString(json)` | Serialize to JSON string |
| `States.Array(val1, val2, ...)` | Create array |
| `States.ArrayPartition(array, size)` | Split array into chunks |
| `States.ArrayContains(array, value)` | Check membership |
| `States.ArrayRange(start, end, step)` | Generate numeric array |
| `States.ArrayGetItem(array, index)` | Get array element |
| `States.ArrayLength(array)` | Array length |
| `States.ArrayUnique(array)` | Deduplicate array |
| `States.Base64Encode(data)` | Base64 encode |
| `States.Base64Decode(data)` | Base64 decode |
| `States.Hash(data, algorithm)` | Hash (MD5, SHA-1, SHA-256, SHA-384, SHA-512) |
| `States.MathRandom(start, end)` | Random integer |
| `States.MathAdd(num1, num2)` | Addition |
| `States.UUID()` | Generate UUID v4 |

---

## 10. Encryption

### AWS-Owned Keys (Default)
- No configuration needed.
- AWS manages encryption transparently.

### Customer-Managed KMS Keys
- Set `encryption_type = "CUSTOMER_MANAGED_KMS_KEY"` with `kms_key_id`.
- Encrypts state machine data at rest.
- The execution role and any interacting roles need `kms:Decrypt` and `kms:GenerateDataKey` permissions.
- KMS key policy must allow Step Functions service.

### Terraform Configuration
```hcl
resource "aws_sfn_state_machine" "this" {
  encryption_configuration {
    type       = "CUSTOMER_MANAGED_KMS_KEY"
    kms_key_id = "arn:aws:kms:..."
  }
}
```

---

## 11. Observability — Logging

### Log Levels
| Level | What is logged |
|---|---|
| `ALL` | Every execution history event + state input/output (if `include_execution_data = true`) |
| `ERROR` | Only error events (TaskFailed, ExecutionFailed, etc.) |
| `FATAL` | Only fatal events (ExecutionAborted, ExecutionTimedOut) |
| `OFF` | No logging (default) |

### Log Destination
- CloudWatch Logs log group.
- Log group ARN must include `:*` suffix for Step Functions.
- Express workflows **require** logging for any visibility (no console history).

### Configuration
```hcl
resource "aws_sfn_state_machine" "this" {
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}
```

### Log Format
Structured JSON with fields like:
```json
{
  "id": "1",
  "type": "TaskStateEntered",
  "details": {
    "name": "ProcessOrder",
    "input": "{...}",
    "inputDetails": { "truncated": false }
  },
  "event_timestamp": "2025-01-01T00:00:00.000Z",
  "execution_arn": "arn:aws:states:..."
}
```

---

## 12. Observability — Metrics

### Namespace: AWS/States

### Execution-Level Metrics
| Metric | Description | Statistic |
|---|---|---|
| `ExecutionsStarted` | Executions started | Sum/Count |
| `ExecutionsSucceeded` | Completed without error | Sum |
| `ExecutionsFailed` | Failed executions | Sum |
| `ExecutionsTimedOut` | Execution-level timeout | Sum |
| `ExecutionsAborted` | Manually aborted | Sum |
| `ExecutionThrottled` | Throttled start requests | Sum |
| `ExecutionTime` | Execution duration (ms) | Average/p50/p95/p99/Max |

### Service Integration Metrics
| Metric | Description |
|---|---|
| `LambdaFunctionsScheduled` | Lambda tasks scheduled |
| `LambdaFunctionsStarted` | Lambda tasks started |
| `LambdaFunctionsSucceeded` | Lambda tasks succeeded |
| `LambdaFunctionsFailed` | Lambda tasks failed |
| `LambdaFunctionsTimedOut` | Lambda tasks timed out |
| `ServiceIntegrationsScheduled` | Non-Lambda tasks scheduled |
| `ServiceIntegrationsStarted` | Non-Lambda tasks started |
| `ServiceIntegrationsSucceeded` | Non-Lambda tasks succeeded |
| `ServiceIntegrationsFailed` | Non-Lambda tasks failed |
| `ServiceIntegrationsTimedOut` | Non-Lambda tasks timed out |

### Activity Metrics
| Metric | Description |
|---|---|
| `ActivitiesScheduled` | Activity tasks scheduled |
| `ActivitiesStarted` | Activity tasks picked up by worker |
| `ActivitiesSucceeded` | Activity tasks completed |
| `ActivitiesFailed` | Activity tasks failed |
| `ActivitiesTimedOut` | Activity tasks timed out |
| `ActivityScheduleTime` | Time waiting for worker (ms) |
| `ActivityRunTime` | Time executing at worker (ms) |
| `ActivityTime` | Total activity duration (ms) |

### Express Workflow Metrics
| Metric | Description |
|---|---|
| `ExpressExecutionMemory` | Memory consumed (bytes) |
| `ExpressExecutionBilledMemory` | Billed memory (64MB increments) |
| `ExpressExecutionBilledDuration` | Billed duration (100ms increments) |

### Dimension
All metrics use dimension: `StateMachineArn = <arn>`.

### Key Alarms to Configure
1. **ExecutionsFailed >= 1** — any workflow failure.
2. **ExecutionsTimedOut >= 1** — execution-level timeout.
3. **ExecutionThrottled > 0** — start rate exceeded.
4. **ExecutionsAborted >= 1** — someone aborted a run.
5. **ExecutionTime p95** — latency monitoring.
6. **LambdaFunctionsFailed >= 1** — Lambda integration errors.
7. **ServiceIntegrationsFailed >= 1** — AWS SDK integration errors.

---

## 13. Observability — Tracing (X-Ray)

### What It Provides
- End-to-end distributed tracing across Step Functions → Lambda → DynamoDB → etc.
- Visual service map showing service dependencies and latencies.
- Trace segments for each state transition.

### Configuration
```hcl
resource "aws_sfn_state_machine" "this" {
  tracing_configuration {
    enabled = true
  }
}
```

### IAM Requirements
- Execution role must have `AWSXRayDaemonWriteAccess` attached.
- Downstream services (Lambda, etc.) must also have X-Ray permissions for full trace propagation.

---

## 14. Express vs Standard Deep Dive

### When to Use Standard
- Long-running processes (minutes to days).
- Workflows requiring exactly-once execution.
- Human approval / wait states.
- Complex orchestration with < 25,000 events per execution.
- Debugging in AWS Console (90-day history).

### When to Use Express
- High-volume event processing (> 100K/sec possible).
- Short tasks (< 5 minutes total).
- IoT data ingestion, stream processing, API backends.
- Idempotent operations (at-least-once delivery).
- Cost-sensitive workloads (per-request + duration pricing).

### Synchronous Express
- Caller blocks until workflow completes (max 5 minutes).
- Ideal for API Gateway → Step Functions → immediate response.
- Returns execution result directly.
- At-most-once semantics (no automatic retry by Step Functions).

### Asynchronous Express
- Fire-and-forget. Returns execution ARN immediately.
- Results available only in CloudWatch Logs.
- At-least-once semantics (may re-execute in rare failure cases).

---

## 15. Concurrency & Throttling

### Standard Workflow Limits
| Limit | Default | Adjustable |
|---|---|---|
| Open executions | 1,000,000 | Yes |
| Start execution rate | 2,000/sec (burst) | Yes (via quota request) |
| State transitions/sec | 1,500/sec per account | Yes |
| State transitions per execution | 25,000 | No |

### Express Workflow Limits
| Limit | Default | Adjustable |
|---|---|---|
| Start execution rate | 100,000/sec | Yes |
| Open executions | Unlimited | N/A |
| Duration | 5 minutes | No |

### Map State Concurrency
- `MaxConcurrency`: controls parallel iterations.
- Default: 0 (unlimited, up to account limits).
- Set to a specific number to throttle and prevent downstream overload.

---

## 16. Map State & Distributed Map

### Inline Map (Standard Map)
- Iterates over a JSON array in the state input.
- Up to 40 concurrent iterations.
- All iterations share the parent execution's history event limit (25,000).

### Distributed Map
- Processes millions of items from S3 (CSV, JSON, S3 inventory).
- Each child execution is a separate Standard or Express workflow.
- Up to 10,000 concurrent child executions.
- Results written back to S3.

```json
{
  "Type": "Map",
  "ItemProcessor": {
    "ProcessorConfig": {
      "Mode": "DISTRIBUTED",
      "ExecutionType": "STANDARD"
    },
    "StartAt": "ProcessItem",
    "States": { ... }
  },
  "ItemReader": {
    "Resource": "arn:aws:states:::s3:getObject",
    "Parameters": {
      "Bucket": "my-bucket",
      "Key": "data/items.csv"
    },
    "ReaderConfig": {
      "InputType": "CSV",
      "CSVHeaderLocation": "FIRST_ROW"
    }
  },
  "ResultWriter": {
    "Resource": "arn:aws:states:::s3:putObject",
    "Parameters": {
      "Bucket": "my-bucket",
      "Prefix": "results/"
    }
  },
  "MaxConcurrency": 1000
}
```

---

## 17. Activity Tasks

### What They Are
- Allow **external workers** (EC2, ECS, on-prem) to poll for and complete tasks.
- Worker calls `GetActivityTask` → receives task → processes → calls `SendTaskSuccess`/`SendTaskFailure`.
- Useful for long-running, non-Lambda compute.

### Terraform Resource
```hcl
resource "aws_sfn_activity" "this" {
  name = "my-activity"
  tags = { ... }
}
```

### Timeouts
- `TimeoutSeconds`: max time to complete task (default: 99999999 seconds ~ 3.1 years).
- `HeartbeatSeconds`: max time between heartbeats (worker must call `SendTaskHeartbeat`).

---

## 18. Callback Pattern (waitForTaskToken)

### How It Works
1. Step Functions pauses a task and generates a unique `taskToken`.
2. Token is passed to the target service (SQS message, Lambda input, etc.).
3. External process calls `SendTaskSuccess(taskToken, output)` or `SendTaskFailure(taskToken, error, cause)` to resume.

### Use Cases
- Human approval workflows.
- External system callbacks.
- Asynchronous third-party API integrations.
- Long-polling patterns.

### Example ASL
```json
{
  "Type": "Task",
  "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
  "Parameters": {
    "QueueUrl": "https://sqs.us-east-1.amazonaws.com/123456789012/approval-queue",
    "MessageBody": {
      "Message": "Approval needed",
      "TaskToken.$": "$$.Task.Token"
    }
  },
  "TimeoutSeconds": 86400,
  "Next": "ApprovalReceived"
}
```

---

## 19. Cost Model

### Standard Workflows
| Component | Price |
|---|---|
| State transitions | $0.025 per 1,000 |
| Free tier | 4,000 transitions/month |

### Express Workflows
| Component | Price |
|---|---|
| Requests | $1.00 per 1,000,000 |
| Duration (per GB-second) | $0.00001667 |
| Memory is tiered in 64MB increments | Minimum 64MB |

### Cost Optimization Tips
- Use Express for high-volume, short tasks.
- Minimize state transitions in Standard workflows (combine Passes, use intrinsics).
- Use `ResultPath` to avoid large payloads (charged per transition for standard).
- Distributed Map: child executions are individually priced.

---

## 20. Limits & Quotas

### Key Limits (Standard)
| Resource | Limit |
|---|---|
| State machine definition size | 1 MB |
| Execution history events | 25,000 per execution |
| Input/output per state | 256 KB |
| Execution name length | 80 characters |
| Open executions per account | 1,000,000 |
| State machine count per region | 10,000 |
| State transitions per second | 1,500 (per account per region) |

### Key Limits (Express)
| Resource | Limit |
|---|---|
| State machine definition size | 1 MB |
| Duration | 5 minutes |
| Input/output per state | 256 KB |
| Payload size | 256 KB |
| Start execution rate | 100,000/sec |

---

## 21. Security Best Practices

1. **Least-privilege IAM**: Only grant permissions for specific service integrations used.
2. **Source account condition**: Use `aws:SourceAccount` in trust policy.
3. **Encryption**: Use customer-managed KMS for sensitive workflows.
4. **VPC endpoints**: Use `com.amazonaws.<region>.states` for private network access.
5. **CloudTrail**: Log all Step Functions API calls for audit.
6. **Input validation**: Validate inputs in the first state before processing.
7. **Sensitive data**: Use `logging_include_execution_data = false` to avoid logging PII.
8. **Cross-account**: Use resource policies or cross-account IAM roles carefully.

---

## 22. Terraform Full Resource Reference

### aws_sfn_state_machine
```hcl
resource "aws_sfn_state_machine" "this" {
  name       = string           # Required
  role_arn   = string           # Required
  definition = string           # Required (ASL JSON)
  type       = string           # Optional: STANDARD (default), EXPRESS
  publish    = bool             # Optional: false (default)

  logging_configuration {               # Optional
    log_destination        = string     # Log group ARN with ":*" suffix
    include_execution_data = bool       # false (default)
    level                  = string     # OFF (default), ALL, ERROR, FATAL
  }

  tracing_configuration {          # Optional
    enabled = bool                 # false (default)
  }

  encryption_configuration {       # Optional
    type                         = string  # AWS_OWNED_KEY (default), CUSTOMER_MANAGED_KMS_KEY
    kms_key_id                   = string  # Required when type = CUSTOMER_MANAGED_KMS_KEY
    kms_data_key_reuse_period_seconds = number  # Optional (60-900 seconds)
  }

  tags = map(string)               # Optional
}
```

### aws_sfn_alias
```hcl
resource "aws_sfn_alias" "this" {
  name        = string        # Required
  description = string        # Optional

  routing_configuration {                    # Required (1-2 entries)
    state_machine_version_arn = string       # Required
    weight                    = number       # Required (0-100, must sum to 100)
  }
}
```

### aws_sfn_activity
```hcl
resource "aws_sfn_activity" "this" {
  name = string         # Required
  tags = map(string)    # Optional
}
```

### Outputs Available
| Attribute | Resource | Description |
|---|---|---|
| `id` | state_machine | State machine ID |
| `arn` | state_machine | State machine ARN |
| `name` | state_machine | State machine name |
| `creation_date` | state_machine | Creation timestamp |
| `status` | state_machine | Status (ACTIVE, DELETING) |
| `state_machine_version_arn` | state_machine | Version ARN (when publish=true) |
| `revision_id` | state_machine | Current revision ID |
| `arn` | alias | Alias ARN |
| `creation_date` | alias | Alias creation timestamp |
| `arn` | activity | Activity ARN |
| `creation_date` | activity | Activity creation timestamp |
