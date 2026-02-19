# aws_eventbridge module usage

Reusable EventBridge module that supports:
- multiple event buses
- rules with `event_pattern` or `schedule_expression`
- multiple targets per rule
- target dead-letter queue and retry policy
- optional automatic Lambda invoke permissions
- optional CloudWatch metric alarms
- optional DLQ-specific CloudWatch metric alarms

## Basic example

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  event_buses = [
    {
      name = "app-events"
      tags = {
        Environment = "dev"
      }
      rules = [
        {
          name          = "nightly-job"
          description   = "Runs nightly"
          is_enabled    = true
          schedule_expression = "cron(0 2 * * ? *)"
          targets = [
            {
              id   = "nightly-lambda"
              arn  = "arn:aws:lambda:us-east-1:123456789012:function:nightly-job"
              dead_letter_arn = "arn:aws:sqs:us-east-1:123456789012:nightly-job-dlq"
            }
          ]
        }
      ]
    }
  ]

  cloudwatch_metric_alarms = {
    failed_invocations_nightly_job = {
      rule_key            = "app-events:nightly-job"
      metric_name         = "FailedInvocations"
      statistic           = "Sum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    throttled_rules = {
      metric_name         = "ThrottledRules"
      statistic           = "Sum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      dimensions = {
        EventBusName = "app-events"
      }
      treat_missing_data = "notBreaching"
      alarm_actions      = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    invocations_spike = {
      rule_key            = "app-events:nightly-job"
      metric_name         = "Invocations"
      statistic           = "Sum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 1000
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    dead_letter_invocations = {
      metric_name         = "InvocationsSentToDLQ"
      statistic           = "Sum"
      period              = 60
      evaluation_periods  = 5
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      dimensions = {
        EventBusName = "app-events"
      }
      treat_missing_data = "notBreaching"
      alarm_actions      = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }

  dlq_cloudwatch_metric_alarms = {
    dlq_visible_messages = {
      target_key           = "app-events:nightly-job:nightly-lambda"
      metric_name          = "ApproximateNumberOfMessagesVisible"
      statistic            = "Maximum"
      period               = 60
      evaluation_periods   = 5
      threshold            = 1
      comparison_operator  = "GreaterThanOrEqualToThreshold"
      treat_missing_data   = "notBreaching"
      alarm_actions        = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }

    dlq_oldest_message_age = {
      target_key           = "app-events:nightly-job:nightly-lambda"
      metric_name          = "ApproximateAgeOfOldestMessage"
      statistic            = "Maximum"
      period               = 60
      evaluation_periods   = 5
      threshold            = 300
      comparison_operator  = "GreaterThanOrEqualToThreshold"
      treat_missing_data   = "notBreaching"
      alarm_actions        = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }
}
```

## Advanced example

```hcl
module "eventbridge" {
  source = "../aws_eventbridge"

  lambda_permission_statement_id_prefix = "AllowFromEventBridge"

  event_buses = [
    {
      name = "blog-events"
      rules = [
        {
          name          = "post-created"
          description   = "Handle post created events"
          event_pattern = jsonencode({
            source      = ["blog.admin"]
            detail-type = ["post.created"]
          })
          targets = [
            {
              id   = "notify-lambda"
              arn  = "arn:aws:lambda:us-east-1:123456789012:function:notify-post-created"

              retry_policy = {
                maximum_event_age_in_seconds = 3600
                maximum_retry_attempts       = 12
              }

              dead_letter_arn = "arn:aws:sqs:us-east-1:123456789012:eventbridge-dlq"

              # Optional overrides (normally not needed)
              # create_lambda_permission      = true
              # lambda_permission_statement_id = "AllowFromPostCreatedRule"
              # lambda_function_name           = "notify-post-created"
              # lambda_qualifier               = "live"
            },
            {
              id       = "audit-queue"
              arn      = "arn:aws:sqs:us-east-1:123456789012:audit-queue"
              role_arn = "arn:aws:iam::123456789012:role/eventbridge-to-sqs"
            }
          ]
        }
      ]
    }
  ]
}
```

## Input reference

- `event_buses`: list of buses to create.
- `event_buses[].name`: Event bus name (must be unique and non-empty).
- `event_buses[].tags`: tags for the bus.
- `event_buses[].rules`: list of rules for that bus.
- `event_buses[].rules[].name`: rule name (unique per bus).
- `event_buses[].rules[].description`: optional rule description.
- `event_buses[].rules[].is_enabled`: enable/disable the rule.
- `event_buses[].rules[].event_pattern`: JSON event pattern string.
- `event_buses[].rules[].schedule_expression`: schedule in `rate(...)` or `cron(...)` format.
- `event_buses[].rules[].targets`: targets for the rule.
- `event_buses[].rules[].targets[].id`: target ID (unique per rule).
- `event_buses[].rules[].targets[].arn`: target ARN.
- `event_buses[].rules[].targets[].input`: static JSON input for the target.
- `event_buses[].rules[].targets[].input_path`: JSONPath from incoming event; cannot be used with `input`.
- `event_buses[].rules[].targets[].role_arn`: IAM role EventBridge assumes for target invocation.
- `event_buses[].rules[].targets[].dead_letter_arn`: SQS DLQ ARN for failed deliveries.
- `event_buses[].rules[].targets[].retry_policy.maximum_event_age_in_seconds`: max event age in seconds (60-86400).
- `event_buses[].rules[].targets[].retry_policy.maximum_retry_attempts`: max retries (0-185).
- `event_buses[].rules[].targets[].create_lambda_permission`: when true and target is Lambda ARN, module creates `aws_lambda_permission`.
- `event_buses[].rules[].targets[].lambda_permission_statement_id`: optional custom statement ID for Lambda permission.
- `event_buses[].rules[].targets[].lambda_function_name`: optional Lambda function name/ARN override used by permission resource.
- `event_buses[].rules[].targets[].lambda_qualifier`: optional Lambda version/alias qualifier for permission.
- `lambda_permission_statement_id_prefix`: prefix for generated Lambda permission statement IDs.
- `cloudwatch_metric_alarms`: map of CloudWatch metric alarms to create.
- `cloudwatch_metric_alarms[].rule_key`: optional `<bus_name>:<rule_name>`; auto-sets `EventBusName` and `RuleName` dimensions.
- `cloudwatch_metric_alarms[].event_bus_name`: optional EventBusName default dimension.
- `cloudwatch_metric_alarms[].dimensions`: optional explicit dimensions merged over defaults.
- `cloudwatch_metric_alarms[].metric_name`: CloudWatch metric (for example `FailedInvocations`, `Invocations`, `ThrottledRules`, `TriggeredRules`).
- `cloudwatch_metric_alarms[].alarm_actions|ok_actions|insufficient_data_actions`: optional SNS/action ARNs.
- `dlq_cloudwatch_metric_alarms`: map of DLQ CloudWatch metric alarms (AWS/SQS namespace by default).
- `dlq_cloudwatch_metric_alarms[].target_key`: optional `<bus_name>:<rule_name>:<target_id>` for a Lambda target with `dead_letter_arn`; auto-resolves DLQ queue name.
- `dlq_cloudwatch_metric_alarms[].dead_letter_arn`: optional SQS DLQ ARN used to resolve queue name.
- `dlq_cloudwatch_metric_alarms[].queue_name`: optional explicit queue name for `QueueName` dimension.
- `dlq_cloudwatch_metric_alarms[].metric_name`: common values include `ApproximateNumberOfMessagesVisible`, `ApproximateAgeOfOldestMessage`, `NumberOfMessagesSent`.

## DLQ logging note

SQS DLQs expose CloudWatch metrics natively, but message-level logs are not emitted to CloudWatch Logs automatically.
For DLQ logging, attach a DLQ consumer (Lambda or worker) and log payloads there, then create log-based metrics/alarms from that consumer log group.

## Outputs

- `event_bus_arn`: map of bus ARNs by bus name.
- `event_arn`: map of rule ARNs by `<bus_name>:<rule_name>`.
- `target_arns`: map of target ARNs by `<bus_name>:<rule_name>:<target_id>`.
- `lambda_permission_statement_ids`: map of generated Lambda permission statement IDs by target key.
- `cloudwatch_metric_alarm_arns`: map of alarm ARNs by alarm key.
- `cloudwatch_metric_alarm_names`: map of alarm names by alarm key.
- `dlq_cloudwatch_metric_alarm_arns`: map of DLQ alarm ARNs by alarm key.
- `dlq_cloudwatch_metric_alarm_names`: map of DLQ alarm names by alarm key.
