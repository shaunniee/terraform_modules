# AWS API Gateway REST API Module

Composable REST API module built with submodules for:
- API definition
- resources (path tree)
- methods
- integrations
- method/integration responses
- deployment + stage
- optional custom domain + Route53 alias

## Basic Example (Lambda Proxy)

```hcl
module "orders_api" {
  source = "./aws_api_gateway_rest_api"

  name = "orders-api"

  resources = {
    orders = {
      path_part = "orders"
    }
  }

  methods = {
    get_orders = {
      resource_key  = "orders"
      http_method   = "GET"
      authorization = "NONE"
    }
  }

  integrations = {
    get_orders_lambda = {
      method_key              = "get_orders"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.orders.invoke_arn
    }
  }

  stage_name = "v1"
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.orders_api.rest_api_execution_arn}/*/*"
}
```

## Advanced Example (Nested Paths, Responses, Logs, Domain)

```hcl
module "api" {
  source = "./aws_api_gateway_rest_api"

  name        = "customer-api"
  description = "Customer service API"

  resources = {
    customers = {
      path_part = "customers"
    }
    customer_id = {
      path_part  = "{id}"
      parent_key = "customers"
    }
  }

  methods = {
    list_customers = {
      resource_key  = "customers"
      http_method   = "GET"
      authorization = "AWS_IAM"
    }
    get_customer = {
      resource_key  = "customer_id"
      http_method   = "GET"
      authorization = "AWS_IAM"
    }
  }

  integrations = {
    list_customers_http = {
      method_key           = "list_customers"
      type                 = "HTTP_PROXY"
      integration_http_method = "GET"
      uri                  = "https://internal.example.com/customers"
    }
    get_customer_http = {
      method_key           = "get_customer"
      type                 = "HTTP_PROXY"
      integration_http_method = "GET"
      uri                  = "https://internal.example.com/customers/{id}"
      request_parameters = {
        "integration.request.path.id" = "method.request.path.id"
      }
    }
  }

  method_responses = {
    list_200 = {
      method_key  = "list_customers"
      status_code = "200"
    }
  }

  integration_responses = {
    list_200 = {
      method_response_key = "list_200"
    }
  }

  stage_name           = "prod"
  xray_tracing_enabled = true

  method_settings = {
    logging_level      = "INFO"
    metrics_enabled    = true
    data_trace_enabled = false
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  access_log_enabled       = true
  create_access_log_group  = true
  access_log_retention_in_days = 30

  create_domain_name  = true
  domain_name         = "api.example.com"
  certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  create_route53_record = true
  hosted_zone_id      = "Z123456789ABCDEFG"

  tags = {
    Environment = "prod"
    Service     = "customer-api"
    ManagedBy   = "terraform"
  }
}
```

## Dynamic Inputs Overview

- `resources`: build arbitrary nested path trees with `parent_key`
- `authorizers`: optionally create API Gateway authorizers from input
- `methods`: attach any HTTP method + auth mode per resource
- `integrations`: mix `AWS_PROXY`, `HTTP_PROXY`, `MOCK`, etc.
- `method_responses` + `integration_responses`: optional response modeling
- `method_settings`: global stage method tuning (`*/*`)
- `access_log_*`: bring your own log destination or let module create one
- `create_domain_name`: optional custom domain + base path mapping + DNS

## Entry-By-Entry Explanation

### `resources` entries

Each map key is your internal identifier for a path segment.

- `path_part`: single path segment to create (examples: `orders`, `{id}`).
- `parent_key`: optional reference to another `resources` key.
  - Omit for resources that should be direct children of API root.
  - Set it to build nested paths.

Example:
- `customers` with no `parent_key` creates `/customers`.
- `customer_id` with `parent_key = "customers"` and `path_part = "{id}"` creates `/customers/{id}`.

### `methods` entries

Each map key is your internal method identifier.

- `resource_key`: optional resource reference from `resources`.
  - If omitted, method is attached to API root (`/`).
- `http_method`: request method (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`, `ANY`).
- `authorization`: `NONE`, `AWS_IAM`, `CUSTOM`, `COGNITO_USER_POOLS`.
- `authorizer_key`: optional reference to an entry in `authorizers`.
- `authorizer_id`: required only for `CUSTOM` or `COGNITO_USER_POOLS`.
- `api_key_required`: enforce usage plan/API key.
- `request_models`: request model mapping by content type.
- `request_parameters`: required request params map (`method.request.path.id = true`, etc.).
- `request_validator_id`: API Gateway request validator ID.
- `operation_name`: optional operation label.

### `integrations` entries

Each map key is your internal integration identifier.

- `method_key`: required reference to one `methods` entry.
- `type`: integration type (`AWS`, `AWS_PROXY`, `HTTP`, `HTTP_PROXY`, `MOCK`).
- `integration_http_method`: backend method (commonly `POST` for Lambda proxy, `GET/POST/...` for HTTP).
- `uri`: backend URI/ARN (Lambda invoke URI, HTTP URL, etc.).
- `connection_type`: usually `INTERNET` or `VPC_LINK`.
- `connection_id`: VPC link ID when using `VPC_LINK`.
- `passthrough_behavior`: template passthrough behavior.
- `request_templates`: VTL templates by content type.
- `request_parameters`: mapping from method params to integration params.
- `content_handling`: payload conversion mode.
- `timeout_milliseconds`: backend timeout (50 to 29000).
- `cache_key_parameters`: method/integration params used for cache key.
- `cache_namespace`: cache namespace override.

### `method_responses` entries

Each map key is your internal method response identifier.

- `method_key`: required reference to one `methods` entry.
- `status_code`: HTTP status code string (`200`, `400`, etc.).
- `response_models`: response model mapping by content type.
- `response_parameters`: response headers map (for example `method.response.header.X-Trace-Id = true`).

### `integration_responses` entries

Each map key is your internal integration response identifier.

- `method_response_key`: required reference to one `method_responses` entry.
- `status_code`: optional override; defaults to referenced method response status.
- `selection_pattern`: regex for selecting backend error responses.
- `response_templates`: VTL response templates by content type.
- `response_parameters`: header/param mappings from integration response to method response.
- `content_handling`: payload conversion mode for integration response.

### Stage and deployment entries

- `stage_name`: deployed stage name (`v1`, `dev`, `prod`).
- `stage_variables`: key-value variables available in stage context.
- `deployment_description`: description on deployment resource.
- `stage_description`: description on stage resource.
- `xray_tracing_enabled`: enable X-Ray tracing.
- `cache_cluster_enabled` and `cache_cluster_size`: stage cache configuration.
- `method_settings`: global method settings applied to `*/*` (logging, metrics, throttling, caching).

### Access log entries

- `access_log_enabled`: turn stage access logging on/off.
- `create_access_log_group`: create CloudWatch log group in this module.
- `access_log_group_name`: optional custom log group name when creating it.
- `access_log_retention_in_days`: retention for created log group.
- `access_log_kms_key_arn`: optional KMS key for created log group encryption.
- `access_log_destination_arn`: use existing log destination ARN instead of creating one.
- `access_log_format`: JSON/string format for access log events.

### Custom domain entries

- `create_domain_name`: enable custom domain resources.
- `domain_name`: custom API hostname (example `api.example.com`).
- `certificate_arn`: ACM certificate ARN for that domain.
- `security_policy`: TLS policy (`TLS_1_0` or `TLS_1_2`).
- `base_path`: optional base path mapping (null maps root).
- `create_route53_record`: create alias `A` record in Route53.
- `hosted_zone_id`: Route53 hosted zone ID (required if creating record).
- `record_name`: DNS record name override (defaults to `domain_name`).

## Detailed Inputs Reference

### Core API Inputs

- `name`:
  - API Gateway REST API name.
  - Used as the primary API identifier in AWS console and outputs.
  - Required and must be non-empty.

- `description`:
  - Optional human-readable API description.
  - Does not affect runtime behavior.

- `tags`:
  - Applied to supported resources created by this module.
  - Useful for ownership/cost/compliance tagging.

- `endpoint_configuration_types`:
  - Controls endpoint type:
    - `REGIONAL`: standard regional endpoint (most common).
    - `EDGE`: CloudFront-backed edge endpoint.
    - `PRIVATE`: private API for VPC endpoint access.
  - Choose based on network exposure and latency requirements.

- `binary_media_types`:
  - Content types that API Gateway treats as binary payloads.
  - Typical examples: `image/png`, `application/octet-stream`.
  - Important when passing binary through Lambda proxy.

- `minimum_compression_size`:
  - Enables response compression above threshold bytes.
  - `null` disables compression.
  - Use to reduce bandwidth for large JSON/text responses.

- `api_key_source`:
  - Where API Gateway reads API keys from:
    - `HEADER`: from `X-API-Key`.
    - `AUTHORIZER`: from custom authorizer context.

- `disable_execute_api_endpoint`:
  - If `true`, default `https://{api_id}.execute-api...` endpoint is disabled.
  - Use when you want only custom domain access.

### Resource Tree Inputs (`resources`)

- Purpose:
  - Builds the path hierarchy for the REST API.
  - Each entry creates one `aws_api_gateway_resource`.

- `path_part`:
  - One segment only (not full path).
  - Examples:
    - `orders`
    - `{orderId}` (path parameter segment)

- `parent_key`:
  - Reference to another resource entry key.
  - If omitted, resource is created directly under API root.

- How nesting works:
  - `orders` -> `path_part = "orders"` creates `/orders`.
  - `order_id` with `parent_key = "orders"` and `path_part = "{id}"` creates `/orders/{id}`.

### Method Inputs (`methods`)

- Purpose:
  - Defines the method contract exposed by API Gateway.
  - Each entry creates one `aws_api_gateway_method`.

- `resource_key`:
  - Resource entry key to attach method to.
  - Omit to attach method to root path `/`.

- `http_method`:
  - Request verb handled by this method.
  - Allowed: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`, `ANY`.

- `authorization`:
  - Auth mode:
    - `NONE`: public method (unless protected downstream).
    - `AWS_IAM`: SigV4 IAM auth.
    - `CUSTOM`: Lambda/custom authorizer.
    - `COGNITO_USER_POOLS`: Cognito authorizer.

- `authorizer_id`:
  - Required only when auth mode expects an authorizer (`CUSTOM`/`COGNITO_USER_POOLS`) and `authorizer_key` is not used.
  - Omit for `NONE` and `AWS_IAM` methods.

- `authorizer_key`:
  - Preferred way to attach a module-managed authorizer.
  - Must reference a key from `authorizers`.

### Authorizer Inputs (`authorizers`)

- Purpose:
  - Creates `aws_api_gateway_authorizer` resources in this module.

- `name`:
  - Authorizer display name.

- `type`:
  - `TOKEN`, `REQUEST`, or `COGNITO_USER_POOLS`.

- `authorizer_uri`:
  - Required for `TOKEN`/`REQUEST` authorizers.

- `provider_arns`:
  - Required for `COGNITO_USER_POOLS` authorizers.

- `identity_source`:
  - Optional source expression (defaults to `method.request.header.Authorization` for TOKEN/REQUEST).

- `authorizer_result_ttl_in_seconds`:
  - Optional cache TTL (`0` to `3600`).

- `api_key_required`:
  - If `true`, callers must provide API key and method must be under usage plan setup.

- `request_models`:
  - Request body model validation by content type.
  - Example: `{ "application/json" = "OrderInputModel" }`.

- `request_parameters`:
  - Required request params map.
  - Example:
    - `"method.request.path.id" = true`
    - `"method.request.querystring.limit" = false`

- `request_validator_id`:
  - Connects method to API Gateway request validator resource.

- `operation_name`:
  - Optional operation label for traceability and docs tooling.

### Integration Inputs (`integrations`)

- Purpose:
  - Connects a method to backend execution.
  - Each entry creates one `aws_api_gateway_integration`.

- `method_key`:
  - Method entry key this integration belongs to.

- `type`:
  - Backend integration type:
    - `AWS_PROXY`: Lambda proxy (most common Lambda mode).
    - `AWS`: non-proxy AWS service integration.
    - `HTTP_PROXY`: passthrough HTTP proxy.
    - `HTTP`: mapped HTTP integration.
    - `MOCK`: synthetic response for preflight/testing.

- `integration_http_method`:
  - HTTP method API Gateway uses to call backend.
  - For Lambda (`AWS_PROXY`), typically `POST`.

- `uri`:
  - Target backend URI (Lambda invoke URI/service endpoint URL).

- `connection_type` and `connection_id`:
  - Use `VPC_LINK` + VPC link ID for private integrations.
  - Default internet routing otherwise.

- `passthrough_behavior`:
  - Controls template passthrough when no mapping template matches.

- `request_templates`:
  - VTL templates for transforming incoming payload before backend call.

- `request_parameters`:
  - Request mapping between method and integration params.
  - Common for path/query/header forwarding in HTTP integrations.

- `content_handling`:
  - Payload conversion strategy for binary/text handling.

- `timeout_milliseconds`:
  - Backend timeout (50-29000).
  - Keep aligned with backend timeout and client expectations.

- `cache_key_parameters` and `cache_namespace`:
  - Fine-grained cache key behavior when API caching is enabled.

### Method Response Inputs (`method_responses`)

- Purpose:
  - Declares the response contract returned to client for a method/status.
  - Each entry creates one `aws_api_gateway_method_response`.

- `method_key`:
  - Method entry this response belongs to.

- `status_code`:
  - HTTP status code for this method response.

- `response_models`:
  - Response model mapping by content type.

- `response_parameters`:
  - Declares which response headers are exposed/expected.
  - Example: `"method.response.header.Access-Control-Allow-Origin" = true`.

### Integration Response Inputs (`integration_responses`)

- Purpose:
  - Maps backend response to method response.
  - Each entry creates one `aws_api_gateway_integration_response`.

- `method_response_key`:
  - Link to a `method_responses` entry.

- `status_code`:
  - Optional override; defaults to linked method response status code.

- `selection_pattern`:
  - Regex match for backend error pattern routing.

- `response_templates`:
  - VTL response transforms.

- `response_parameters`:
  - Maps backend headers/body values into method response headers.

- `content_handling`:
  - Response payload conversion behavior.

### Stage & Deployment Inputs

- `stage_name`:
  - Stage identifier in URL and API lifecycle.
  - Example invoke URL suffix: `/prod`.

- `stage_description`:
  - Stage metadata only.

- `deployment_description`:
  - Deployment metadata only.

- `stage_variables`:
  - Key-value vars available in mapping templates and stage context.

- `xray_tracing_enabled`:
  - Enables API Gateway X-Ray segment emission.

- `cache_cluster_enabled` and `cache_cluster_size`:
  - Controls stage-level cache cluster.
  - Use only when caching strategy is planned and measured.

- `method_settings`:
  - Global `*/*` method behavior:
    - logging/metrics
    - data tracing
    - throttling
    - caching controls
  - Good default place for operational guardrails.

### Access Logging Inputs

- `access_log_enabled`:
  - Turns stage access logs on.
  - Requires either module-created log group or external destination ARN.

- `create_access_log_group`:
  - If `true`, module creates CloudWatch log group for access logs.

- `access_log_group_name`:
  - Optional custom name for module-created access log group.

- `access_log_retention_in_days`:
  - Retention policy for module-created access log group.

- `access_log_kms_key_arn`:
  - Optional KMS encryption key for module-created access log group.

- `access_log_destination_arn`:
  - Use existing destination instead of creating one.

- `access_log_format`:
  - Final log line format.
  - Must include fields useful for debugging/auditing (`requestId`, `status`, etc.).

### Custom Domain & DNS Inputs

- `create_domain_name`:
  - Enables custom domain and base path mapping resources.

- `domain_name`:
  - Public hostname (for example `api.example.com`).

- `certificate_arn`:
  - ACM certificate ARN for custom domain TLS.

- `base_path`:
  - Base path mapping under domain.
  - `null` maps API stage at root path.

- `security_policy`:
  - Domain TLS policy (`TLS_1_0` or `TLS_1_2`).

- `create_route53_record`:
  - If `true`, module creates Route53 alias `A` record.

- `hosted_zone_id`:
  - Hosted zone for alias record creation.

- `record_name`:
  - DNS record name override.
  - Defaults to `domain_name` when omitted.

## Key Outputs

- `rest_api_id`
- `rest_api_execution_arn`
- `invoke_url`
- `resource_ids`
- `methods_index`
- `integration_ids`
- `custom_domain_name`
