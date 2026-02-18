##############################
# Cognito User Pool
##############################
resource "aws_cognito_user_pool" "this" {
  name = var.user_pool_name

  mfa_configuration        = var.mfa_configuration
  username_attributes      = var.username_attributes
  auto_verified_attributes = var.auto_verified_attributes

  password_policy {
    minimum_length    = var.password_min_length
    require_uppercase = var.password_require_uppercase
    require_lowercase = var.password_require_lowercase
    require_numbers   = var.password_require_numbers
    require_symbols   = var.password_require_symbols
    temporary_password_validity_days = var.temp_password_validity_days
  }

  admin_create_user_config {
    allow_admin_create_user_only = var.admin_create_only
  }

  dynamic "lambda_config" {
    for_each = length(var.lambda_triggers) > 0 ? [1] : []
    content {
      pre_sign_up          = lookup(var.lambda_triggers, "pre_sign_up", null)
      post_confirmation    = lookup(var.lambda_triggers, "post_confirmation", null)
      pre_authentication   = lookup(var.lambda_triggers, "pre_authentication", null)
      post_authentication  = lookup(var.lambda_triggers, "post_authentication", null)
      custom_message       = lookup(var.lambda_triggers, "custom_message", null)
      define_auth_challenge = lookup(var.lambda_triggers, "define_auth_challenge", null)
      create_auth_challenge = lookup(var.lambda_triggers, "create_auth_challenge", null)
      verify_auth_challenge_response = lookup(var.lambda_triggers, "verify_auth_challenge_response", null)
    }
  }

  tags = var.tags
}

##############################
# Cognito User Pool Client
##############################
resource "aws_cognito_user_pool_client" "this" {
  name         = var.client_name
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = var.generate_secret
  explicit_auth_flows = var.explicit_auth_flows

  allowed_oauth_flows_user_pool_client = (
    length(var.allowed_oauth_flows) > 0 ||
    length(var.allowed_oauth_scopes) > 0 ||
    length(var.callback_urls) > 0 ||
    length(var.logout_urls) > 0
  )

  allowed_oauth_flows           = var.allowed_oauth_flows
  allowed_oauth_scopes          = var.allowed_oauth_scopes
  callback_urls                 = var.callback_urls
  logout_urls                   = var.logout_urls
  supported_identity_providers  = var.supported_identity_providers
  prevent_user_existence_errors = var.prevent_user_existence_errors
}

##############################
# Optional Cognito Identity Pool
##############################
resource "aws_cognito_identity_pool" "this" {
  count = var.create_identity_pool ? 1 : 0

  identity_pool_name                = var.identity_pool_name
  allow_unauthenticated_identities = var.allow_unauthenticated

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.this.id
    provider_name = aws_cognito_user_pool.this.endpoint
    server_side_token_check = true
  }

  tags = var.tags
}

##############################
# Optional Cognito Domain
##############################
resource "aws_cognito_user_pool_domain" "this" {
  count        = var.create_domain ? 1 : 0
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}
