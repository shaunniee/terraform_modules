````markdown
# AWS Cognito Terraform Module

Reusable module for provisioning Cognito authentication primitives:
- Cognito User Pool
- Cognito User Pool Client
- Optional Cognito Identity Pool
- Optional Cognito User Pool Domain
- Password policy and MFA controls
- Optional Lambda trigger wiring

## Basic Usage

```hcl
module "cognito" {
  source = "./aws_cognito"

  user_pool_name = "app-users"
  client_name    = "app-client"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Advanced Usage (OAuth + Domain + Identity Pool + Triggers)

```hcl
module "cognito" {
  source = "./aws_cognito"

  user_pool_name    = "customer-auth-prod"
  mfa_configuration = "OPTIONAL"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_min_length         = 12
  password_require_uppercase  = true
  password_require_lowercase  = true
  password_require_numbers    = true
  password_require_symbols    = true
  temp_password_validity_days = 7
  admin_create_only           = false

  client_name      = "customer-web-client"
  generate_secret  = false

  allowed_oauth_flows  = ["code", "implicit"]
  allowed_oauth_scopes = [
    "email",
    "openid",
    "phone",
    "profile"
  ]

  callback_urls = [
    "https://app.example.com/auth/callback",
    "myapp://auth/callback"
  ]

  logout_urls = [
    "https://app.example.com/logout",
    "myapp://logout"
  ]

  supported_identity_providers  = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"

  create_identity_pool  = true
  identity_pool_name    = "customer-identity-prod"
  allow_unauthenticated = false

  create_domain = true
  domain_prefix = "customer-auth-prod"

  lambda_triggers = {
    pre_sign_up       = "arn:aws:lambda:us-east-1:123456789012:function:cognito-pre-signup"
    post_confirmation = "arn:aws:lambda:us-east-1:123456789012:function:cognito-post-confirmation"
    custom_message    = "arn:aws:lambda:us-east-1:123456789012:function:cognito-custom-message"
  }

  tags = {
    Environment = "prod"
    Service     = "customer-auth"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `user_pool_name` | string | - | Yes | Name of the Cognito User Pool |
| `mfa_configuration` | string | `"OFF"` | No | MFA mode: `OFF`, `ON`, `OPTIONAL` |
| `username_attributes` | list(string) | `["email"]` | No | Username attributes (`email`, `phone_number`) |
| `auto_verified_attributes` | list(string) | `["email"]` | No | Auto-verified attributes (`email`, `phone_number`) |
| `password_min_length` | number | `8` | No | Password minimum length (6-99) |
| `password_require_uppercase` | bool | `true` | No | Require uppercase characters |
| `password_require_lowercase` | bool | `true` | No | Require lowercase characters |
| `password_require_numbers` | bool | `true` | No | Require numeric characters |
| `password_require_symbols` | bool | `false` | No | Require symbol characters |
| `temp_password_validity_days` | number | `7` | No | Temporary password validity in days (0-365) |
| `admin_create_only` | bool | `false` | No | Allow only admin-created users |
| `lambda_triggers` | map(string) | `{}` | No | Lambda trigger ARNs keyed by trigger type |
| `client_name` | string | - | Yes | Name of the User Pool Client |
| `generate_secret` | bool | `false` | No | Generate client secret |
| `allowed_oauth_flows` | list(string) | `[]` | No | OAuth flows (`code`, `implicit`, `client_credentials`) |
| `allowed_oauth_scopes` | list(string) | `[]` | No | OAuth scopes for the app client |
| `callback_urls` | list(string) | `[]` | No | OAuth callback URLs (must start with `http://`, `https://`, or custom scheme like `myapp://`) |
| `logout_urls` | list(string) | `[]` | No | OAuth logout URLs (must start with `http://`, `https://`, or custom scheme like `myapp://`) |
| `supported_identity_providers` | list(string) | `["COGNITO"]` | No | Identity providers for app client |
| `prevent_user_existence_errors` | string | `"ENABLED"` | No | User existence behavior: `ENABLED` or `LEGACY` |
| `create_identity_pool` | bool | `false` | No | Create Cognito Identity Pool |
| `identity_pool_name` | string | `""` | Conditional | Required when `create_identity_pool = true` |
| `allow_unauthenticated` | bool | `false` | No | Allow unauthenticated identities |
| `create_domain` | bool | `false` | No | Create Cognito User Pool Domain |
| `domain_prefix` | string | `""` | Conditional | Required when `create_domain = true`; lowercase/digits/hyphen, 1-63 chars |
| `tags` | map(string) | `{}` | No | Tags applied to supported resources |

## Outputs

| Output | Description |
|--------|-------------|
| `user_pool_id` | ID of the Cognito User Pool |
| `user_pool_arn` | ARN of the Cognito User Pool |
| `user_pool_client_id` | ID of the Cognito User Pool Client |
| `identity_pool_id` | ID of the Identity Pool (or `null` if not created) |
| `domain` | Cognito domain prefix (or `null` if not created) |

## Lambda Trigger Keys

The following keys are supported in `lambda_triggers`:
- `pre_sign_up`
- `post_confirmation`
- `pre_authentication`
- `post_authentication`
- `custom_message`
- `define_auth_challenge`
- `create_auth_challenge`
- `verify_auth_challenge_response`

## Validation Notes

- `user_pool_name` and `client_name` must be non-empty.
- `mfa_configuration` must be `OFF`, `ON`, or `OPTIONAL`.
- `allowed_oauth_flows` must use supported flow values and cannot contain duplicates.
- `allowed_oauth_scopes` and `supported_identity_providers` cannot contain empty values.
- `lambda_triggers` values must be valid Lambda function ARNs.
- `identity_pool_name` is required when `create_identity_pool` is enabled.
- `domain_prefix` is required and format-validated when `create_domain` is enabled.

## Important Behavior

- User Pool and User Pool Client are always created.
- Identity Pool is created only when `create_identity_pool = true`.
- User Pool Domain is created only when `create_domain = true`.
- Output values for optional resources resolve to `null` when those resources are not created.

````
