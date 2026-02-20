# AWS SNS Module — Usage Guide

Production-grade SNS topic module with map-based subscriptions, encryption by default,
FIFO support, filter policies, DLQ redrive, and full observability (alarms + dashboard).

---

## Table of Contents

1. [Basic Topic](#1-basic-topic)
2. [FIFO Topic](#2-fifo-topic)
3. [Subscriptions with Filters](#3-subscriptions-with-filters)
4. [Custom KMS Encryption](#4-custom-kms-encryption)
5. [Topic Policy](#5-topic-policy)
6. [Observability](#6-observability)
7. [Full Kitchen Sink](#7-full-kitchen-sink)
8. [Variable Reference](#variable-reference)
9. [Outputs Reference](#outputs-reference)
10. [Validation Rules](#validation-rules)
11. [Default Alarms](#default-alarms)
12. [Dashboard Widgets](#dashboard-widgets)
13. [Best Practices](#best-practices)

---

## 1. Basic Topic

```hcl
module "notifications" {
  source = "../aws_sns"

  name         = "order-notifications"
  display_name = "Order Notifications"

  tags = {
    Environment = "production"
    Team        = "orders"
  }
}
```

> Encryption is enabled by default using the AWS-managed key (`alias/aws/sns`).

---

## 2. FIFO Topic

```hcl
module "fifo_events" {
  source = "../aws_sns"

  name       = "payment-events"
  fifo_topic = true

  # Content-based deduplication (uses SHA-256 of message body)
  content_based_deduplication = true

  tags = {
    Environment = "production"
  }
}
```

> The `.fifo` suffix is appended automatically. No need to include it in the name.

---

## 3. Subscriptions with Filters

```hcl
module "order_topic" {
  source = "../aws_sns"

  name = "order-updates"

  subscriptions = {
    # SQS queue — receives all messages
    fulfillment_queue = {
      protocol = "sqs"
      endpoint = "arn:aws:sqs:us-east-1:123456789012:fulfillment-queue"
    }

    # Lambda — only receives "order.completed" events
    analytics_lambda = {
      protocol = "lambda"
      endpoint = "arn:aws:lambda:us-east-1:123456789012:function:analytics"
      filter_policy = jsonencode({
        event_type = ["order.completed"]
      })
      filter_policy_scope = "MessageAttributes"
    }

    # Email — human notification
    ops_email = {
      protocol = "email"
      endpoint = "ops-team@example.com"
    }

    # HTTPS webhook with raw delivery
    webhook = {
      protocol             = "https"
      endpoint             = "https://api.example.com/webhooks/orders"
      raw_message_delivery = true
    }

    # SQS with DLQ for failed deliveries
    billing_queue = {
      protocol = "sqs"
      endpoint = "arn:aws:sqs:us-east-1:123456789012:billing-queue"
      redrive_policy = jsonencode({
        deadLetterTargetArn = "arn:aws:sqs:us-east-1:123456789012:billing-dlq"
      })
    }

    # Firehose (requires role ARN)
    data_lake = {
      protocol              = "firehose"
      endpoint              = "arn:aws:firehose:us-east-1:123456789012:deliverystream/orders"
      subscription_role_arn = "arn:aws:iam::123456789012:role/sns-firehose-role"
    }
  }

  tags = {
    Environment = "production"
  }
}
```

> **Key**: Subscriptions use a **map** (not a list). Keys are stable identifiers — reordering or
> adding/removing entries does not destroy other subscriptions.

---

## 4. Custom KMS Encryption

```hcl
module "encrypted_topic" {
  source = "../aws_sns"

  name              = "sensitive-data"
  kms_master_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-abcd-1234-abcd-123456789012"

  tags = {
    Environment = "production"
  }
}
```

To disable encryption entirely:

```hcl
module "unencrypted_topic" {
  source = "../aws_sns"

  name              = "public-announcements"
  kms_master_key_id = null

  tags = {
    Environment = "staging"
  }
}
```

---

## 5. Topic Policy

```hcl
module "cross_account_topic" {
  source = "../aws_sns"

  name = "cross-account-events"

  topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCrossAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::111111111111:root" }
        Action    = "SNS:Publish"
        Resource  = "*"
      }
    ]
  })

  tags = {
    Environment = "production"
  }
}
```

---

## 6. Observability

### Default Alarms Only

```hcl
module "monitored_topic" {
  source = "../aws_sns"

  name = "critical-alerts"

  observability = {
    enabled = true

    # Override thresholds
    failed_notifications_threshold = 5

    # Alarm action (e.g., PagerDuty SNS topic)
    default_alarm_actions = ["arn:aws:sns:us-east-1:123456789012:pagerduty"]
  }

  tags = {
    Environment = "production"
  }
}
```

### Custom Alarms

```hcl
module "custom_alarms_topic" {
  source = "../aws_sns"

  name = "order-events"

  observability = {
    enabled = true
  }

  cloudwatch_metric_alarms = {
    # Override the default failed_notifications alarm
    failed_notifications = {
      metric_name         = "NumberOfNotificationsFailed"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 10
      evaluation_periods  = 3
      period              = 60
      statistic           = "Sum"
      alarm_description   = "Custom: high failure rate on order-events topic."
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:pagerduty"]
    }

    # Additional custom alarm
    low_throughput = {
      metric_name         = "NumberOfMessagesPublished"
      comparison_operator = "LessThanThreshold"
      threshold           = 100
      evaluation_periods  = 6
      period              = 300
      statistic           = "Sum"
      treat_missing_data  = "breaching"
      alarm_description   = "Published message count dropped below 100 in 30 minutes."
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-alerts"]
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### Dashboard Only (No Alarms)

```hcl
module "dashboard_only" {
  source = "../aws_sns"

  name = "internal-events"

  observability = {
    enabled               = true
    enable_default_alarms = false
    enable_dashboard      = true
  }

  tags = {
    Environment = "staging"
  }
}
```

---

## 7. Full Kitchen Sink

```hcl
module "full_sns" {
  source = "../aws_sns"

  # Identity
  name         = "payment-events"
  display_name = "Payment Events"
  fifo_topic   = true

  # FIFO
  content_based_deduplication = true

  # Encryption
  kms_master_key_id = "arn:aws:kms:us-east-1:123456789012:key/my-key"

  # Topic policy
  topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = "*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:::my-bucket"
          }
        }
      }
    ]
  })

  # Delivery policy (HTTP retry behavior)
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numRetries         = 3
        numMaxDelayRetries = 0
        numNoDelayRetries  = 0
        backoffFunction    = "linear"
      }
      disableSubscriptionOverrides = false
    }
  })

  # Data protection
  data_protection_policy = jsonencode({
    Name        = "payment-data-protection"
    Description = "Detect and mask credit card numbers"
    Version     = "2021-06-01"
    Statement = [
      {
        Sid            = "DetectCreditCard"
        DataDirection  = "Inbound"
        Principal      = ["*"]
        DataIdentifier = ["arn:aws:dataprotection::aws:data-identifier/CreditCardNumber"]
        Operation = {
          Deny = {}
        }
      }
    ]
  })

  # Subscriptions
  subscriptions = {
    payment_processor = {
      protocol             = "sqs"
      endpoint             = "arn:aws:sqs:us-east-1:123456789012:payment-processor.fifo"
      raw_message_delivery = true
      filter_policy = jsonencode({
        event_type = ["payment.completed", "payment.refunded"]
      })
      redrive_policy = jsonencode({
        deadLetterTargetArn = "arn:aws:sqs:us-east-1:123456789012:payment-dlq.fifo"
      })
    }

    audit_lambda = {
      protocol = "lambda"
      endpoint = "arn:aws:lambda:us-east-1:123456789012:function:payment-audit"
    }
  }

  # Observability
  observability = {
    enabled                        = true
    failed_notifications_threshold = 3
    default_alarm_actions          = ["arn:aws:sns:us-east-1:123456789012:ops-pagerduty"]
    default_ok_actions             = ["arn:aws:sns:us-east-1:123456789012:ops-resolved"]
  }

  cloudwatch_metric_alarms = {
    zero_publishes = {
      metric_name         = "NumberOfMessagesPublished"
      comparison_operator = "LessThanOrEqualToThreshold"
      threshold           = 0
      evaluation_periods  = 6
      period              = 300
      statistic           = "Sum"
      treat_missing_data  = "breaching"
      alarm_description   = "No messages published to payment-events for 30 minutes."
      alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:ops-pagerduty"]
    }
  }

  tags = {
    Environment = "production"
    Team        = "payments"
    CostCenter  = "CC-1234"
  }
}
```

---

## Variable Reference

| Variable | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — (required) | Topic name. `.fifo` suffix added automatically for FIFO topics. |
| `display_name` | `string` | `null` | Display name (shown in email "From" field). |
| `fifo_topic` | `bool` | `false` | Whether to create a FIFO topic. |
| `content_based_deduplication` | `bool` | `false` | Enable content-based deduplication (FIFO only). |
| `kms_master_key_id` | `string` | `"alias/aws/sns"` | KMS key for encryption. `null` to disable. |
| `delivery_policy` | `string` | `null` | JSON delivery policy for HTTP/S retry behavior. |
| `topic_policy` | `string` | `null` | IAM policy document (JSON) for the topic. |
| `data_protection_policy` | `string` | `null` | JSON data protection policy for PII detection. |
| `archive_policy` | `string` | `null` | JSON archive policy (FIFO only). |
| `subscriptions` | `map(object)` | `{}` | Map of subscriptions. See [Subscriptions](#3-subscriptions-with-filters). |
| `observability` | `object` | `{}` | Observability config. See [Observability](#6-observability). |
| `cloudwatch_metric_alarms` | `map(object)` | `{}` | Custom CloudWatch alarms. See [Custom Alarms](#custom-alarms). |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |

### Subscription Object Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `protocol` | `string` | — (required) | `email`, `email-json`, `sqs`, `lambda`, `http`, `https`, `sms`, `application`, `firehose` |
| `endpoint` | `string` | — (required) | Target endpoint (email, ARN, URL, phone number). |
| `raw_message_delivery` | `bool` | `false` | Send raw message (SQS, HTTP/S, Firehose only). |
| `filter_policy` | `string` | `null` | JSON filter policy. |
| `filter_policy_scope` | `string` | `"MessageAttributes"` | `MessageAttributes` or `MessageBody`. |
| `redrive_policy` | `string` | `null` | JSON redrive policy with `deadLetterTargetArn`. |
| `subscription_role_arn` | `string` | `null` | IAM role ARN (required for Firehose). |
| `delivery_policy` | `string` | `null` | Per-subscription JSON delivery policy. |
| `confirmation_timeout_in_minutes` | `number` | `1` | Confirmation timeout (1–10080). |
| `endpoint_auto_confirms` | `bool` | `false` | Auto-confirm HTTP/S subscriptions. |

---

## Outputs Reference

| Output | Description |
|---|---|
| `topic_arn` | ARN of the SNS topic |
| `topic_id` | ID (ARN) of the SNS topic |
| `topic_name` | Name of the topic (includes `.fifo` suffix) |
| `topic_owner` | AWS account ID of the topic owner |
| `subscription_arns` | Map of subscription key → ARN |
| `subscription_ids` | Map of subscription key → ID |
| `subscription_count` | Number of subscriptions created |
| `cloudwatch_alarm_arns` | Map of alarm key → ARN |
| `cloudwatch_alarm_names` | Map of alarm key → alarm name |
| `dashboard_arn` | CloudWatch dashboard ARN (null if disabled) |
| `dashboard_name` | CloudWatch dashboard name (null if disabled) |
| `observability_summary` | Summary object with alarm count, keys, dashboard name |

---

## Validation Rules

This module includes **30+ validation rules** that catch misconfigurations at `terraform plan` time:

### Topic-Level
| # | Rule | Error |
|---|---|---|
| 1 | `name` length 1–251 chars | Leaves room for `.fifo` suffix under 256-char limit |
| 2 | `name` matches `[a-zA-Z0-9_-]+` | Only alphanumeric, hyphens, underscores |
| 3 | `kms_master_key_id` non-empty when set | Prevents empty string encryption config |
| 4 | `delivery_policy` valid JSON | Catches malformed JSON |
| 5 | `topic_policy` valid JSON | Catches malformed JSON |
| 6 | `data_protection_policy` valid JSON | Catches malformed JSON |
| 7 | `archive_policy` valid JSON | Catches malformed JSON |

### FIFO Cross-Cutting
| # | Rule | Error |
|---|---|---|
| 8 | `content_based_deduplication` requires `fifo_topic = true` | Lifecycle precondition on topic resource |
| 9 | `archive_policy` requires `fifo_topic = true` | Lifecycle precondition on topic resource |

### Subscription-Level
| # | Rule | Error |
|---|---|---|
| 10 | `protocol` must be valid enum | Only 9 allowed protocols |
| 11 | `endpoint` must be non-empty | Catches blank endpoints |
| 12 | `filter_policy` valid JSON | Catches malformed JSON |
| 13 | `filter_policy_scope` must be `MessageAttributes` or `MessageBody` | Prevents invalid scope |
| 14 | `redrive_policy` valid JSON | Catches malformed JSON |
| 15 | `subscription_role_arn` must be ARN format | Validates IAM role format |
| 16 | Firehose requires `subscription_role_arn` | Prevents missing role |
| 17 | `delivery_policy` valid JSON | Per-subscription policy validation |
| 18 | HTTP/S endpoint must start with `http://` or `https://` | URL format check |
| 19 | SQS/Lambda/Firehose/Application endpoint must be ARN | ARN format check |
| 20 | `confirmation_timeout_in_minutes` must be 1–10080 | AWS API range |
| 21 | `raw_message_delivery` only for SQS/HTTP/S/Firehose | Protocol compatibility (lifecycle precondition) |
| 32 | `display_name` length <= 256 | AWS max; keep <= 100 for SMS |

### Observability
| # | Rule | Error |
|---|---|---|
| 22 | `default_alarm_actions` must be ARNs | Validates action ARN format |
| 23 | `default_ok_actions` must be ARNs | Validates action ARN format |
| 24 | `default_insufficient_data_actions` must be ARNs | Validates action ARN format |
| 25 | `failed_notifications_threshold` >= 1 | Positive threshold |
| 26 | `sms_success_rate_threshold` 0.0–1.0 | Valid percentage range |

### Custom Alarm-Level
| # | Rule | Error |
|---|---|---|
| 27 | `comparison_operator` must be valid CW operator | 7 valid operators |
| 28 | `treat_missing_data` must be valid | 4 valid values |
| 29 | `statistic` / `extended_statistic` mutually exclusive | At least one must be set |
| 30 | `evaluation_periods` >= 1 | Positive periods |
| 31 | `period` >= 10 | Minimum CW period |

---

## Default Alarms

When `observability.enabled = true` and `observability.enable_default_alarms = true` (default):

| Alarm Key | Metric | Threshold | Condition | Notes |
|---|---|---|---|---|
| `failed_notifications` | `NumberOfNotificationsFailed` | `>= 1` (configurable) | Sum over 5 min, 1 eval period | Fires immediately on any failure |
| `sms_success_rate` | `SMSSuccessRate` | `< 0.9` (configurable) | Avg over 5 min, 2 eval periods | Only created if subscriptions include SMS protocol |
| `zero_publishes` | `NumberOfMessagesPublished` | `<= 0` | Sum over 5 min, 6 eval periods (30 min) | Opt-in via `enable_zero_publishes_alarm = true`. Detects dead producers. |

> **Tip**: Override any default alarm by providing a custom alarm with the same key in `cloudwatch_metric_alarms`.

---

## Dashboard Widgets

When `observability.enabled = true` and `observability.enable_dashboard = true` (default):

| Row | Widget | Metric | Stat |
|---|---|---|---|
| 1 | Messages Published | `NumberOfMessagesPublished` | Sum |
| 1 | Notifications Failed | `NumberOfNotificationsFailed` | Sum |
| 2 | Notifications Delivered | `NumberOfNotificationsDelivered` | Sum |
| 2 | Notifications Filtered Out | `NumberOfNotificationsFilteredOut` | Sum |
| 3 | Publish Size | `PublishSize` | Average |
| 3 | SMS Success Rate | `SMSSuccessRate` | Average |
| 4 | Filtered Out — No Msg Attrs | `...FilteredOut-NoMessageAttributes` | Sum |
| 4 | Filtered Out — Invalid Attrs | `...FilteredOut-InvalidAttributes` | Sum |
| 4 | Filtered Out — Invalid Body | `...FilteredOut-InvalidMessageBody` | Sum |
| 5 | Redriven to DLQ | `NumberOfNotificationsRedrivenToDlq` | Sum |
| 5 | Failed to Redrive | `NumberOfNotificationsFailedToRedriveToDlq` | Sum |

**11 widgets** across 5 rows covering publish throughput, delivery failures, filter-out breakdowns, and DLQ redrive health.

---

## Best Practices

1. **Encryption**: The module defaults to the AWS-managed SNS key (`alias/aws/sns`). For compliance workloads, use a customer-managed KMS key.

2. **Map-based subscriptions**: Always use descriptive keys like `billing_queue` or `ops_email`. Keys are for_each identifiers — adding, removing, or reordering entries is safe.

3. **Filter policies**: Use `filter_policy_scope = "MessageBody"` for payload-based filtering (requires JSON message bodies). The default `MessageAttributes` is more efficient.

4. **Subscription DLQ**: Configure `redrive_policy` on individual subscriptions to capture failed deliveries. The DLQ must be an SQS queue and have an appropriate policy allowing SNS to send messages.

5. **FIFO ordering**: FIFO topics guarantee ordering per `MessageGroupId`. Use `content_based_deduplication = true` to avoid providing a `MessageDeduplicationId` on every publish.

6. **Data protection**: Use `data_protection_policy` to detect and block PII (credit card numbers, SSNs) from being published to the topic.

7. **Topic policy**: Use `topic_policy` to grant cross-account publish access or allow AWS services (S3/EventBridge/CloudWatch) to publish.

8. **Observability**: Enable `observability.enabled = true` for production topics. The `failed_notifications` alarm fires immediately (1 eval period) to catch delivery issues fast.

9. **Custom alarms**: Use the same key as a default alarm to override it. This lets you customize thresholds while keeping the default as a baseline.

10. **SMS topics**: For production SMS, set `sms_success_rate_threshold` >= 0.95 and monitor the dashboard for delivery rate degradation.
