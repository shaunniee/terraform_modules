output "table_name" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.this.name
}

output "table_id" {
  description = "DynamoDB table ID."
  value       = aws_dynamodb_table.this.id
}

output "table_arn" {
  description = "DynamoDB table ARN."
  value       = aws_dynamodb_table.this.arn
}

output "table_stream_arn" {
  description = "DynamoDB stream ARN when streams are enabled, else null."
  value       = aws_dynamodb_table.this.stream_arn
}

output "table_stream_label" {
  description = "DynamoDB stream label when streams are enabled, else null."
  value       = aws_dynamodb_table.this.stream_label
}

output "global_secondary_index_names" {
  description = "Configured global secondary index names."
  value       = [for g in var.global_secondary_indexes : g.name]
}

output "local_secondary_index_names" {
  description = "Configured local secondary index names."
  value       = [for l in var.local_secondary_indexes : l.name]
}

output "configured_replica_regions" {
  description = "Configured DynamoDB global table replica regions."
  value       = [for r in var.replicas : r.region_name]
}

output "replica_regions" {
  description = "Replica regions reported by AWS for the table."
  value       = [for r in aws_dynamodb_table.this.replica : r.region_name]
}

output "cloudwatch_metric_alarm_arns" {
  description = "Map of CloudWatch metric alarm ARNs keyed by cloudwatch_metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb : k => v.arn }
}

output "cloudwatch_metric_alarm_names" {
  description = "Map of CloudWatch metric alarm names keyed by cloudwatch_metric_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb : k => v.alarm_name }
}

output "cloudwatch_metric_anomaly_alarm_arns" {
  description = "Map of CloudWatch anomaly alarm ARNs keyed by cloudwatch_metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_anomaly : k => v.arn }
}

output "cloudwatch_metric_anomaly_alarm_names" {
  description = "Map of CloudWatch anomaly alarm names keyed by cloudwatch_metric_anomaly_alarms key."
  value       = { for k, v in aws_cloudwatch_metric_alarm.dynamodb_anomaly : k => v.alarm_name }
}

output "contributor_insights_table_enabled" {
  description = "Whether Contributor Insights is enabled for the table."
  value       = length(aws_dynamodb_contributor_insights.table) > 0
}

output "contributor_insights_gsi_names" {
  description = "GSI names with Contributor Insights enabled."
  value       = [for _, v in aws_dynamodb_contributor_insights.gsi : v.index_name]
}

output "cloudtrail_data_events_trail_arn" {
  description = "CloudTrail ARN when cloudtrail_data_events is enabled, else null."
  value       = try(aws_cloudtrail.dynamodb_data_events[0].arn, null)
}

output "cloudtrail_data_events_trail_name" {
  description = "CloudTrail name when cloudtrail_data_events is enabled, else null."
  value       = try(aws_cloudtrail.dynamodb_data_events[0].name, null)
}

output "cloudtrail_data_events_cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name used by CloudTrail data events when CloudWatch Logs delivery is enabled."
  value       = try(local.cloudtrail_logs_enabled, false) ? try(aws_cloudwatch_log_group.cloudtrail_data_events[0].name, local.cloudtrail_log_group_name) : null
}

output "cloudtrail_data_events_cloudwatch_logs_role_arn" {
  description = "IAM role ARN used by CloudTrail to publish into CloudWatch Logs when enabled."
  value       = try(aws_iam_role.cloudtrail_to_cwlogs[0].arn, try(local.effective_cloudtrail_data_events.cloud_watch_logs_role_arn, null))
}
