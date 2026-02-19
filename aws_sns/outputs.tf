output "sns_topic_arn" {
  value = aws_sns_topic.this.arn
}

output "sns_topic_name" {
  value = aws_sns_topic.this.name
}