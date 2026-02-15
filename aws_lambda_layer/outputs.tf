output "layer_name" {
  description = "Layer name."
  value       = aws_lambda_layer_version.this.layer_name
}

output "layer_version" {
  description = "Published layer version number."
  value       = aws_lambda_layer_version.this.version
}

output "layer_arn" {
  description = "Versioned layer ARN."
  value       = aws_lambda_layer_version.this.arn
}

output "layer_version_arn" {
  description = "Version-specific layer ARN (same as layer_arn)."
  value       = aws_lambda_layer_version.this.arn
}

output "layer_source_code_size" {
  description = "Layer package size in bytes."
  value       = aws_lambda_layer_version.this.source_code_size
}
