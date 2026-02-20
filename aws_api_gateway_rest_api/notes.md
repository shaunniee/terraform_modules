# AWS API Gateway — Complete Engineering Reference Notes
> For use inside Terraform modules. Covers REST API (v1), HTTP API (v2), WebSocket API — every detail, feature, config, and Terraform resource reference.

---

## Table of Contents

1. [Core Concepts & API Types](#1-core-concepts--api-types)
2. [HTTP API (v2) — Deep Dive](#2-http-api-v2--deep-dive)
3. [REST API (v1) — Deep Dive](#3-rest-api-v1--deep-dive)
4. [WebSocket API — Deep Dive](#4-websocket-api--deep-dive)
5. [Integrations](#5-integrations)
6. [Authorizers & Authentication](#6-authorizers--authentication)
7. [Request / Response Transformation](#7-request--response-transformation)
8. [Stages & Deployments](#8-stages--deployments)
9. [Custom Domains & TLS](#9-custom-domains--tls)
10. [Throttling & Usage Plans](#10-throttling--usage-plans)
11. [CORS](#11-cors)
12. [Caching](#12-caching)
13. [Private APIs (VPC)](#13-private-apis-vpc)
14. [Canary Deployments](#14-canary-deployments)
15. [Mutual TLS (mTLS)](#15-mutual-tls-mtls)
16. [WAF Integration](#16-waf-integration)
17. [Observability — Access Logging](#17-observability--access-logging)
18. [Observability — Execution Logging](#18-observability--execution-logging)
19. [Observability — Metrics & Alarms](#19-observability--metrics--alarms)
20. [Observability — X-Ray Tracing](#20-observability--x-ray-tracing)
21. [Debugging & Troubleshooting](#21-debugging--troubleshooting)
22. [Cost Model](#22-cost-model)
23. [Limits & Quotas](#23-limits--quotas)
24. [Security Best Practices](#24-security-best-practices)
25. [Terraform Full Resource Reference](#25-terraform-full-resource-reference)

---

## 1. Core Concepts & API Types

### Three API Types

| Feature | HTTP API (v2) | REST API (v1) | WebSocket API |
|---|---|---|---|
| Protocol | HTTP/HTTPS | HTTP/HTTPS | WebSocket |
| Latency | ~6ms p50 | ~10ms p50 | N/A |
| Cost | ~70% cheaper than REST | Standard | Standard |
| Payload format | 1.0 or 2.0 | 1.0 | 1.0 |
| Lambda proxy | ✅ | ✅ | ✅ |
| Custom authorizers | ✅ JWT + Lambda | ✅ Lambda only | ✅ Lambda only |
| JWT authorizer | ✅ Native | ❌ | ❌ |
| Usage plans / API keys | ❌ | ✅ | ❌ |
| Request/response transform | ❌ | ✅ (mapping templates) | ❌ |
| Response caching | ❌ | ✅ | ❌ |
| Private APIs | ❌ | ✅ | ❌ |
| VPC Link | ✅ (NLB/ALB/Cloud Map) | ✅ (NLB only) | ❌ |
| mTLS | ✅ | ✅ | ❌ |
| WAF | ✅ | ✅ | ❌ |
| Custom domain | ✅ | ✅ | ✅ |
| Edge-optimized | ❌ | ✅ | ❌ |
| Regional | ✅ | ✅ | ✅ |
| X-Ray tracing | ✅ | ✅ | ❌ |
| Terraform resource | `aws_apigatewayv2_*` | `aws_api_gateway_*` | `aws_apigatewayv2_*` |

### When to Choose Which
- **HTTP API**: Default choice. Simpler, faster, cheaper. Use when you don't need usage plans, caching, edge-optimized, or VTL transforms.
- **REST API**: When you need API keys + usage plans, request/response mapping templates, edge-optimized CDN distribution, private VPC-only APIs, or response caching.
- **WebSocket API**: Real-time bidirectional communication (chat, live dashboards, gaming, notifications).

### Request Flow
```
Client
  └─→ CloudFront (edge-optimized) or Regional Endpoint
        └─→ API Gateway
              ├─→ Authorizer (Lambda / Cognito / JWT)
              ├─→ WAF (if attached)
              ├─→ Throttle check
              ├─→ Cache check (REST only)
              ├─→ Request mapping (REST only)
              ├─→ Integration (Lambda / HTTP / VPC Link / Mock / AWS Service)
              ├─→ Response mapping (REST only)
              └─→ Client Response
```

---

## 2. HTTP API (v2) — Deep Dive

### Terraform: Create HTTP API
```hcl
resource "aws_apigatewayv2_api" "this" {
  name          = var.api_name
  protocol_type = "HTTP"
  description   = var.description

  # CORS (built-in for HTTP API)
  cors_configuration {
    allow_origins     = ["https://app.example.com"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Api-Key"]
    expose_headers    = ["X-Request-Id"]
    allow_credentials = true
    max_age           = 86400
  }

  tags = var.tags
}
```

### Routes
- Format: `METHOD /path` e.g. `GET /users`, `POST /orders/{orderId}`
- Special routes: `$default` (catch-all), `$connect`, `$disconnect`, `$default` (WebSocket)
- Path parameters: `{param}`, `{param+}` (greedy)

```hcl
resource "aws_apigatewayv2_route" "get_users" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "GET /users"

  target                = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type    = "JWT"         # "NONE", "JWT", "AWS_IAM", "CUSTOM"
  authorizer_id         = aws_apigatewayv2_authorizer.jwt.id
  authorization_scopes  = ["api:read"]  # required scope(s)

  # Request parameters mapping
  request_parameter {
    request_parameter_key = "route.request.header.X-User-Id"
    required              = false
  }
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}
```

### Integration (Lambda Proxy)
```hcl
resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.this.invoke_arn

  payload_format_version = "2.0"  # "1.0" or "2.0" — use 2.0 for HTTP API
  timeout_milliseconds   = 29000  # max 29000ms for HTTP API

  # For response streaming
  # integration_method = "POST"
}
```

### Stage
```hcl
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name  # e.g. "prod", "$default"
  auto_deploy = true

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
  }

  # Default route throttle
  default_route_settings {
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
    detailed_metrics_enabled = true
    logging_level          = "INFO"  # REST only; not used for HTTP API
    data_trace_enabled     = false
  }

  # Per-route overrides
  route_settings {
    route_key              = "POST /orders"
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
    detailed_metrics_enabled = true
  }

  stage_variables = {
    env = var.environment
  }

  tags = var.tags
}
```

### Payload Format 1.0 vs 2.0

**Format 1.0** (compatible with REST API proxy):
```json
{
  "httpMethod": "GET",
  "path": "/users",
  "headers": { "Authorization": "Bearer ..." },
  "queryStringParameters": { "limit": "10" },
  "body": null,
  "isBase64Encoded": false
}
```

**Format 2.0** (recommended for HTTP API):
```json
{
  "version": "2.0",
  "routeKey": "GET /users",
  "rawPath": "/users",
  "rawQueryString": "limit=10",
  "headers": { "authorization": "Bearer ..." },
  "queryStringParameters": { "limit": "10" },
  "requestContext": {
    "accountId": "123456789012",
    "apiId": "abc123",
    "domainName": "api.example.com",
    "http": {
      "method": "GET",
      "path": "/users",
      "sourceIp": "1.2.3.4",
      "userAgent": "..."
    },
    "requestId": "abc-123",
    "routeKey": "GET /users",
    "stage": "prod",
    "time": "..."
  },
  "body": null,
  "isBase64Encoded": false
}
```

---

## 3. REST API (v1) — Deep Dive

### API Types
| Type | Description |
|---|---|
| `EDGE` | CloudFront-distributed, globally optimized. Certificate must be in `us-east-1`. |
| `REGIONAL` | Single region. Use with CloudFront manually for caching control. |
| `PRIVATE` | Only accessible within VPC via VPC endpoint. |

```hcl
resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = var.description

  endpoint_configuration {
    types            = ["REGIONAL"]  # "EDGE", "REGIONAL", "PRIVATE"
    vpc_endpoint_ids = []  # required for PRIVATE
  }

  # Binary media types (for file uploads/downloads)
  binary_media_types = ["multipart/form-data", "image/*", "application/octet-stream"]

  # Minimum compression size (bytes); -1 = disabled
  minimum_compression_size = 1024

  # API policy (for PRIVATE or cross-account)
  policy = data.aws_iam_policy_document.api_policy.json

  tags = var.tags
}
```

### Resources & Methods

```hcl
# Root-level resource: /users
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "users"
}

# Nested resource: /users/{userId}
resource "aws_api_gateway_resource" "user" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{userId}"
}

# Method: GET /users/{userId}
resource "aws_api_gateway_method" "get_user" {
  rest_api_id          = aws_api_gateway_rest_api.this.id
  resource_id          = aws_api_gateway_resource.user.id
  http_method          = "GET"
  authorization        = "COGNITO_USER_POOLS"  # "NONE", "AWS_IAM", "CUSTOM", "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito.id
  authorization_scopes = ["api:read"]

  api_key_required = false

  # Validate request body / params
  request_validator_id = aws_api_gateway_request_validator.this.id

  # Parameter validation / mapping
  request_parameters = {
    "method.request.path.userId"         = true   # required path param
    "method.request.header.X-Request-Id" = false  # optional header
    "method.request.querystring.limit"   = false
  }

  request_models = {
    "application/json" = aws_api_gateway_model.user_request.name
  }
}
```

### Request Validator
```hcl
resource "aws_api_gateway_request_validator" "this" {
  rest_api_id           = aws_api_gateway_rest_api.this.id
  name                  = "validate-body-params"
  validate_request_body = true
  validate_request_parameters = true
}
```

### Models (JSON Schema)
```hcl
resource "aws_api_gateway_model" "user_request" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
  name         = "UserRequest"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "UserRequest"
    type      = "object"
    required  = ["name", "email"]
    properties = {
      name  = { type = "string" }
      email = { type = "string", format = "email" }
      age   = { type = "integer", minimum = 0 }
    }
  })
}
```

### Integration (Lambda)
```hcl
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.get_user.http_method

  integration_http_method = "POST"       # Lambda always uses POST
  type                    = "AWS_PROXY"  # "AWS", "AWS_PROXY", "HTTP", "HTTP_PROXY", "MOCK"
  uri                     = aws_lambda_function.this.invoke_arn

  # Timeout: 50ms - 29000ms
  timeout_milliseconds = 29000

  # For non-proxy (AWS) integration only — request mapping
  # request_templates = {
  #   "application/json" = file("${path.module}/mapping/request.vtl")
  # }

  # Pass-through behavior for non-proxy
  # passthrough_behavior = "WHEN_NO_TEMPLATES"  # WHEN_NO_TEMPLATES | WHEN_NO_MATCH | NEVER

  # Request parameter mapping
  request_parameters = {
    "integration.request.header.X-User-Id" = "method.request.header.X-User-Id"
  }
}
```

### Method Response & Integration Response (non-proxy)
```hcl
resource "aws_api_gateway_method_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.user.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
    "method.response.header.X-Request-Id"               = false
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "ok" {
  rest_api_id       = aws_api_gateway_rest_api.this.id
  resource_id       = aws_api_gateway_resource.user.id
  http_method       = aws_api_gateway_method.get_user.http_method
  status_code       = aws_api_gateway_method_response.ok.status_code
  selection_pattern = ""  # regex to match; "" = default/success

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
    "method.response.header.X-Request-Id"               = "integration.response.header.X-Request-Id"
  }

  response_templates = {
    "application/json" = ""  # passthrough or VTL
  }
}
```

### Deployment & Stage (REST API)
```hcl
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    # Force redeploy when any API resource changes
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.users.id,
      aws_api_gateway_method.get_user.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name  # e.g. "prod", "v1"
  description   = "Production stage"

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
  }

  # Execution logging
  xray_tracing_enabled = true

  # Stage-level throttle
  default_route_settings {  # REST uses method_settings below
  }

  # Variables available in mapping templates / Lambda as context.stage
  variables = {
    env             = var.environment
    lambda_alias    = "live"
  }

  # Cache cluster
  cache_cluster_enabled = var.enable_cache
  cache_cluster_size    = "0.5"  # GB: "0.5","1.6","6.1","13.5","28.4","58.2","118","237"

  tags = var.tags
}

# Per-method settings (logging, throttle, cache)
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"  # "resource/METHOD" or "*/*" for all

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"  # "OFF", "ERROR", "INFO"
    data_trace_enabled     = false   # full request/response logging (expensive!)
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
    caching_enabled        = false
    cache_ttl_in_seconds   = 300
    cache_data_encrypted   = true
    require_authorization_for_cache_control = true
    unauthorized_cache_control_header_strategy = "SUCCEED_WITH_RESPONSE_HEADER"
  }
}
```

---

## 4. WebSocket API — Deep Dive

### Concepts
- **Routes**: `$connect`, `$disconnect`, `$default`, custom action-based routes.
- **Connection ID**: Unique ID per connection, used to send messages back to clients.
- **Callback URL**: `https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/@connections/{connectionId}`

```hcl
resource "aws_apigatewayv2_api" "ws" {
  name                       = "${var.api_name}-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"  # key to route on
  description                = "WebSocket API"

  tags = var.tags
}

# $connect route
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
  authorization_type = "NONE"  # or "AWS_IAM" or "CUSTOM"
}

# $disconnect route
resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect.id}"
}

# $default route (catch-all)
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.default.id}"
}

# Custom action route
resource "aws_apigatewayv2_route" "message" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "sendMessage"
  target    = "integrations/${aws_apigatewayv2_integration.message.id}"
}

resource "aws_apigatewayv2_integration" "connect" {
  api_id             = aws_apigatewayv2_api.ws.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_connect.invoke_arn
  payload_format_version = "1.0"  # WebSocket only supports 1.0
}

resource "aws_apigatewayv2_stage" "ws" {
  api_id      = aws_apigatewayv2_api.ws.id
  name        = "prod"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit   = 1000
    throttling_rate_limit    = 500
    data_trace_enabled       = false
    detailed_metrics_enabled = true
    logging_level            = "INFO"
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.ws_access.arn
  }
}
```

### Sending Messages to Clients (Lambda)
```python
import boto3

def send_to_connection(api_id, stage, region, connection_id, data):
    endpoint = f"https://{api_id}.execute-api.{region}.amazonaws.com/{stage}"
    client = boto3.client("apigatewaymanagementapi", endpoint_url=endpoint)
    try:
        client.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(data).encode()
        )
    except client.exceptions.GoneException:
        # Connection is stale — delete from your DB
        pass
```

### IAM for Lambda to Send to Connections
```hcl
data "aws_iam_policy_document" "ws_send" {
  statement {
    effect  = "Allow"
    actions = ["execute-api:ManageConnections"]
    resources = [
      "${aws_apigatewayv2_api.ws.execution_arn}/${var.stage}/@connections/*"
    ]
  }
}
```

---

## 5. Integrations

### Integration Types

| Type | Description | Use Case |
|---|---|---|
| `AWS_PROXY` | Lambda proxy — full event passthrough | Lambda (recommended) |
| `AWS` | AWS service action with mapping templates | Invoke Lambda, SQS, DynamoDB directly |
| `HTTP_PROXY` | HTTP passthrough to backend URL | Upstream HTTP service |
| `HTTP` | HTTP with mapping templates | HTTP with transform |
| `MOCK` | Respond directly from API GW (no backend) | Health checks, CORS OPTIONS, testing |

### HTTP Proxy Integration (to backend service)
```hcl
resource "aws_apigatewayv2_integration" "http_backend" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "https://internal-service.example.com/{proxy}"

  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id

  timeout_milliseconds = 15000
}
```

### Direct AWS Service Integration (REST, non-proxy)
Example: API GW → SQS (no Lambda needed)
```hcl
resource "aws_api_gateway_integration" "sqs" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.queue.id
  http_method             = "POST"
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.this.name}"
  credentials             = aws_iam_role.apigw_sqs.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}
```

### Mock Integration (CORS OPTIONS or health check)
```hcl
resource "aws_api_gateway_integration" "options_mock" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = "OPTIONS"
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}
```

### VPC Link (HTTP API → private ALB/NLB)
```hcl
resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.api_name}-vpc-link"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = var.private_subnet_ids

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.internal.arn  # ALB listener ARN
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id
}
```

### VPC Link (REST API → private NLB)
```hcl
resource "aws_api_gateway_vpc_link" "this" {
  name        = "${var.api_name}-vpc-link"
  target_arns = [aws_lb.internal.arn]  # NLB only for REST API VPC Link

  tags = var.tags
}

resource "aws_api_gateway_integration" "nlb" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = "ANY"
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${aws_lb.internal.dns_name}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.this.id
}
```

---

## 6. Authorizers & Authentication

### Auth Types Summary

| Type | API | Description |
|---|---|---|
| `NONE` | All | No auth — public endpoint |
| `AWS_IAM` | HTTP + REST | SigV4 signed requests (IAM users/roles) |
| `JWT` | HTTP only | Native JWT validation (Cognito / any OIDC) |
| `COGNITO_USER_POOLS` | REST only | Cognito User Pool token validation |
| `CUSTOM` (Lambda) | All | Custom auth logic in Lambda |

### JWT Authorizer (HTTP API — recommended for Cognito)
```hcl
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  name             = "cognito-jwt"
  identity_sources = ["$request.header.Authorization"]  # where to find token

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}
```

### Cognito Authorizer (REST API)
```hcl
resource "aws_api_gateway_authorizer" "cognito" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  name        = "cognito-authorizer"
  type        = "COGNITO_USER_POOLS"

  provider_arns = [aws_cognito_user_pool.this.arn]

  # Where to find the token
  identity_source = "method.request.header.Authorization"

  # Optional: comma-separated list of scopes to check
  # For COGNITO type, scopes are checked at the method level (authorization_scopes)
}
```

### Lambda Authorizer (REST API) — Token-based
```hcl
resource "aws_api_gateway_authorizer" "lambda_token" {
  rest_api_id                      = aws_api_gateway_rest_api.this.id
  name                             = "lambda-token-authorizer"
  type                             = "TOKEN"                       # "TOKEN" or "REQUEST"
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials           = aws_iam_role.apigw_authorizer.arn
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300  # 0 = no caching, max 3600
  identity_validation_expression   = "^Bearer [-0-9a-zA-Z\\._]*$"  # regex pre-check
}
```

### Lambda Authorizer (REST API) — Request-based
```hcl
resource "aws_api_gateway_authorizer" "lambda_request" {
  rest_api_id     = aws_api_gateway_rest_api.this.id
  name            = "lambda-request-authorizer"
  type            = "REQUEST"
  authorizer_uri  = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.apigw_authorizer.arn

  # Can use multiple sources: headers, querystring, context, stageVariables
  identity_source = "method.request.header.Authorization, method.request.querystring.api_key"

  authorizer_result_ttl_in_seconds = 0  # disable caching for request authorizers
}
```

### Lambda Authorizer (HTTP API)
```hcl
resource "aws_apigatewayv2_authorizer" "lambda" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "REQUEST"
  name             = "lambda-authorizer"

  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials_arn        = aws_iam_role.apigw_authorizer.arn
  authorizer_result_ttl_in_seconds  = 300
  authorizer_payload_format_version = "2.0"  # "1.0" or "2.0"
  enable_simple_responses           = true   # true: return {isAuthorized: bool}, false: return IAM policy

  identity_sources = ["$request.header.Authorization"]
}
```

### Lambda Authorizer Response — Simple (HTTP API v2.0)
```python
def handler(event, context):
    token = event["identitySource"][0]  # the header value
    if valid(token):
        return {
            "isAuthorized": True,
            "context": {
                "userId": "user-123",
                "tenantId": "tenant-456"
            }
        }
    return {"isAuthorized": False}
```

### Lambda Authorizer Response — IAM Policy (REST API)
```python
def handler(event, context):
    token = event["authorizationToken"]
    if valid(token):
        return {
            "principalId": "user-123",
            "policyDocument": {
                "Version": "2012-10-17",
                "Statement": [{
                    "Action": "execute-api:Invoke",
                    "Effect": "Allow",
                    "Resource": event["methodArn"]  # or "*" for wildcard
                }]
            },
            "context": {
                "userId": "user-123"  # available in $context.authorizer.userId
            },
            "usageIdentifierKey": "optional-key-for-usage-plan"
        }
```

### IAM for API GW to invoke Lambda authorizer
```hcl
resource "aws_iam_role" "apigw_authorizer" {
  name = "${var.api_name}-authorizer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "apigw_authorizer" {
  role = aws_iam_role.apigw_authorizer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.authorizer.arn
    }]
  })
}

resource "aws_lambda_permission" "apigw_authorizer" {
  statement_id  = "AllowAPIGWAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/authorizers/${aws_api_gateway_authorizer.lambda_token.id}"
}
```

### API Keys (REST API only)
```hcl
resource "aws_api_gateway_api_key" "client" {
  name        = "${var.api_name}-client-key"
  description = "API key for client"
  enabled     = true
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.api_name}-usage-plan"
  description = "Standard usage plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name

    # Per-method throttle within usage plan
    throttle {
      path        = "/users/GET"
      burst_limit = 100
      rate_limit  = 50
    }
  }

  quota_settings {
    limit  = 10000
    offset = 0
    period = "MONTH"  # "DAY", "WEEK", "MONTH"
  }

  throttle_settings {
    burst_limit = 500
    rate_limit  = 1000
  }
}

resource "aws_api_gateway_usage_plan_key" "this" {
  key_id        = aws_api_gateway_api_key.client.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}
```

---

## 7. Request / Response Transformation

> Only available in REST API (v1) via Velocity Template Language (VTL). HTTP API has limited parameter mapping.

### VTL Context Variables
```
$context.requestId          — Unique request ID
$context.identity.sourceIp  — Client IP
$context.authorizer.userId  — From authorizer context
$context.stage              — Stage name
$context.stageVariables.myVar — Stage variables

$input.body                 — Raw request body (string)
$input.json('$.field')      — JSONPath on body
$input.params('paramName')  — Path/query/header param
$util.urlEncode(str)        — URL encode
$util.urlDecode(str)        — URL decode
$util.escapeJavaScript(str) — Escape for JS
$util.base64Encode(str)     — Base64 encode
$util.base64Decode(str)     — Base64 decode
```

### Request Mapping Template Example
```vtl
## Pass selected fields to Lambda
{
  "userId": "$input.params('userId')",
  "requestBody": $input.json('$'),
  "requestId": "$context.requestId",
  "sourceIp": "$context.identity.sourceIp",
  "stage": "$context.stage"
}
```

### Response Mapping Template
```vtl
## Wrap response in standard envelope
{
  "success": true,
  "data": $input.json('$'),
  "requestId": "$context.requestId"
}
```

### HTTP API Parameter Mapping (limited, no VTL)
```hcl
resource "aws_apigatewayv2_integration" "this" {
  api_id           = aws_apigatewayv2_api.this.id
  integration_type = "HTTP_PROXY"
  integration_uri  = "https://backend.example.com"

  request_parameters = {
    "append:header.X-Forwarded-For" = "$context.identity.sourceIp"
    "overwrite:path"                = "/v2$request.path"
    "remove:header.X-Internal"      = "''"
  }

  response_parameters {
    status_code = "200"
    mappings = {
      "append:header.X-Request-Id" = "$context.requestId"
    }
  }
}
```

---

## 8. Stages & Deployments

### REST API Deployment Strategy
- Every change to resources/methods/integrations requires a new **Deployment**.
- Deployments are immutable snapshots.
- Use `triggers` with `sha1(jsonencode(...))` to force redeploy on change.
- `create_before_destroy = true` prevents downtime.

```hcl
# Collect all API resources into a hash for change detection
locals {
  api_resources_hash = sha1(jsonencode([
    aws_api_gateway_rest_api.this.body,
    aws_api_gateway_resource.users.id,
    aws_api_gateway_method.get_users.id,
    aws_api_gateway_integration.lambda.id,
    aws_api_gateway_method_response.ok.id,
    aws_api_gateway_integration_response.ok.id,
    aws_api_gateway_authorizer.cognito.id,
  ]))
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  triggers    = { redeployment = local.api_resources_hash }
  lifecycle   { create_before_destroy = true }
}
```

### HTTP API — Auto Deploy
```hcl
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "prod"
  auto_deploy = true  # automatically deploy on changes
}
```

### Stage Variables (REST)
- Accessible in mapping templates as `$stageVariables.varName`.
- Accessible in Lambda via event: `event.stageVariables.varName`.
- Useful to point to different Lambda aliases per stage.

```hcl
resource "aws_api_gateway_stage" "this" {
  variables = {
    lambdaAlias = "live"
    backendUrl  = "https://backend-${var.environment}.internal"
  }
}

# In integration URI, use stage variable:
# arn:aws:apigateway:region:lambda:path/functions/arn:aws:lambda:region:account:function:name:${stageVariables.lambdaAlias}/invocations
```

---

## 9. Custom Domains & TLS

### Custom Domain (HTTP API or REST API)
```hcl
resource "aws_acm_certificate" "api" {
  domain_name       = "api.example.com"
  validation_method = "DNS"
  # For EDGE REST API: certificate MUST be in us-east-1
  # For REGIONAL or HTTP API: certificate in same region as API

  tags = var.tags
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_acm_certificate.api.domain_validation_options : r.resource_record_name]
}

resource "aws_apigatewayv2_domain_name" "this" {
  domain_name = "api.example.com"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"  # "TLS_1_0" or "TLS_1_2"
  }

  # mTLS truststore (optional)
  # mutual_tls_authentication {
  #   truststore_uri     = "s3://${aws_s3_bucket.truststore.bucket}/truststore.pem"
  #   truststore_version = aws_s3_object.truststore.version_id
  # }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this.id
  stage       = aws_apigatewayv2_stage.this.id
  api_mapping_key = ""  # "" = root, "v1" = api.example.com/v1
}

# Route53 alias to API GW regional endpoint
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "api.example.com"
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
```

### REST API Custom Domain
```hcl
resource "aws_api_gateway_domain_name" "this" {
  domain_name              = "api.example.com"
  regional_certificate_arn = aws_acm_certificate.api.arn  # regional_certificate_arn for REGIONAL
  # certificate_arn        = aws_acm_certificate.api.arn  # certificate_arn for EDGE (us-east-1)

  endpoint_configuration {
    types = ["REGIONAL"]  # or ["EDGE"]
  }

  security_policy = "TLS_1_2"

  tags = var.tags
}

resource "aws_api_gateway_base_path_mapping" "this" {
  api_id      = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  domain_name = aws_api_gateway_domain_name.this.domain_name
  base_path   = "v1"  # empty = root mapping
}
```

---

## 10. Throttling & Usage Plans

### Throttling Hierarchy (REST API)
```
Account limit (10,000 rps default, adjustable)
  └─→ Stage-level throttle (method_settings */* or stage default)
        └─→ Usage plan throttle (per API key)
              └─→ Per-route/method throttle
```

### Stage-Level Throttle (REST API)
```hcl
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 5000   # concurrent requests
    throttling_rate_limit  = 10000  # requests/second (steady state)
  }
}
```

### HTTP API Throttle
```hcl
resource "aws_apigatewayv2_stage" "this" {
  default_route_settings {
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
  }
}
```

### Throttle Error Responses
- `429 Too Many Requests` — throttled by API GW.
- `503 Service Unavailable` — downstream (Lambda) throttled.
- Use exponential backoff with jitter in clients.

---

## 11. CORS

### HTTP API — Built-in CORS (simplest)
```hcl
resource "aws_apigatewayv2_api" "this" {
  cors_configuration {
    allow_origins     = ["https://app.example.com", "https://admin.example.com"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Api-Key", "X-Amz-Date"]
    expose_headers    = ["X-Request-Id", "X-Response-Time"]
    allow_credentials = true
    max_age           = 86400
  }
}
```

### REST API — Manual CORS (OPTIONS method + integration responses)
```hcl
# OPTIONS method
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = "OPTIONS"
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = "OPTIONS"
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Max-Age"       = true
  }
  response_models = { "application/json" = "Empty" }
}

resource "aws_api_gateway_integration_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = "OPTIONS"
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://app.example.com'"
    "method.response.header.Access-Control-Max-Age"       = "'86400'"
  }
}

# Also add CORS headers to actual method responses
resource "aws_api_gateway_method_response" "get_ok" {
  # ...
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "get_ok" {
  # ...
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}
```

---

## 12. Caching

> REST API only. Not available in HTTP API.

### Enable Cache
```hcl
resource "aws_api_gateway_stage" "this" {
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"  # GB: 0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237
}

resource "aws_api_gateway_method_settings" "cached" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "users/GET"

  settings {
    caching_enabled      = true
    cache_ttl_in_seconds = 300   # 0-3600; 0 = disable
    cache_data_encrypted = true

    # Allow clients to invalidate cache with Cache-Control: max-age=0
    require_authorization_for_cache_control = true
    unauthorized_cache_control_header_strategy = "SUCCEED_WITH_RESPONSE_HEADER"
    # Options: FAIL_WITH_403, SUCCEED_WITH_RESPONSE_HEADER, SUCCEED_WITHOUT_RESPONSE_HEADER
  }
}
```

### Cache Key (per-method)
- Default cache key = full request path.
- Add query parameters and headers to cache key:

```hcl
resource "aws_api_gateway_method" "get_users" {
  request_parameters = {
    "method.request.querystring.limit"  = false
    "method.request.querystring.offset" = false
  }
}

resource "aws_api_gateway_integration" "lambda" {
  cache_key_parameters = [
    "method.request.querystring.limit",
    "method.request.querystring.offset"
  ]
  cache_namespace = "userCache"
}
```

### Cache Invalidation
- Header: `Cache-Control: max-age=0` (if authorized).
- AWS CLI: `aws apigateway flush-stage-cache --rest-api-id ... --stage-name ...`

---

## 13. Private APIs (VPC)

> REST API only.

```hcl
resource "aws_api_gateway_rest_api" "private" {
  name = "${var.api_name}-private"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.apigw.id]
  }

  # Resource policy — restrict access to specific VPC endpoint
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "execute-api:/*"
        Condition = {
          StringEquals = {
            "aws:SourceVpce" = aws_vpc_endpoint.apigw.id
          }
        }
      }
    ]
  })
}

resource "aws_vpc_endpoint" "apigw" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = var.tags
}
```

---

## 14. Canary Deployments

> REST API only.

```hcl
resource "aws_api_gateway_stage" "this" {
  canary_settings {
    percent_traffic          = 10.0  # % of traffic to canary
    stage_variable_overrides = {
      lambdaAlias = "canary"
    }
    use_stage_cache = false
  }
}

# After validation, promote canary:
# aws apigateway update-stage --rest-api-id ... --stage-name ... \
#   --patch-operations op=remove,path=/canarySettings
```

---

## 15. Mutual TLS (mTLS)

```hcl
# Upload truststore to S3
resource "aws_s3_object" "truststore" {
  bucket = aws_s3_bucket.truststore.id
  key    = "truststore.pem"
  source = "certs/truststore.pem"
}

resource "aws_apigatewayv2_domain_name" "mtls" {
  domain_name = "secure-api.example.com"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  mutual_tls_authentication {
    truststore_uri     = "s3://${aws_s3_bucket.truststore.bucket}/${aws_s3_object.truststore.key}"
    truststore_version = aws_s3_object.truststore.version_id
  }
}
```

---

## 16. WAF Integration

```hcl
resource "aws_wafv2_web_acl" "api" {
  name  = "${var.api_name}-waf"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitRule"
    priority = 2
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000  # requests per 5-minute window
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.api_name}-waf"
    sampled_requests_enabled   = true
  }
}

# Associate WAF with HTTP API stage
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_apigatewayv2_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

# Associate WAF with REST API stage
resource "aws_wafv2_web_acl_association" "rest" {
  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
```

---

## 17. Observability — Access Logging

### Access Log Format Variables
```
$context.requestId              — Unique request ID
$context.identity.sourceIp      — Client IP
$context.httpMethod             — HTTP method
$context.routeKey               — Route key (HTTP API)
$context.resourcePath           — Path (REST API)
$context.status                 — Response HTTP status
$context.responseLength         — Response size in bytes
$context.requestTime            — Request timestamp (CLF)
$context.requestTimeEpoch       — Request timestamp (Unix ms)
$context.integrationLatency     — Backend latency in ms
$context.responseLatency        — Total API GW latency in ms
$context.error.message          — Error message (if any)
$context.error.responseType     — Error type
$context.authorizer.principalId — Auth principal
$context.authorizer.userId      — From authorizer context map
$context.identity.userAgent     — Client User-Agent
$context.domainName             — Custom domain (if any)
$context.apiId                  — API ID
$context.stage                  — Stage name
$context.protocol               — HTTP/1.1 or HTTP/2
```

### JSON Access Log Setup
```hcl
resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.api_name}/access"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# HTTP API
resource "aws_apigatewayv2_stage" "this" {
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
  }
}

# REST API — log format set in stage access_log_settings
resource "aws_api_gateway_stage" "this" {
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    # Format string — use JSON for structured logging
  }
}
```

### Access Log Format String (use in stage resource or console)
```json
{
  "requestId": "$context.requestId",
  "sourceIp": "$context.identity.sourceIp",
  "method": "$context.httpMethod",
  "path": "$context.path",
  "routeKey": "$context.routeKey",
  "status": "$context.status",
  "protocol": "$context.protocol",
  "responseLength": "$context.responseLength",
  "requestTime": "$context.requestTime",
  "integrationLatency": "$context.integrationLatency",
  "responseLatency": "$context.responseLatency",
  "userAgent": "$context.identity.userAgent",
  "errorMessage": "$context.error.message",
  "authorizerError": "$context.authorizer.error",
  "userId": "$context.authorizer.userId",
  "stage": "$context.stage",
  "apiId": "$context.apiId"
}
```

### IAM for API GW to write logs
```hcl
resource "aws_iam_role" "apigw_logs" {
  name = "APIGatewayCloudWatchLogsRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_logs" {
  role       = aws_iam_role.apigw_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Must be set once per account per region
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_logs.arn
}
```

---

## 18. Observability — Execution Logging

> REST API only (HTTP API has access logging only).

```hcl
resource "aws_cloudwatch_log_group" "execution" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.this.id}/${var.stage_name}"
  retention_in_days = 7  # execution logs are verbose; short retention
  tags              = var.tags
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"   # "OFF", "ERROR", "INFO"
    data_trace_enabled = false    # logs full request/response — VERY verbose, use for debugging only
  }
}
```

### Execution Log Content
- `INFO`: Method request details, authorization decisions, integration request/response, method response.
- `ERROR`: Only errors.
- `data_trace_enabled = true`: Full request/response body logged — use only temporarily for debugging.

---

## 19. Observability — Metrics & Alarms

### Built-in CloudWatch Metrics (namespace: `AWS/ApiGateway`)

| Metric | Description | Stat |
|---|---|---|
| `Count` | Total API calls | Sum |
| `4XXError` | Client errors (400-499) | Sum, Avg |
| `5XXError` | Server errors (500-599) | Sum, Avg |
| `Latency` | Total end-to-end latency (including integration) | Avg, p50, p95, p99 |
| `IntegrationLatency` | Backend latency only | Avg, p50, p95, p99 |
| `CacheHitCount` | Cache hits | Sum |
| `CacheMissCount` | Cache misses | Sum |
| `DataProcessed` | Data transferred (bytes) | Sum |

### Dimensions
- REST API: `ApiName`, `Method`, `Resource`, `Stage`
- HTTP API: `ApiId`, `Stage`

### CloudWatch Alarms
```hcl
resource "aws_cloudwatch_metric_alarm" "5xx" {
  alarm_name          = "${var.api_name}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.this.name
    Stage   = aws_api_gateway_stage.this.stage_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "4xx" {
  alarm_name          = "${var.api_name}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 100  # tune based on expected traffic
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.this.name
    Stage   = aws_api_gateway_stage.this.stage_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "p99_latency" {
  alarm_name          = "${var.api_name}-p99-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 5000  # 5 seconds

  metric_name        = "Latency"
  namespace          = "AWS/ApiGateway"
  period             = 60
  extended_statistic = "p99"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.this.name
    Stage   = aws_api_gateway_stage.this.stage_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

### CloudWatch Logs Insights Queries

```
# Error rate over time
fields @timestamp, status, routeKey, integrationLatency
| filter status >= 400
| stats count() as errors by bin(5min)

# Slowest routes
fields @timestamp, routeKey, responseLatency
| stats avg(responseLatency) as avgLatency, max(responseLatency) as maxLatency, count() as requests
  by routeKey
| sort avgLatency desc

# Client error breakdown
fields @timestamp, status, errorMessage
| filter status >= 400 and status < 500
| stats count() by status, errorMessage

# Integration latency vs API GW overhead
fields @timestamp, routeKey,
  responseLatency - integrationLatency as apigwOverhead,
  integrationLatency
| stats avg(apigwOverhead), avg(integrationLatency) by routeKey
| sort avg(apigwOverhead) desc

# 429 throttle events
fields @timestamp, sourceIp, routeKey
| filter status = 429
| stats count() by sourceIp
| sort count() desc

# Auth failures
fields @timestamp, sourceIp, errorMessage
| filter errorMessage like /Unauthorized|Forbidden|Token/
| sort @timestamp desc
```

### CloudWatch Dashboard
```hcl
resource "aws_cloudwatch_dashboard" "api" {
  dashboard_name = "${var.api_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title   = "Request Count & Error Rate"
          metrics = [
            ["AWS/ApiGateway", "Count",    "ApiName", var.api_name, "Stage", var.stage_name, { stat = "Sum" }],
            ["AWS/ApiGateway", "5XXError", "ApiName", var.api_name, "Stage", var.stage_name, { stat = "Sum", color = "#d62728" }],
            ["AWS/ApiGateway", "4XXError", "ApiName", var.api_name, "Stage", var.stage_name, { stat = "Sum", color = "#ff7f0e" }],
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Latency"
          metrics = [
            ["AWS/ApiGateway", "Latency",            "ApiName", var.api_name, "Stage", var.stage_name, { stat = "p50", label = "p50" }],
            ["AWS/ApiGateway", "Latency",            "ApiName", var.api_name, "Stage", var.stage_name, { stat = "p95", label = "p95" }],
            ["AWS/ApiGateway", "Latency",            "ApiName", var.api_name, "Stage", var.stage_name, { stat = "p99", label = "p99" }],
            ["AWS/ApiGateway", "IntegrationLatency", "ApiName", var.api_name, "Stage", var.stage_name, { stat = "avg", label = "Integration avg" }],
          ]
          period = 60
        }
      }
    ]
  })
}
```

---

## 20. Observability — X-Ray Tracing

### Enable X-Ray (REST API)
```hcl
resource "aws_api_gateway_stage" "this" {
  xray_tracing_enabled = true
}
```

### Enable X-Ray (HTTP API)
```hcl
resource "aws_apigatewayv2_stage" "this" {
  # X-Ray not yet native for HTTP API
  # Use custom tracing via Lambda X-Ray or OpenTelemetry
}
```

### X-Ray Context in Lambda
- When API GW tracing is enabled, it automatically adds `X-Amzn-Trace-Id` header.
- Lambda X-Ray SDK reads this header and continues the trace.
- Service map shows: `Client → API Gateway → Lambda → [downstream services]`

### X-Ray Sampling
```hcl
resource "aws_xray_sampling_rule" "apigw" {
  rule_name      = "${var.api_name}-sampling"
  priority       = 500
  version        = 1
  reservoir_size = 10
  fixed_rate     = 0.05
  url_path       = "/api/*"
  host           = "api.example.com"
  http_method    = "*"
  service_type   = "AWS::ApiGateway::Stage"
  service_name   = "${var.api_name}/${var.stage_name}"
  resource_arn   = "*"
}
```

---

## 21. Debugging & Troubleshooting

### Common HTTP Error Codes from API GW

| Code | Source | Common Cause |
|---|---|---|
| `400 Bad Request` | API GW | Request validation failed, malformed body |
| `403 Forbidden` | API GW | Missing/invalid API key; WAF block; resource policy deny; IAM auth failure |
| `403 Missing Authentication Token` | API GW | Route doesn't exist (not auth issue!) |
| `404 Not Found` | API GW | Route not found |
| `429 Too Many Requests` | API GW | Throttled by stage/usage plan |
| `500 Internal Server Error` | API GW | Integration config error, bad mapping template |
| `502 Bad Gateway` | API GW | Lambda returned invalid response format |
| `503 Service Unavailable` | API GW | Lambda throttled / downstream unavailable |
| `504 Gateway Timeout` | API GW | Integration timed out (> `timeout_milliseconds`) |

### 502 Bad Gateway (Lambda → API GW)
- Lambda returned invalid JSON or missing required fields.
- Check Lambda response format:
```python
# Correct proxy response format
return {
    "statusCode": 200,
    "headers": {"Content-Type": "application/json"},
    "body": json.dumps({"message": "ok"}),
    "isBase64Encoded": False
}
```
- For Format 2.0 (HTTP API), `statusCode` is the only required field.

### 403 "Missing Authentication Token" 
- **Not** an auth issue — this means the route doesn't exist.
- Check: route key matches exactly (`GET /users` not `GET /user`).
- Check: deployment includes the new route.
- Check: stage URL is correct (includes stage name for REST API).

### Authorizer Debugging
```
# Enable authorizer logging
data_trace_enabled = true  # temporarily

# Check execution log for:
# - "Token source request-context, method ARN"
# - "Identity source value"
# - "Policy validation success/failure"
```

### Test Invocation (Console / AWS CLI)
```bash
# Test REST API method directly
aws apigateway test-invoke-method \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method GET \
  --path-with-query-string '/users/123' \
  --headers '{"Authorization":"Bearer ..."}' \
  --body '{}'

# Invoke HTTP API
curl -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "https://abc123.execute-api.us-east-1.amazonaws.com/prod/users"

# Check stage info
aws apigateway get-stage \
  --rest-api-id abc123 \
  --stage-name prod

# List deployments
aws apigateway get-deployments \
  --rest-api-id abc123
```

### VTL Template Debugging
```bash
# Test mapping template
aws apigateway test-invoke-method \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method POST \
  --body '{"name":"test"}' \
  --query 'log'
```

### Common Deployment Issues
- **Changes not reflected**: REST API requires new deployment. Check `triggers` hash.
- **Stage variables not updated**: Stage redeploy needed.
- **Authorizer still using old TTL cache**: Wait for TTL or flush using API key rotation.
- **CORS still failing**: Check OPTIONS method exists; check response headers are included on non-OPTIONS responses too.

---

## 22. Cost Model

### REST API Pricing
- **API calls**: $3.50 per million calls (first 333M/month), tiering down to $1.51.
- **Data transfer**: Standard EC2 rates.
- **Cache**: $0.02/hr (0.5 GB) to $3.80/hr (237 GB).
- **Private API**: $0.01/hr per VPC endpoint + $0.01/GB data processed.

### HTTP API Pricing
- **API calls**: $1.00 per million calls (first 300M), then $0.90.
- ~71% cheaper than REST API.
- No charge for caching (no cache available).

### WebSocket API Pricing
- **Connection minutes**: $0.29 per million minutes.
- **Messages**: $1.00 per million messages.

### Cost Optimization
- Prefer HTTP API over REST API unless you need REST-specific features.
- Use caching to reduce Lambda invocations.
- Implement proper throttling to prevent runaway usage.
- Use CloudFront in front of Regional REST API — CloudFront cheaper per request than edge-optimized.
- Minimize authorizer invocations with caching (TTL 300s).
- Use Usage Plans and quotas to cap per-client spending.

---

## 23. Limits & Quotas

| Resource | REST API | HTTP API | Adjustable |
|---|---|---|---|
| Regional APIs per account | 600 | 600 | Yes |
| Max stages per API | 10 | 10 | Yes |
| Max routes per API | 300 | 300 | Yes |
| Max integrations per API | 300 | 300 | Yes |
| Max authorizers per API | 10 | 10 | Yes |
| Max API keys | 500 | N/A | Yes |
| Max usage plans | 300 | N/A | Yes |
| Regional throttle default | 10,000 rps | 10,000 rps | Yes |
| Regional burst default | 5,000 | 5,000 | Yes |
| Max timeout | 29 sec | 29 sec | No |
| Max payload (REST) | 10 MB | 10 MB | No |
| Max mapping template size | 300 KB | N/A | No |
| Max Lambda authorizer response size | 8 KB | 8 KB | No |
| Max custom domain names | 120 | 120 | Yes |
| Max VPC links | 20 | 20 | Yes |
| Max stages per domain | 200 | 200 | No |
| WebSocket frame size | 32 KB | N/A | No |
| WebSocket message size (accumulated) | 128 KB | N/A | No |
| WebSocket connection duration | 2 hours | N/A | No |
| WebSocket idle timeout | 10 minutes | N/A | No |

---

## 24. Security Best Practices

### Authentication
- Always require auth on production endpoints — no `authorization = "NONE"` unless truly public.
- Prefer JWT (Cognito) over custom Lambda authorizers when possible — faster, cheaper, more scalable.
- Cache authorizer responses (TTL 300s) to reduce Lambda invocations.
- Validate JWT scopes at the route level for fine-grained access control.

### Rate Limiting & DDoS
- Set stage-level throttle limits.
- Use WAF with managed rule groups (AWSManagedRulesCommonRuleSet, AWSManagedRulesKnownBadInputsRuleSet).
- Add WAF rate-based rules per IP.
- Use AWS Shield Advanced for critical APIs.

### Encryption & TLS
- Enforce `TLS_1_2` security policy on custom domains.
- Use mTLS for machine-to-machine API clients.
- Encrypt CloudWatch logs with KMS.
- Encrypt cache with `cache_data_encrypted = true`.

### Least Privilege
- Scope Lambda permissions to specific API GW execution ARN.
- Use resource policies on Private APIs to restrict VPC endpoint access.
- Scope IAM authorizer roles to specific APIs/authorizers.

### Input Validation
- Enable request validators (body + parameters) — catch bad input before Lambda.
- Define JSON schema models for all request bodies.
- Sanitize and validate in Lambda too (defense in depth).

### API Key Security
- API keys are not authentication — they are metering/quota tools.
- Combine API keys with Cognito/Lambda auth for both metering and identity.
- Rotate API keys regularly; never embed in client-side code.

---

## 25. Terraform Full Resource Reference

### Complete HTTP API Module

```hcl
##############################################
# variables.tf
##############################################
variable "api_name"           { type = string }
variable "description"        { default = "" }
variable "stage_name"         { default = "prod" }
variable "environment"        { type = string }
variable "log_retention_days" { default = 30 }
variable "enable_xray"        { default = true }
variable "throttle_burst"     { default = 5000 }
variable "throttle_rate"      { default = 10000 }
variable "cors_origins"       { default = ["*"] }
variable "lambda_invoke_arn"  { type = string }
variable "lambda_function_name" { type = string }
variable "cognito_user_pool_arn"      { type = string }
variable "cognito_user_pool_client_id"{ type = string }
variable "cognito_issuer_url"         { type = string }
variable "kms_key_arn"        { default = null }
variable "tags"               { default = {} }

##############################################
# main.tf — HTTP API (v2)
##############################################

# --- API ---
resource "aws_apigatewayv2_api" "this" {
  name          = var.api_name
  protocol_type = "HTTP"
  description   = var.description

  cors_configuration {
    allow_origins     = var.cors_origins
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Api-Key", "X-Amz-Date", "X-Amz-Security-Token"]
    expose_headers    = ["X-Request-Id"]
    allow_credentials = length(var.cors_origins) == 1 && var.cors_origins[0] == "*" ? false : true
    max_age           = 86400
  }

  tags = var.tags
}

# --- JWT Authorizer ---
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  name             = "cognito-jwt"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = var.cognito_issuer_url
  }
}

# --- Lambda Integration ---
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

# --- Routes ---
resource "aws_apigatewayv2_route" "get_users" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /users"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# --- Lambda Permission ---
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- Logging ---
resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.api_name}/access"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# --- Stage ---
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
  }

  default_route_settings {
    throttling_burst_limit   = var.throttle_burst
    throttling_rate_limit    = var.throttle_rate
    detailed_metrics_enabled = true
  }

  stage_variables = {
    env = var.environment
  }

  tags = var.tags
}

# --- Custom Domain ---
resource "aws_apigatewayv2_domain_name" "this" {
  count       = var.custom_domain != "" ? 1 : 0
  domain_name = var.custom_domain

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count       = var.custom_domain != "" ? 1 : 0
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.this.id
}

# --- Alarms ---
resource "aws_cloudwatch_metric_alarm" "5xx" {
  alarm_name          = "${var.api_name}-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions = {
    ApiId = aws_apigatewayv2_api.this.id
    Stage = aws_apigatewayv2_stage.this.name
  }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "4xx" {
  alarm_name          = "${var.api_name}-4xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 50
  treat_missing_data  = "notBreaching"
  dimensions = {
    ApiId = aws_apigatewayv2_api.this.id
    Stage = aws_apigatewayv2_stage.this.name
  }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

##############################################
# outputs.tf
##############################################
output "api_id"           { value = aws_apigatewayv2_api.this.id }
output "api_arn"          { value = aws_apigatewayv2_api.this.arn }
output "execution_arn"    { value = aws_apigatewayv2_api.this.execution_arn }
output "invoke_url"       { value = aws_apigatewayv2_stage.this.invoke_url }
output "stage_arn"        { value = aws_apigatewayv2_stage.this.arn }
output "log_group_name"   { value = aws_cloudwatch_log_group.access.name }
output "authorizer_id"    { value = aws_apigatewayv2_authorizer.jwt.id }
output "custom_domain_target" {
  value = length(aws_apigatewayv2_domain_name.this) > 0 ?
    aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name : null
}
```

---

### Terraform Resource Quick Reference Table

| Resource | API Type | Purpose |
|---|---|---|
| `aws_apigatewayv2_api` | HTTP + WebSocket | Create HTTP or WebSocket API |
| `aws_apigatewayv2_route` | HTTP + WebSocket | Route key → integration mapping |
| `aws_apigatewayv2_integration` | HTTP + WebSocket | Backend integration config |
| `aws_apigatewayv2_stage` | HTTP + WebSocket | Stage with logging, throttle, auto_deploy |
| `aws_apigatewayv2_authorizer` | HTTP | JWT or Lambda authorizer |
| `aws_apigatewayv2_domain_name` | HTTP + WebSocket | Custom domain config |
| `aws_apigatewayv2_api_mapping` | HTTP + WebSocket | Map API+stage to custom domain path |
| `aws_apigatewayv2_vpc_link` | HTTP | VPC Link to ALB/NLB/Cloud Map |
| `aws_api_gateway_rest_api` | REST | Create REST API |
| `aws_api_gateway_resource` | REST | URL path resource |
| `aws_api_gateway_method` | REST | HTTP method on resource |
| `aws_api_gateway_integration` | REST | Backend integration |
| `aws_api_gateway_integration_response` | REST | Map integration response |
| `aws_api_gateway_method_response` | REST | Define method response codes/headers |
| `aws_api_gateway_deployment` | REST | Immutable deployment snapshot |
| `aws_api_gateway_stage` | REST | Stage attached to deployment |
| `aws_api_gateway_method_settings` | REST | Per-method throttle, logging, cache |
| `aws_api_gateway_authorizer` | REST | Lambda or Cognito authorizer |
| `aws_api_gateway_request_validator` | REST | Validate body/params |
| `aws_api_gateway_model` | REST | JSON Schema model |
| `aws_api_gateway_api_key` | REST | API key |
| `aws_api_gateway_usage_plan` | REST | Throttle + quota per key group |
| `aws_api_gateway_usage_plan_key` | REST | Associate key with usage plan |
| `aws_api_gateway_domain_name` | REST | Custom domain |
| `aws_api_gateway_base_path_mapping` | REST | Map stage to domain path |
| `aws_api_gateway_vpc_link` | REST | VPC Link to NLB |
| `aws_api_gateway_account` | REST | Account-level CW log role |
| `aws_api_gateway_gateway_response` | REST | Customize GW error responses |
| `aws_lambda_permission` | All | Allow API GW to invoke Lambda |
| `aws_wafv2_web_acl` | All | WAF rules |
| `aws_wafv2_web_acl_association` | All | Attach WAF to stage |
| `aws_cloudwatch_log_group` | All | Access/execution log group |
| `aws_cloudwatch_metric_alarm` | All | 4XX, 5XX, latency alarms |
| `aws_cloudwatch_dashboard` | All | Operational dashboard |
| `aws_xray_sampling_rule` | REST | X-Ray sampling config |
| `aws_route53_record` | All | DNS alias to API GW endpoint |
| `aws_acm_certificate` | All | TLS cert for custom domain |

### Gateway Responses (REST API — customize error messages)
```hcl
resource "aws_api_gateway_gateway_response" "unauthorized" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "UNAUTHORIZED"
  status_code   = "401"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
    "gatewayresponse.header.WWW-Authenticate"            = "'Bearer'"
  }

  response_templates = {
    "application/json" = jsonencode({
      error   = "Unauthorized"
      message = "Valid authentication credentials required"
    })
  }
}

resource "aws_api_gateway_gateway_response" "throttled" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "THROTTLED"
  status_code   = "429"

  response_templates = {
    "application/json" = jsonencode({
      error   = "TooManyRequests"
      message = "Rate limit exceeded. Please retry after backoff."
    })
  }
}

# All gateway response types:
# ACCESS_DENIED, API_CONFIGURATION_ERROR, AUTHORIZER_CONFIGURATION_ERROR,
# AUTHORIZER_FAILURE, BAD_REQUEST_BODY, BAD_REQUEST_PARAMETERS,
# DEFAULT_4XX, DEFAULT_5XX, EXPIRED_TOKEN, INTEGRATION_FAILURE,
# INTEGRATION_TIMEOUT, INVALID_API_KEY, INVALID_SIGNATURE,
# MISSING_AUTHENTICATION_TOKEN, QUOTA_EXCEEDED, REQUEST_TOO_LARGE,
# RESOURCE_NOT_FOUND, THROTTLED, UNAUTHORIZED, UNSUPPORTED_MEDIA_TYPE,
# WAF_FILTERED
```

---

*Last updated: February 2026*
*Next: DynamoDB, SQS, EventBridge, Step Functions, ECS, RDS, ElastiCache*