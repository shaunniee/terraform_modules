# =============================================================================
# AWS CI/CD Module - Outputs
# =============================================================================

# =============================================================================
# Artifact Bucket
# =============================================================================

output "artifact_bucket_arn" {
  description = "The ARN of the artifact S3 bucket."
  value       = try(aws_s3_bucket.artifacts[0].arn, null)
}

output "artifact_bucket_name" {
  description = "The name of the artifact S3 bucket."
  value       = local.artifact_bucket_name
}

output "artifact_bucket_id" {
  description = "The ID of the artifact S3 bucket."
  value       = try(aws_s3_bucket.artifacts[0].id, null)
}

# =============================================================================
# KMS Key
# =============================================================================

output "kms_key_arn" {
  description = "The ARN of the KMS key used for CI/CD encryption."
  value       = try(aws_kms_key.this[0].arn, null)
}

output "kms_key_id" {
  description = "The ID of the KMS key used for CI/CD encryption."
  value       = try(aws_kms_key.this[0].key_id, null)
}

output "kms_key_alias" {
  description = "The alias of the KMS key."
  value       = try(aws_kms_alias.this[0].name, null)
}

# =============================================================================
# CodeBuild Outputs
# =============================================================================

output "codebuild_project_arns" {
  description = "Map of CodeBuild project key to project ARN."
  value       = { for k, v in module.codebuild : k => v.codebuild_project_arn }
}

output "codebuild_project_names" {
  description = "Map of CodeBuild project key to project name."
  value       = { for k, v in module.codebuild : k => v.codebuild_project_name }
}

output "codebuild_role_arns" {
  description = "Map of CodeBuild project key to IAM role ARN."
  value       = { for k, v in module.codebuild : k => v.codebuild_role_arn }
}

output "codebuild_role_names" {
  description = "Map of CodeBuild project key to IAM role name (null if external role was provided)."
  value       = { for k, v in module.codebuild : k => v.codebuild_role_name }
}

output "codebuild_badge_urls" {
  description = "Map of CodeBuild project key to badge URL."
  value       = { for k, v in module.codebuild : k => v.codebuild_badge_url }
}

# =============================================================================
# CodePipeline Outputs
# =============================================================================

output "codepipeline_arn" {
  description = "The ARN of the CodePipeline."
  value       = try(module.codepipeline[0].codepipeline_arn, null)
}

output "codepipeline_name" {
  description = "The name of the CodePipeline."
  value       = try(module.codepipeline[0].codepipeline_name, null)
}

output "codepipeline_role_arn" {
  description = "The ARN of the CodePipeline IAM role."
  value       = try(module.codepipeline[0].codepipeline_role_arn, null)
}

output "codepipeline_role_name" {
  description = "The name of the CodePipeline IAM role (null if external role was provided)."
  value       = try(module.codepipeline[0].codepipeline_role_name, null)
}

# =============================================================================
# CodeDeploy Outputs
# =============================================================================

output "codedeploy_app_arn" {
  description = "The ARN of the CodeDeploy application."
  value       = try(module.codedeploy[0].codedeploy_app_arn, null)
}

output "codedeploy_app_name" {
  description = "The name of the CodeDeploy application."
  value       = try(module.codedeploy[0].codedeploy_app_name, null)
}

output "codedeploy_deployment_group_arns" {
  description = "Map of deployment group name to ARN."
  value       = try(module.codedeploy[0].codedeploy_deployment_group_arns, {})
}

output "codedeploy_role_arn" {
  description = "The ARN of the CodeDeploy IAM role."
  value       = try(module.codedeploy[0].codedeploy_role_arn, null)
}

output "codedeploy_role_name" {
  description = "The name of the CodeDeploy IAM role (null if external role was provided)."
  value       = try(module.codedeploy[0].codedeploy_role_name, null)
}

# =============================================================================
# Observability Outputs (Aggregated)
# =============================================================================

output "codebuild_alarm_arns" {
  description = "Map of CodeBuild project key to their CloudWatch alarm ARNs."
  value       = { for k, v in module.codebuild : k => v.cloudwatch_alarm_arns }
}

output "codepipeline_alarm_arns" {
  description = "Map of CodePipeline CloudWatch alarm ARNs."
  value       = try(module.codepipeline[0].cloudwatch_alarm_arns, {})
}

output "codedeploy_alarm_arns" {
  description = "Map of CodeDeploy CloudWatch alarm ARNs."
  value       = try(module.codedeploy[0].cloudwatch_alarm_arns, {})
}
