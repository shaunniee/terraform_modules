
# AWS API Gateway REST API Module - Complete Guide

This module provides a dynamic way to build a full API Gateway REST API using map-based inputs.

It supports:
- REST API creation and endpoint configuration
- Nested resources and path parameters
- Methods with multiple auth modes
- Integrations (`AWS`, `AWS_PROXY`, `HTTP`, `HTTP_PROXY`, `MOCK`)
- Method and integration responses
- Stage deployment and global method settings
- Access logs (managed CloudWatch group or existing destination)
- Optional custom domain + optional Route53 alias record

---

## 1) Module Design (How Inputs Fit Together)

Use these maps together:
- `resources` defines path segments
- `methods` attaches HTTP methods to resources (or root)
- `integrations` binds methods to backends
- `method_responses` defines client response contracts (optional)
- `integration_responses` maps backend responses to method responses (optional)

Flow:
1. Build path tree (`resources`)
2. Attach method contracts (`methods`)
3. Wire backends (`integrations`)
4. Optionally model response mapping (`method_responses` + `integration_responses`)
5. Deploy stage and apply runtime settings
6. Optionally add domain and DNS

---

## 2) Prerequisites

- Terraform >= 1.3
- AWS provider configured
- IAM permissions for API Gateway + optional CloudWatch/Route53
- For Lambda integrations: separate `aws_lambda_permission` allowing API Gateway invoke

---

## 3) Scenario-Based Usage Examples

### Scenario A: Minimal Lambda Proxy API

```hcl
module "orders_api" {
  source = "./aws_api_gateway_rest_api"

  name = "orders-api"

  resources = {
    orders = { path_part = "orders" }
  }

  methods = {
    list_orders = {
      resource_key  = "orders"
      http_method   = "GET"
      authorization = "NONE"
    }
  }

  integrations = {
    list_orders_lambda = {
      method_key              = "list_orders"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.orders.invoke_arn
    }
  }

  stage_name = "v1"
}

resource "aws_lambda_permission" "allow_apigw_orders" {
  statement_id  = "AllowExecutionFromAPIGatewayOrders"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.orders_api.rest_api_execution_arn}/*/*"
}
```

---

### Scenario B: Nested Resources + HTTP Proxy Backend

```hcl
module "customer_api" {
  source = "./aws_api_gateway_rest_api"

  name = "customer-api"

  resources = {
    customers = { path_part = "customers" }
    customer_id = {
      path_part  = "{id}"
      parent_key = "customers"
    }
  }

  methods = {
    get_customer = {
      resource_key  = "customer_id"
      http_method   = "GET"
      authorization = "AWS_IAM"
      request_parameters = {
        "method.request.path.id" = true
      }
    }
  }

  integrations = {
    get_customer_http = {
      method_key              = "get_customer"
      type                    = "HTTP_PROXY"
      integration_http_method = "GET"
      uri                     = "https://internal.example.com/customers/{id}"
      request_parameters = {
        "integration.request.path.id" = "method.request.path.id"
      }
    }
  }

  stage_name = "prod"
}
```

---

### Scenario C: CORS Preflight with MOCK Integration

```hcl
module "cors_api" {
  source = "./aws_api_gateway_rest_api"

  name = "cors-api"

  resources = {
    items = { path_part = "items" }
  }

  methods = {
    options_items = {
      resource_key  = "items"
      http_method   = "OPTIONS"
      authorization = "NONE"
    }
  }

  integrations = {
    options_items_mock = {
      method_key = "options_items"
      type       = "MOCK"
      request_templates = {
        "application/json" = "{\"statusCode\": 200}"
      }
    }
  }

  method_responses = {
    options_200 = {
      method_key  = "options_items"
      status_code = "200"
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin"  = true
        "method.response.header.Access-Control-Allow-Methods" = true
        "method.response.header.Access-Control-Allow-Headers" = true
      }
    }
  }

  integration_responses = {
    options_200 = {
      method_response_key = "options_200"
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin"  = "'https://app.example.com'"
        "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
      }
    }
  }

  stage_name = "v1"
}
```

---

### Scenario D: Lambda Custom Authorizer (`CUSTOM`)

```hcl
resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name                   = "jwt-custom-authorizer"
  rest_api_id            = module.secure_api.rest_api_id
  authorizer_uri         = aws_lambda_function.authorizer.invoke_arn
  authorizer_result_ttl_in_seconds = 300
  type                   = "REQUEST"
  identity_source        = "method.request.header.Authorization"
}

module "secure_api" {
  source = "./aws_api_gateway_rest_api"

  name = "secure-api"

  resources = {
    profile = { path_part = "profile" }
  }

  methods = {
    get_profile = {
      resource_key  = "profile"
      http_method   = "GET"
      authorization = "CUSTOM"
      authorizer_id = aws_api_gateway_authorizer.jwt_authorizer.id
    }
  }

  integrations = {
    get_profile_lambda = {
      method_key              = "get_profile"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.profile.invoke_arn
    }
  }

  stage_name = "prod"
}
```

---

### Scenario E: Cognito User Pool Authorizer (`COGNITO_USER_POOLS`)

```hcl
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  rest_api_id   = module.user_api.rest_api_id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.users.arn]
}

module "user_api" {
  source = "./aws_api_gateway_rest_api"

  name = "user-api"

  resources = {
    me = { path_part = "me" }
  }

  methods = {
    get_me = {
      resource_key  = "me"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
      authorizer_id = aws_api_gateway_authorizer.cognito.id
    }
  }

  integrations = {
    get_me_lambda = {
      method_key              = "get_me"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.me.invoke_arn
    }
  }

  stage_name = "prod"
}
```

---

### Scenario F: Private Integration with `VPC_LINK`

```hcl
module "private_api" {
  source = "./aws_api_gateway_rest_api"

  name = "private-api"

  resources = {
    invoices = { path_part = "invoices" }
  }

  methods = {
    get_invoices = {
      resource_key  = "invoices"
      http_method   = "GET"
      authorization = "AWS_IAM"
    }
  }

  integrations = {
    get_invoices_vpc = {
      method_key              = "get_invoices"
      type                    = "HTTP_PROXY"
      integration_http_method = "GET"
      uri                     = "http://internal-alb.example.local/invoices"
      connection_type         = "VPC_LINK"
      connection_id           = aws_api_gateway_vpc_link.internal.id
    }
  }

  stage_name = "prod"
}
```

---

### Scenario G: Stage Logs, Metrics, Throttling, and Caching

```hcl
module "ops_api" {
  source = "./aws_api_gateway_rest_api"

  name = "ops-api"

  methods = {
    health = {
      http_method   = "GET"
      authorization = "NONE"
    }
  }

  integrations = {
    health_mock = {
      method_key = "health"
      type       = "MOCK"
      request_templates = {
        "application/json" = "{\"statusCode\":200}"
      }
    }
  }

  stage_name = "prod"

  method_settings = {
    logging_level          = "INFO"
    metrics_enabled        = true
    throttling_burst_limit = 200
    throttling_rate_limit  = 100
    caching_enabled        = true
    cache_ttl_in_seconds   = 300
  }

  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"

  access_log_enabled           = true
  create_access_log_group      = true
  access_log_retention_in_days = 30
}
```

---

### Scenario H: Custom Domain + Route53 Alias

```hcl
module "public_api" {
  source = "./aws_api_gateway_rest_api"

  name       = "public-api"
  stage_name = "v1"

  methods = {
    ping = {
      http_method   = "GET"
      authorization = "NONE"
    }
  }

  integrations = {
    ping_mock = {
      method_key = "ping"
      type       = "MOCK"
      request_templates = {
        "application/json" = "{\"statusCode\":200}"
      }
    }
  }

  create_domain_name    = true
  domain_name           = "api.example.com"
  certificate_arn       = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  security_policy       = "TLS_1_2"
  base_path             = null
  create_route53_record = true
  hosted_zone_id        = "Z123456789ABCDEFG"
}
```

---

## 4) Inputs Reference

### Top-Level Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | API name |
| `description` | string | `null` | No | API description |
| `tags` | map(string) | `{}` | No | Tags for supported resources |
| `endpoint_configuration_types` | list(string) | `["REGIONAL"]` | No | Endpoint type(s): `REGIONAL`, `EDGE`, `PRIVATE` |
| `binary_media_types` | list(string) | `[]` | No | Binary media types |
| `minimum_compression_size` | number | `null` | No | Compression threshold bytes (0-10485760) |
| `api_key_source` | string | `"HEADER"` | No | API key source: `HEADER` or `AUTHORIZER` |
| `disable_execute_api_endpoint` | bool | `false` | No | Disable default execute-api endpoint |
| `resources` | map(object) | `{}` | No | Path resource definitions |
| `methods` | map(object) | `{}` | No | Method definitions |
| `integrations` | map(object) | `{}` | No | Backend integration definitions |
| `method_responses` | map(object) | `{}` | No | Method response definitions |
| `integration_responses` | map(object) | `{}` | No | Integration response definitions |
| `stage_name` | string | `"v1"` | No | Stage name |
| `stage_description` | string | `null` | No | Stage description |
| `deployment_description` | string | `null` | No | Deployment description |
| `stage_variables` | map(string) | `{}` | No | Stage variables |
| `xray_tracing_enabled` | bool | `false` | No | Enable X-Ray tracing |
| `cache_cluster_enabled` | bool | `false` | No | Enable API cache cluster |
| `cache_cluster_size` | string | `null` | Conditional | Required when cache cluster enabled |
| `method_settings` | object | `null` | No | Global `*/*` method settings |
| `access_log_enabled` | bool | `false` | No | Enable stage access logs |
| `create_access_log_group` | bool | `false` | No | Create CloudWatch log group for access logs |
| `access_log_group_name` | string | `null` | No | Optional custom log group name |
| `access_log_retention_in_days` | number | `14` | No | Retention for module-created log group |
| `access_log_kms_key_arn` | string | `null` | No | KMS key ARN for module-created log group |
| `access_log_destination_arn` | string | `null` | Conditional | Needed when logs enabled and group not created |
| `access_log_format` | string | JSON format | No | Access log line format |
| `create_domain_name` | bool | `false` | No | Create custom domain + base path mapping |
| `domain_name` | string | `null` | Conditional | Required when custom domain enabled |
| `certificate_arn` | string | `null` | Conditional | Required when custom domain enabled |
| `base_path` | string | `null` | No | Base path mapping (null = root) |
| `security_policy` | string | `"TLS_1_2"` | No | TLS policy (`TLS_1_0`, `TLS_1_2`) |
| `create_route53_record` | bool | `false` | No | Create Route53 alias `A` record |
| `hosted_zone_id` | string | `null` | Conditional | Required when Route53 record enabled |
| `record_name` | string | `null` | No | DNS name override (defaults to domain_name) |

### Object Schemas

#### `resources` object

```hcl
resources = {
  key = {
    path_part  = string
    parent_key = optional(string)
  }
}
```

#### `methods` object

```hcl
methods = {
  key = {
    resource_key         = optional(string)
    http_method          = string
    authorization        = optional(string, "NONE")
    authorizer_id        = optional(string)
    api_key_required     = optional(bool, false)
    request_models       = optional(map(string), {})
    request_parameters   = optional(map(bool), {})
    request_validator_id = optional(string)
    operation_name       = optional(string)
  }
}
```

#### `integrations` object

```hcl
integrations = {
  key = {
    method_key              = string
    type                    = string
    integration_http_method = optional(string)
    uri                     = optional(string)
    connection_type         = optional(string)
    connection_id           = optional(string)
    passthrough_behavior    = optional(string)
    request_templates       = optional(map(string), {})
    request_parameters      = optional(map(string), {})
    content_handling        = optional(string)
    timeout_milliseconds    = optional(number)
    cache_key_parameters    = optional(list(string), [])
    cache_namespace         = optional(string)
  }
}
```

#### `method_responses` object

```hcl
method_responses = {
  key = {
    method_key          = string
    status_code         = string
    response_models     = optional(map(string), {})
    response_parameters = optional(map(bool), {})
  }
}
```

#### `integration_responses` object

```hcl
integration_responses = {
  key = {
    method_response_key = string
    status_code         = optional(string)
    selection_pattern   = optional(string)
    response_templates  = optional(map(string), {})
    response_parameters = optional(map(string), {})
    content_handling    = optional(string)
  }
}
```

---

## 5) Validation Rules Enforced by Module

Core validation and coupling rules:
- `name` must be non-empty.
- `endpoint_configuration_types` values must be one of `REGIONAL`, `EDGE`, `PRIVATE`.
- `minimum_compression_size` must be null or `0..10485760`.
- `methods[*].http_method` must be a valid API Gateway method.
- `methods[*].authorization` must be `NONE`, `AWS_IAM`, `CUSTOM`, or `COGNITO_USER_POOLS`.
- `methods[*].authorizer_id` is required for `CUSTOM` and `COGNITO_USER_POOLS`.
- `methods[*].resource_key` must reference a key from `resources` (when set).
- `integrations[*].method_key` must reference an existing `methods` key.
- `integrations[*].type` must be one of `HTTP`, `HTTP_PROXY`, `AWS`, `AWS_PROXY`, `MOCK`.
- Non-`MOCK` integrations require `integration_http_method` and `uri`.
- `integrations[*].connection_type` must be `INTERNET` or `VPC_LINK` when provided.
- If `connection_type = VPC_LINK`, `connection_id` is required.
- `integrations[*].timeout_milliseconds` must be null or `50..29000`.
- `method_responses[*].method_key` must reference `methods` and status code must be `1xx..5xx` format.
- `integration_responses[*].method_response_key` must reference `method_responses`.
- `stage_name` format: 1-128 chars, letters/numbers/underscore/hyphen.
- If `cache_cluster_enabled = true`, `cache_cluster_size` is required and must be one of `0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237`.
- If `access_log_enabled = true`, either `create_access_log_group = true` or `access_log_destination_arn` must be set.
- If `create_domain_name = true`, both `domain_name` and `certificate_arn` are required (non-empty).
- If `create_route53_record = true`, `create_domain_name = true` and non-empty `hosted_zone_id` are required.

---

## 6) Outputs Reference

| Output | Description |
|--------|-------------|
| `rest_api_id` | REST API ID |
| `rest_api_execution_arn` | Execution ARN (useful for Lambda permissions) |
| `rest_api_root_resource_id` | Root resource ID |
| `resource_ids` | Resource IDs keyed by resource key |
| `methods_index` | Method metadata keyed by method key |
| `integration_ids` | Integration IDs keyed by integration key |
| `method_response_ids` | Method response IDs keyed by response key |
| `integration_response_ids` | Integration response IDs keyed by response key |
| `stage_name` | Stage name |
| `stage_arn` | Stage ARN |
| `invoke_url` | Stage invoke URL |
| `access_log_group_name` | Access log group name when created by module |
| `custom_domain_name` | Custom domain name (null if disabled) |
| `custom_domain_regional_domain_name` | Regional API Gateway domain target for alias |
| `custom_domain_regional_zone_id` | Regional hosted zone ID for alias |

---

## 7) Best Practices

- Keep resource/method map keys stable to avoid unnecessary replacements.
- Start with `AWS_PROXY`/`HTTP_PROXY` unless you specifically need mapping templates.
- Keep `method_responses` + `integration_responses` for non-proxy patterns (e.g., CORS headers, custom transforms).
- Enable `method_settings.metrics_enabled` and access logs in non-dev environments.
- Use `rest_api_execution_arn` output for downstream Lambda invoke permissions.
- Keep domain and DNS creation in the same stack where possible to avoid drift.

---

## 8) Troubleshooting Checklist

- Validation says `authorizer_id` required:
  - Set `methods[*].authorizer_id` when using `CUSTOM` or `COGNITO_USER_POOLS`.
- Integration errors on apply:
  - Ensure non-`MOCK` integrations include both `integration_http_method` and `uri`.
- VPC link integration fails:
  - Use `connection_type = "VPC_LINK"` and provide valid `connection_id`.
- Access logs not enabled:
  - Set `access_log_enabled = true` and either create log group or provide destination ARN.
- Custom domain setup fails:
  - Verify ACM cert ARN region/validity and hosted zone ID when creating Route53 alias.

