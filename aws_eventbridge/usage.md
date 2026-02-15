# aws_eventbridge module usage

Reusable EventBridge module that supports:
- multiple event buses
- rules with `event_pattern` or `schedule_expression`
- multiple targets per rule
- target dead-letter queue and retry policy
- optional automatic Lambda invoke permissions

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
            }
          ]
        }
      ]
    }
  ]
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

## Outputs

- `event_bus_arn`: map of bus ARNs by bus name.
- `event_arn`: map of rule ARNs by `<bus_name>:<rule_name>`.
- `target_arns`: map of target ARNs by `<bus_name>:<rule_name>:<target_id>`.
- `lambda_permission_statement_ids`: map of generated Lambda permission statement IDs by target key.
