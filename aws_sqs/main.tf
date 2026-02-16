locals {
  queue_name = var.fifo_queue ? "${var.name}.fifo" : var.name
  dlq_name   = var.fifo_queue ? "${var.name}-dlq.fifo" : "${var.name}-dlq"
}

# Dead Letter Queue (optional)
resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name                      = local.dlq_name
  fifo_queue                = var.fifo_queue
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds = var.message_retention_seconds
  tags                      = var.tags
}

# Main Queue
resource "aws_sqs_queue" "this" {
  name                       = local.queue_name
  fifo_queue                 = var.fifo_queue
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  tags                       = var.tags

  redrive_policy = var.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null
}

# Allow main queue to redrive from DLQ
resource "aws_sqs_queue_redrive_allow_policy" "this" {
  count = var.create_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}