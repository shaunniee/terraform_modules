output "event_arn" {
  description = "Map of event rule ARNs keyed by '<bus_name>:<rule_name>'."
  value = {
    for key, rule in aws_cloudwatch_event_rule.this : key => rule.arn
  }
}

output "event_bus_arn" {
  description = "Map of event bus ARNs keyed by event bus name."
  value = {
    for key, bus in aws_cloudwatch_event_bus.this : key => bus.arn
  }
}

output "target_arns" {
  description = "Map of target ARNs keyed by '<bus_name>:<rule_name>:<target_id>'."
  value = {
    for key, target in aws_cloudwatch_event_target.this : key => target.arn
  }
}

output "lambda_permission_statement_ids" {
  description = "Map of Lambda permission statement IDs created for Lambda targets."
  value = {
    for key, permission in aws_lambda_permission.eventbridge_invoke : key => permission.statement_id
  }
}

output "cloudwatch_metric_alarm_arns" {
  description = "Map of CloudWatch metric alarm ARNs keyed by alarm key."
  value = {
    for key, alarm in aws_cloudwatch_metric_alarm.this : key => alarm.arn
  }
}

output "cloudwatch_metric_alarm_names" {
  description = "Map of CloudWatch metric alarm names keyed by alarm key."
  value = {
    for key, alarm in aws_cloudwatch_metric_alarm.this : key => alarm.alarm_name
  }
}

output "dlq_cloudwatch_metric_alarm_arns" {
  description = "Map of DLQ CloudWatch metric alarm ARNs keyed by alarm key."
  value = {
    for key, alarm in aws_cloudwatch_metric_alarm.dlq : key => alarm.arn
  }
}

output "dlq_cloudwatch_metric_alarm_names" {
  description = "Map of DLQ CloudWatch metric alarm names keyed by alarm key."
  value = {
    for key, alarm in aws_cloudwatch_metric_alarm.dlq : key => alarm.alarm_name
  }
}
