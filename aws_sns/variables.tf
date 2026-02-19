

variable "tags" {
  description = "Tags to apply to all SNS topics"
  type        = map(string)
  default     = {}
}

variable "topic_name" {
  description = "The name of the SNS topic"
  type        = string
}

variable "topic_display_name" {
  description = "The display name of the SNS topic"
  type        = string
  default     = null
}

variable "fifo_topic" {
  description = "Whether the SNS topic is a FIFO topic"
  type        = bool
  default     = false
}

variable "kms_master_key_id" {
  description = "The ID of an AWS-managed customer master key (CMK) for Amazon SNS or a custom CMK. For more information, see KeyId in the AWS Key Management Service API Reference."
  type        = string
  default     = null
}

variable "subscriptions" {
  description = "List of subscriptions for the topic"
  type = list(object({
    protocol             = string   # email, lambda, sqs, http, etc.
    endpoint             = string
    raw_message_delivery = optional(bool, false)
  }))
  default = []
}