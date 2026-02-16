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
