# AWS Cognito Terraform Module - Complete Guide

Reusable Terraform module for provisioning Cognito authentication building blocks with sensible defaults and input validation.

## Table of Contents

1. [What This Module Creates](#1-what-this-module-creates)
2. [Prerequisites](#2-prerequisites)
3. [Scenario-Based Usage Examples](#3-scenario-based-usage-examples)
4. [Inputs Reference](#4-inputs-reference)
5. [Validation Rules Enforced by Module](#5-validation-rules-enforced-by-module)
6. [Outputs Reference](#6-outputs-reference)
7. [Behavior Notes](#7-behavior-notes)
8. [Best Practices](#8-best-practices)
9. [Troubleshooting Checklist](#9-troubleshooting-checklist)
10. [Known Limits](#10-known-limits)

---

## 1) What This Module Creates

- `aws_cognito_user_pool.this` (always)
- `aws_cognito_user_pool_client.this` (always)
- `aws_cognito_identity_pool.this` (optional; controlled by `create_identity_pool`)
- `aws_cognito_user_pool_domain.this` (optional; controlled by `create_domain`)

Feature highlights:
- Password policy and MFA configuration
- Optional Cognito Lambda triggers
- OAuth app client configuration
- Optional hosted UI domain
- Optional identity pool

---

## 2) Prerequisites

- Terraform `>= 1.3`
- AWS provider configured
- IAM permissions for Cognito and optional related resources
- If using Lambda triggers: Lambda functions must exist and have invocation permissions configured externally

---

## 3) Scenario-Based Usage Examples

### Scenario A: Minimal User Pool + App Client

```hcl
module "cognito" {
  source = "./aws_cognito"

  user_pool_name = "app-users"
  client_name    = "app-client"

  # Default explicit auth flows are:
  # ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

---

### Scenario B: OAuth App Client with Redirect URLs

```hcl
module "cognito_oauth" {
  source = "./aws_cognito"

  user_pool_name = "customer-users"
  client_name    = "customer-web-client"

  allowed_oauth_flows  = ["code", "implicit"]
  allowed_oauth_scopes = ["openid", "email", "profile"]

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
}
```

---

### Scenario C: Strong Password Policy + MFA

```hcl
module "cognito_security" {
  source = "./aws_cognito"

  user_pool_name    = "secure-users"
  client_name       = "secure-client"
  mfa_configuration = "OPTIONAL"

  password_min_length         = 12
  password_require_uppercase  = true
  password_require_lowercase  = true
  password_require_numbers    = true
  password_require_symbols    = true
  temp_password_validity_days = 7
  admin_create_only           = true
}
```

---

### Scenario D: User Pool with Lambda Triggers

```hcl
module "cognito_triggers" {
  source = "./aws_cognito"

  user_pool_name = "triggered-users"
  client_name    = "triggered-client"

  lambda_triggers = {
    pre_sign_up       = "arn:aws:lambda:us-east-1:123456789012:function:cognito-pre-signup"
    post_confirmation = "arn:aws:lambda:us-east-1:123456789012:function:cognito-post-confirmation"
    custom_message    = "arn:aws:lambda:us-east-1:123456789012:function:cognito-custom-message"
  }
}
```

---

### Scenario E: Include Identity Pool

```hcl
module "cognito_identity" {
  source = "./aws_cognito"

  user_pool_name        = "identity-users"
  client_name           = "identity-client"
  create_identity_pool  = true
  identity_pool_name    = "identity-users-pool"
  allow_unauthenticated = false
}
```

---

### Scenario F: Hosted UI Domain

```hcl
module "cognito_domain" {
  source = "./aws_cognito"

  user_pool_name = "domain-users"
  client_name    = "domain-client"

  create_domain = true
  domain_prefix = "domain-users-auth"
}
```

---

### Scenario G: Full Configuration (OAuth + Domain + Identity Pool + Triggers)

```hcl
module "cognito_full" {
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

  client_name     = "customer-web-client"
  generate_secret = false

  allowed_oauth_flows  = ["code", "implicit"]
  allowed_oauth_scopes = ["openid", "email", "profile", "phone"]

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

---

## 4) Inputs Reference

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `user_pool_name` | string | - | Yes | Name of the Cognito User Pool |
| `mfa_configuration` | string | `"OFF"` | No | MFA mode: `OFF`, `ON`, `OPTIONAL` |
| `username_attributes` | list(string) | `["email"]` | No | Username attributes (`email`, `phone_number`) |
| `auto_verified_attributes` | list(string) | `["email"]` | No | Auto-verified attributes (`email`, `phone_number`) |
| `password_min_length` | number | `8` | No | Password minimum length (`6..99`) |
| `password_require_uppercase` | bool | `true` | No | Require uppercase characters |
| `password_require_lowercase` | bool | `true` | No | Require lowercase characters |
| `password_require_numbers` | bool | `true` | No | Require numeric characters |
| `password_require_symbols` | bool | `false` | No | Require symbol characters |
| `temp_password_validity_days` | number | `7` | No | Temporary password validity (`0..365`) |
| `admin_create_only` | bool | `false` | No | Restrict user creation to admins |
| `lambda_triggers` | map(string) | `{}` | No | Lambda trigger ARNs keyed by supported trigger key |
| `client_name` | string | - | Yes | User Pool Client name |
| `generate_secret` | bool | `false` | No | Generate app client secret |
| `explicit_auth_flows` | list(string) | `["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]` | No | User Pool Client explicit auth flows |
| `allowed_oauth_flows` | list(string) | `[]` | No | OAuth flows: `code`, `implicit`, `client_credentials` |
| `allowed_oauth_scopes` | list(string) | `[]` | No | OAuth scopes |
| `callback_urls` | list(string) | `[]` | No | OAuth callback URLs (must have valid URI scheme) |
| `logout_urls` | list(string) | `[]` | No | OAuth logout URLs (must have valid URI scheme) |
| `supported_identity_providers` | list(string) | `["COGNITO"]` | No | App client identity providers |
| `prevent_user_existence_errors` | string | `"ENABLED"` | No | `ENABLED` or `LEGACY` |
| `create_identity_pool` | bool | `false` | No | Create Cognito Identity Pool |
| `identity_pool_name` | string | `""` | Conditional | Required when `create_identity_pool = true` |
| `allow_unauthenticated` | bool | `false` | No | Allow unauthenticated identities in identity pool |
| `create_domain` | bool | `false` | No | Create Cognito hosted UI domain |
| `domain_prefix` | string | `""` | Conditional | Required when `create_domain = true`; lowercase/digits/hyphen, `1..63` |
| `tags` | map(string) | `{}` | No | Resource tags |

### `lambda_triggers` Supported Keys

- `pre_sign_up`
- `post_confirmation`
- `pre_authentication`
- `post_authentication`
- `custom_message`
- `define_auth_challenge`
- `create_auth_challenge`
- `verify_auth_challenge_response`

---

## 5) Validation Rules Enforced by Module

- `user_pool_name` and `client_name` must be non-empty.
- `mfa_configuration` must be `OFF`, `ON`, or `OPTIONAL`.
- `username_attributes` and `auto_verified_attributes` can only include `email` and/or `phone_number`.
- `password_min_length` must be within `6..99`.
- `temp_password_validity_days` must be within `0..365`.
- `lambda_triggers` supports only approved keys.
- `lambda_triggers` values must be valid Lambda ARNs.
- `allowed_oauth_flows` values must be valid and unique.
- `explicit_auth_flows` values must be valid and unique.
- `allowed_oauth_scopes` values must be non-empty and unique.
- `supported_identity_providers` values must be non-empty and unique.
- `prevent_user_existence_errors` must be `ENABLED` or `LEGACY`.
- `identity_pool_name` is required when `create_identity_pool = true`.
- `domain_prefix` is required and format-validated when `create_domain = true`.

---

## 6) Outputs Reference

| Output | Description |
|--------|-------------|
| `user_pool_id` | Cognito User Pool ID |
| `user_pool_arn` | Cognito User Pool ARN |
| `user_pool_client_id` | User Pool Client ID |
| `identity_pool_id` | Identity Pool ID or `null` when not created |
| `domain` | Cognito domain prefix or `null` when not created |

---

## 7) Behavior Notes

- User Pool and User Pool Client are always created.
- Identity Pool is created only when `create_identity_pool = true`.
- Hosted UI domain is created only when `create_domain = true`.
- `lambda_config` is added only when `lambda_triggers` is non-empty.
- OAuth app client mode (`allowed_oauth_flows_user_pool_client`) is auto-enabled when any OAuth-related fields are provided (`allowed_oauth_flows`, scopes, callback URLs, logout URLs).
- App client auth flows default to username/password + refresh token, and can be overridden with `explicit_auth_flows`.
- Optional outputs resolve to `null` when related resources are not created.

---

## 8) Best Practices

- Use `code` flow for web apps when possible.
- Keep callback/logout URLs explicit and environment-specific.
- Enable MFA and stronger password settings in production.
- Use admin-only user creation where business process requires controlled onboarding.
- Keep Lambda trigger handlers idempotent and observable (logs/metrics).
- Tag all resources consistently for ownership and cost tracking.

---

## 9) Troubleshooting Checklist

- OAuth redirect issues:
  - Verify callback/logout URLs exactly match the app configuration.
- Hosted UI domain creation fails:
  - Confirm `domain_prefix` format and uniqueness in region/account.
- Identity pool not created:
  - Ensure `create_identity_pool = true` and `identity_pool_name` is set.
- Lambda triggers not firing:
  - Check trigger key names and Lambda ARN correctness.
- Plan/apply validation errors on URLs:
  - Confirm each URL uses a valid URI scheme (`https://`, custom app scheme, etc.).

---

## 10) Known Limits

- Module currently models core User Pool + App Client + optional Identity Pool + optional Domain only.
- Advanced Cognito features such as custom schemas, app client token validity tuning, advanced security modes, and user pool resource servers are not included in this module interface.
- Lambda permission resources for Cognito invocation are not managed by this module.
