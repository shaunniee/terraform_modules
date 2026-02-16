variable "name" {
  description = "Base name for the SQS queue"
  type        = string
}

variable "fifo_queue" {
  description = "Whether this is a FIFO queue"
  type        = bool
  default     = false
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4 days
}

variable "receive_wait_time_seconds" {
  type    = number
  default = 0
}

variable "create_dlq" {
  description = "Whether to create a dead-letter queue"
  type        = bool
  default     = false
}

variable "max_receive_count" {
  description = "How many receives before message goes to DLQ"
  type        = number
  default     = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}