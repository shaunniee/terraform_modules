variable "user_pool_name" {
  description = "Name of the Cognito User Pool."
  type        = string

  validation {
    condition     = length(trimspace(var.user_pool_name)) > 0
    error_message = "user_pool_name must not be empty."
  }
}

variable "mfa_configuration" {
  description = "MFA setting for the user pool. Allowed values: OFF, ON, OPTIONAL."
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "mfa_configuration must be one of: OFF, ON, OPTIONAL."
  }
}

variable "username_attributes" {
  description = "Attributes used as username values."
  type        = list(string)
  default     = ["email"]

  validation {
    condition     = alltrue([for attr in var.username_attributes : contains(["email", "phone_number"], attr)])
    error_message = "username_attributes can only include: email, phone_number."
  }
}

variable "auto_verified_attributes" {
  description = "User attributes to auto-verify during signup."
  type        = list(string)
  default     = ["email"]

  validation {
    condition     = alltrue([for attr in var.auto_verified_attributes : contains(["email", "phone_number"], attr)])
    error_message = "auto_verified_attributes can only include: email, phone_number."
  }
}

variable "password_min_length" {
  description = "Minimum length for user passwords."
  type        = number
  default     = 8

  validation {
    condition     = var.password_min_length >= 6 && var.password_min_length <= 99
    error_message = "password_min_length must be between 6 and 99."
  }
}

variable "password_require_uppercase" {
  description = "Whether passwords must include uppercase characters."
  type        = bool
  default     = true
}

variable "password_require_lowercase" {
  description = "Whether passwords must include lowercase characters."
  type        = bool
  default     = true
}

variable "password_require_numbers" {
  description = "Whether passwords must include numeric characters."
  type        = bool
  default     = true
}

variable "password_require_symbols" {
  description = "Whether passwords must include symbol characters."
  type        = bool
  default     = false
}

variable "temp_password_validity_days" {
  description = "Number of days temporary passwords remain valid."
  type        = number
  default     = 7

  validation {
    condition     = var.temp_password_validity_days >= 0 && var.temp_password_validity_days <= 365
    error_message = "temp_password_validity_days must be between 0 and 365."
  }
}

variable "admin_create_only" {
  description = "Allow only administrators to create users."
  type        = bool
  default     = false
}

variable "lambda_triggers" {
  description = "Map of Cognito Lambda trigger ARNs keyed by trigger name."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for trigger_name in keys(var.lambda_triggers) : contains([
        "pre_sign_up",
        "post_confirmation",
        "pre_authentication",
        "post_authentication",
        "custom_message",
        "define_auth_challenge",
        "create_auth_challenge",
        "verify_auth_challenge_response"
      ], trigger_name)
    ])
    error_message = "lambda_triggers contains unsupported keys."
  }

  validation {
    condition = alltrue([
      for trigger_arn in values(var.lambda_triggers) : can(regex("^arn:aws(-[a-z]+)*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9-_]+(:[A-Za-z0-9-_]+)?$", trigger_arn))
    ])
    error_message = "Each lambda_triggers value must be a valid Lambda function ARN."
  }
}

variable "client_name" {
  description = "Name of the Cognito User Pool Client."
  type        = string

  validation {
    condition     = length(trimspace(var.client_name)) > 0
    error_message = "client_name must not be empty."
  }
}

variable "generate_secret" {
  description = "Whether to generate a client secret for the user pool client."
  type        = bool
  default     = false
}

variable "allowed_oauth_flows" {
  description = "OAuth flows enabled for the user pool client."
  type        = list(string)
  default     = []

  validation {
    condition     = length(distinct(var.allowed_oauth_flows)) == length(var.allowed_oauth_flows)
    error_message = "allowed_oauth_flows must not contain duplicate values."
  }

  validation {
    condition     = alltrue([for flow in var.allowed_oauth_flows : contains(["code", "implicit", "client_credentials"], flow)])
    error_message = "allowed_oauth_flows can only include: code, implicit, client_credentials."
  }
}

variable "allowed_oauth_scopes" {
  description = "OAuth scopes enabled for the user pool client."
  type        = list(string)
  default     = []

  validation {
    condition     = length(distinct(var.allowed_oauth_scopes)) == length(var.allowed_oauth_scopes)
    error_message = "allowed_oauth_scopes must not contain duplicate values."
  }

  validation {
    condition     = alltrue([for scope in var.allowed_oauth_scopes : length(trimspace(scope)) > 0])
    error_message = "allowed_oauth_scopes must not contain empty values."
  }
}

variable "callback_urls" {
  description = "Allowed callback URLs for OAuth redirect."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for url in var.callback_urls : can(regex("^[a-z][a-z0-9+.-]*://.+", lower(url)))
    ])
    error_message = "Each callback URL must use a valid URI scheme (for example: https://..., http://..., myapp://...)."
  }
}

variable "logout_urls" {
  description = "Allowed logout redirect URLs."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for url in var.logout_urls : can(regex("^[a-z][a-z0-9+.-]*://.+", lower(url)))
    ])
    error_message = "Each logout URL must use a valid URI scheme (for example: https://..., http://..., myapp://...)."
  }
}

variable "supported_identity_providers" {
  description = "List of identity providers supported by the app client."
  type        = list(string)
  default     = ["COGNITO"]

  validation {
    condition     = length(distinct(var.supported_identity_providers)) == length(var.supported_identity_providers)
    error_message = "supported_identity_providers must not contain duplicate values."
  }

  validation {
    condition     = alltrue([for provider in var.supported_identity_providers : length(trimspace(provider)) > 0])
    error_message = "supported_identity_providers must not contain empty values."
  }
}

variable "prevent_user_existence_errors" {
  description = "Behavior when users do not exist in authentication flows."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "LEGACY"], var.prevent_user_existence_errors)
    error_message = "prevent_user_existence_errors must be one of: ENABLED, LEGACY."
  }
}

variable "create_identity_pool" {
  description = "Whether to create a Cognito Identity Pool."
  type        = bool
  default     = false
}

variable "identity_pool_name" {
  description = "Name of the Cognito Identity Pool when create_identity_pool is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_identity_pool || length(trimspace(var.identity_pool_name)) > 0
    error_message = "identity_pool_name must be provided when create_identity_pool is true."
  }
}

variable "allow_unauthenticated" {
  description = "Whether unauthenticated identities are allowed in the identity pool."
  type        = bool
  default     = false
}

variable "create_domain" {
  description = "Whether to create a Cognito hosted UI domain."
  type        = bool
  default     = false
}

variable "domain_prefix" {
  description = "Domain prefix for Cognito hosted UI when create_domain is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_domain || length(trimspace(var.domain_prefix)) > 0
    error_message = "domain_prefix must be provided when create_domain is true."
  }

  validation {
    condition     = var.domain_prefix == "" || can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.domain_prefix))
    error_message = "domain_prefix must be 1-63 characters of lowercase letters, numbers, or hyphens, and cannot start or end with a hyphen."
  }
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
