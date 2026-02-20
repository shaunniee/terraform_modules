# =============================================================================
# Event Rules
# =============================================================================

output "event_rule_arns" {
  description = "Map of event rule ARNs keyed by '<bus_name>:<rule_name>'."
  value = {
    for key, rule in aws_cloudwatch_event_rule.this : key => rule.arn
  }
}

output "event_rule_names" {
  description = "Map of event rule names keyed by '<bus_name>:<rule_name>'."
  value = {
    for key, rule in aws_cloudwatch_event_rule.this : key => rule.name
  }
}

# =============================================================================
# Event Buses
# =============================================================================

output "event_bus_arns" {
  description = "Map of custom event bus ARNs keyed by event bus name. The 'default' bus is not included."
  value = {
    for key, bus in aws_cloudwatch_event_bus.this : key => bus.arn
  }
}

output "event_bus_names" {
  description = "Map of event bus names keyed by event bus name (includes default if used)."
  value = local.bus_name_map
}

# =============================================================================
# Targets
# =============================================================================

output "target_arns" {
  description = "Map of target ARNs keyed by '<bus_name>:<rule_name>:<target_id>'."
  value = {
    for key, target in aws_cloudwatch_event_target.this : key => target.arn
  }
}

# =============================================================================
# Lambda Permissions
# =============================================================================

output "lambda_permission_statement_ids" {
  description = "Map of Lambda permission statement IDs created for Lambda targets."
  value = {
    for key, permission in aws_lambda_permission.eventbridge_invoke : key => permission.statement_id
  }
}

# =============================================================================
# Archives
# =============================================================================

output "archive_arns" {
  description = "Map of event archive ARNs keyed by archive name."
  value = {
    for key, archive in aws_cloudwatch_event_archive.this : key => archive.arn
  }
}

# =============================================================================
# Bus Policies
# =============================================================================

output "bus_policy_ids" {
  description = "Map of event bus policy IDs keyed by bus name."
  value = {
    for key, policy in aws_cloudwatch_event_bus_policy.this : key => policy.id
  }
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

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

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================

output "cloudwatch_metric_anomaly_alarm_arns" {
  description = "Map of CloudWatch anomaly detection alarm ARNs keyed by alarm key."
  value = {
    for key, alarm in aws_cloudwatch_metric_alarm.anomaly : key => alarm.arn
  }
}

output "cloudwatch_metric_anomaly_alarm_names" {
  description = "Map of CloudWatch anomaly detection alarm names keyed by alarm key."
  value = {
    for key, alarm in aws_cloudwatch_metric_alarm.anomaly : key => alarm.alarm_name
  }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard (null if not created)."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_arn, null)
}

# =============================================================================
# Event Logging
# =============================================================================

output "event_log_group_names" {
  description = "Map of CloudWatch Logs log group names for event logging, keyed by bus name."
  value = {
    for key, lg in aws_cloudwatch_log_group.event_logs : key => lg.name
  }
}

output "event_log_group_arns" {
  description = "Map of CloudWatch Logs log group ARNs for event logging, keyed by bus name."
  value = {
    for key, lg in aws_cloudwatch_log_group.event_logs : key => lg.arn
  }
}

output "event_log_rule_arns" {
  description = "Map of catch-all logging rule ARNs, keyed by bus name."
  value = {
    for key, rule in aws_cloudwatch_event_rule.event_logs : key => rule.arn
  }
}

# =============================================================================
# Connections
# =============================================================================

output "connection_arns" {
  description = "Map of EventBridge connection ARNs keyed by connection name."
  value = {
    for key, conn in aws_cloudwatch_event_connection.this : key => conn.arn
  }
}

output "connection_names" {
  description = "Map of EventBridge connection names keyed by connection name."
  value = {
    for key, conn in aws_cloudwatch_event_connection.this : key => conn.name
  }
}

# =============================================================================
# API Destinations
# =============================================================================

output "api_destination_arns" {
  description = "Map of API destination ARNs keyed by destination name."
  value = {
    for key, dest in aws_cloudwatch_event_api_destination.this : key => dest.arn
  }
}

output "api_destination_names" {
  description = "Map of API destination names keyed by destination name."
  value = {
    for key, dest in aws_cloudwatch_event_api_destination.this : key => dest.name
  }
}

# =============================================================================
# Schema Registries
# =============================================================================

output "schema_registry_arns" {
  description = "Map of schema registry ARNs keyed by registry name."
  value = {
    for key, reg in aws_schemas_registry.this : key => reg.arn
  }
}

output "schema_registry_names" {
  description = "Map of schema registry names keyed by registry name."
  value = {
    for key, reg in aws_schemas_registry.this : key => reg.name
  }
}

# =============================================================================
# Schemas
# =============================================================================

output "schema_arns" {
  description = "Map of schema ARNs keyed by schema name."
  value = {
    for key, schema in aws_schemas_schema.this : key => schema.arn
  }
}

output "schema_versions" {
  description = "Map of latest schema version numbers keyed by schema name."
  value = {
    for key, schema in aws_schemas_schema.this : key => schema.version
  }
}

# =============================================================================
# Schema Discoverers
# =============================================================================

output "schema_discoverer_ids" {
  description = "Map of schema discoverer IDs keyed by discoverer name."
  value = {
    for key, disc in aws_schemas_discoverer.this : key => disc.id
  }
}

output "schema_discoverer_arns" {
  description = "Map of schema discoverer ARNs keyed by discoverer name."
  value = {
    for key, disc in aws_schemas_discoverer.this : key => disc.arn
  }
}

# =============================================================================
# Observability summary
# =============================================================================

output "observability" {
  description = "Summary of observability configuration."
  value = {
    enabled                    = local.observability_enabled
    total_alarms_created       = length(aws_cloudwatch_metric_alarm.this) + length(aws_cloudwatch_metric_alarm.dlq) + length(aws_cloudwatch_metric_alarm.anomaly)
    default_alarms_created     = length(local.default_per_rule_alarms) + length(local.default_bus_level_alarms) + length(local.default_dropped_events_alarms)
    anomaly_alarms_created     = length(aws_cloudwatch_metric_alarm.anomaly)
    dashboard_enabled          = local.dashboard_enabled
    event_logging_enabled      = local.event_logging_enabled
    event_log_groups_created   = length(aws_cloudwatch_log_group.event_logs)
  }
}

# =============================================================================
# Pipes
# =============================================================================

output "pipe_arns" {
  description = "Map of EventBridge Pipe ARNs by name."
  value       = { for k, v in aws_pipes_pipe.this : k => v.arn }
}

output "pipe_names" {
  description = "Map of EventBridge Pipe names by key."
  value       = { for k, v in aws_pipes_pipe.this : k => v.name }
}

output "pipe_states" {
  description = "Map of EventBridge Pipe desired states by key."
  value       = { for k, v in aws_pipes_pipe.this : k => v.desired_state }
}
