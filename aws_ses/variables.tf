variable "domain_identities" {
  description = "Domain identities to verify in SES. Key is domain name."
  type = map(object({
    dkim_enabled           = optional(bool, true)
    mail_from_domain       = optional(string)
    behavior_on_mx_failure = optional(string, "UseDefaultValue")
  }))
  default = {}

  validation {
    condition = alltrue([
      for d in keys(var.domain_identities) :
      can(regex("^(?=.{1,253}$)([a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$", d))
    ])
    error_message = "domain_identities keys must be valid domain names."
  }

  validation {
    condition = alltrue([
      for cfg in values(var.domain_identities) :
      contains(["UseDefaultValue", "RejectMessage"], cfg.behavior_on_mx_failure)
    ])
    error_message = "domain_identities[*].behavior_on_mx_failure must be UseDefaultValue or RejectMessage."
  }
}

variable "email_identities" {
  description = "Email identities to verify in SES."
  type        = list(string)
  default     = []

  validation {
    condition     = length(distinct(var.email_identities)) == length(var.email_identities)
    error_message = "email_identities must be unique."
  }

  validation {
    condition = alltrue([
      for e in var.email_identities :
      can(regex("^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", e))
    ])
    error_message = "email_identities must contain valid email addresses."
  }
}

variable "identity_policies" {
  description = "SES identity policies keyed by policy name."
  type = map(object({
    identity = string
    policy   = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for p in values(var.identity_policies) :
      contains(concat(keys(var.domain_identities), var.email_identities), p.identity)
    ])
    error_message = "identity_policies[*].identity must reference a configured domain_identities key or email_identities value."
  }

  validation {
    condition = alltrue([
      for p in values(var.identity_policies) :
      can(jsondecode(p.policy))
    ])
    error_message = "identity_policies[*].policy must be valid JSON."
  }
}

variable "configuration_sets" {
  description = "SES configuration set names to create."
  type        = list(string)
  default     = []

  validation {
    condition     = length(distinct(var.configuration_sets)) == length(var.configuration_sets)
    error_message = "configuration_sets names must be unique."
  }

  validation {
    condition = alltrue([
      for n in var.configuration_sets :
      can(regex("^[a-zA-Z0-9_-]{1,64}$", n))
    ])
    error_message = "configuration_sets names must be 1-64 chars using letters, numbers, hyphen, underscore."
  }
}

variable "event_destinations" {
  description = "SES event destinations keyed by destination name (SNS-only destination in this module)."
  type = map(object({
    configuration_set_name = string
    enabled                = optional(bool, true)
    matching_types         = list(string)
    sns_topic_arn          = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for ed in values(var.event_destinations) :
      contains(var.configuration_sets, ed.configuration_set_name)
    ])
    error_message = "event_destinations[*].configuration_set_name must reference configuration_sets."
  }

  validation {
    condition = alltrue(flatten([
      for ed in values(var.event_destinations) : [
        for t in ed.matching_types : contains([
          "send", "reject", "bounce", "complaint", "delivery", "open", "click", "renderingFailure"
        ], t)
      ]
    ]))
    error_message = "event_destinations[*].matching_types must use valid SES event type values."
  }

  validation {
    condition = alltrue([
      for ed in values(var.event_destinations) :
      can(regex("^arn:aws[a-zA-Z-]*:sns:[a-z0-9-]+:[0-9]{12}:.+$", ed.sns_topic_arn))
    ])
    error_message = "event_destinations[*].sns_topic_arn must be a valid SNS topic ARN."
  }
}

variable "templates" {
  description = "SES templates keyed by template name."
  type = map(object({
    subject_part = string
    html_part    = string
    text_part    = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.templates) :
      can(regex("^[a-zA-Z0-9_-]{1,64}$", name))
    ])
    error_message = "template names must be 1-64 chars using letters, numbers, hyphen, underscore."
  }
}
