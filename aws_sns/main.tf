resource "aws_sns_topic" "this" {
  name         = var.topic_name
  display_name = var.topic_display_name
  fifo_topic   = var.fifo_topic
    kms_master_key_id = var.kms_master_key_id
  tags         = var.tags
}

resource "aws_sns_topic_subscription" "this" {
  for_each = { for idx, sub in var.subscriptions : idx => sub }

  topic_arn            = aws_sns_topic.this.arn
  protocol             = each.value.protocol
  endpoint             = each.value.endpoint
  raw_message_delivery = lookup(each.value, "raw_message_delivery", false)
}