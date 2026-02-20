# AWS API Gateway — Complete Engineering Notes (Terraform-Centric)

> Deep reference notes for day-to-day cloud engineering and Terraform implementation.
> Covers core architecture, security, integrations, release patterns, observability, debugging, and cost.

---

## Table of Contents

1. [Service Scope and API Types](#1-service-scope-and-api-types)
2. [Core Architecture and Request Lifecycle](#2-core-architecture-and-request-lifecycle)
3. [REST API Building Blocks](#3-rest-api-building-blocks)
4. [Endpoint Types and Network Topology](#4-endpoint-types-and-network-topology)
5. [AuthN/AuthZ and Access Control](#5-authnauthz-and-access-control)
6. [Request Validation, Mapping, and Transformation](#6-request-validation-mapping-and-transformation)
7. [Integration Types and Backend Patterns](#7-integration-types-and-backend-patterns)
8. [Errors, Gateway Responses, and Client Experience](#8-errors-gateway-responses-and-client-experience)
9. [Deployments, Stages, Versioning, and Release Strategies](#9-deployments-stages-versioning-and-release-strategies)
10. [Performance, Throttling, Caching, and Limits](#10-performance-throttling-caching-and-limits)
11. [Custom Domains, TLS, DNS, and Edge Considerations](#11-custom-domains-tls-dns-and-edge-considerations)
12. [Security Hardening and Compliance Controls](#12-security-hardening-and-compliance-controls)
13. [Observability: Logs, Metrics, Traces, and Alarms](#13-observability-logs-metrics-traces-and-alarms)
14. [Debugging and Troubleshooting Playbook](#14-debugging-and-troubleshooting-playbook)
15. [Cost Model and Optimization](#15-cost-model-and-optimization)
16. [Important Quotas and Service Limits](#16-important-quotas-and-service-limits)
17. [Terraform Reference: API Gateway (REST v1 + Related)](#17-terraform-reference-api-gateway-rest-v1--related)
18. [This Module: Feature Mapping and Design Notes](#18-this-module-feature-mapping-and-design-notes)
19. [Production Readiness Checklist](#19-production-readiness-checklist)

---

## 1. Service Scope and API Types

API Gateway has three API families:

| API Family | Terraform Namespace | Best For | Notes |
|---|---|---|---|
| REST API (v1) | `aws_api_gateway_*` | Full feature set, legacy and enterprise controls | Most configurable; higher cost and more moving parts |
| HTTP API (v2) | `aws_apigatewayv2_*` | Lower-cost low-latency proxy APIs | Fewer features than REST API |
| WebSocket API (v2) | `aws_apigatewayv2_*` | Bi-directional persistent connections | Route-based message handling |

This module implements **REST API (v1)**. Most notes below are REST-focused, with explicit callouts where behavior differs across API types.

---

## 2. Core Architecture and Request Lifecycle

### High-Level Request Path (REST API)

1. Client sends HTTPS request to execute-api endpoint or custom domain.
2. API Gateway resolves stage + resource path + method.
3. Request auth and policy checks run (IAM/Cognito/Lambda authorizer/API key/WAF if configured).
4. Request validator and model validation run (if configured).
5. Method request transforms to integration request (VTL templates / parameter mappings).
6. Backend integration executes (Lambda/HTTP/AWS service/MOCK).
7. Integration response maps to method response.
8. Stage and gateway response behaviors apply.
9. Access logs, execution logs, metrics, and optional X-Ray are emitted.

### Control Plane vs Data Plane

- **Control plane**: create API resources, methods, integrations, deployments, stages.
- **Data plane**: live request execution against deployed stage.
- Important: changes to resources/methods/integrations are not live until a new deployment is associated to a stage.

---

## 3. REST API Building Blocks

### Core Entities

| Entity | Purpose | Terraform |
|---|---|---|
| REST API | API container and global options | `aws_api_gateway_rest_api` |
| Resource | Path segment (`/orders/{id}`) | `aws_api_gateway_resource` |
| Method | HTTP verb + auth + request config | `aws_api_gateway_method` |
| Integration | Backend target + mapping | `aws_api_gateway_integration` |
| Method Response | Declares expected client response status/model | `aws_api_gateway_method_response` |
| Integration Response | Maps backend result to method response | `aws_api_gateway_integration_response` |
| Deployment | Immutable snapshot of API config | `aws_api_gateway_deployment` |
| Stage | Live environment pointer to deployment | `aws_api_gateway_stage` |

### Method Concepts

- Method-level controls:
  - Authorization mode (`NONE`, `AWS_IAM`, `CUSTOM`, `COGNITO_USER_POOLS`)
  - API key required flag
  - Request parameters and request models
  - Request validator assignment
- `ANY` is supported but requires careful backend handling and explicit observability dimensions.

---

## 4. Endpoint Types and Network Topology

### Endpoint Types

| Type | Characteristics | Typical Use |
|---|---|---|
| `REGIONAL` | Regional endpoint, recommended default | Most workloads |
| `EDGE` | CloudFront-managed edge-optimized endpoint | Global client distribution without self-managed CDN |
| `PRIVATE` | Reachable via VPC interface endpoint (PrivateLink) | Internal APIs in private networks |

### Network Patterns

- Public API with WAF + custom domain.
- Private API with resource policy restricting `aws:SourceVpce`.
- VPC Link integration for private NLB-backed services.

### Private API Notes

- Requires API resource policy for least-privilege access.
- Typically paired with route-level IAM auth and centralized VPC endpoint strategy.
- Validate DNS and endpoint policies to avoid accidental broad access.

---

## 5. AuthN/AuthZ and Access Control

### Authorization Modes

| Mode | What It Does | Key Terraform |
|---|---|---|
| `NONE` | No built-in authorization | `aws_api_gateway_method.authorization` |
| `AWS_IAM` | SigV4 request signing + IAM policy evaluation | method auth + IAM policies |
| `CUSTOM` | Lambda authorizer (`TOKEN` or `REQUEST`) | `aws_api_gateway_authorizer` |
| `COGNITO_USER_POOLS` | JWT validation via Cognito User Pool | `aws_api_gateway_authorizer` with provider ARNs |

### Lambda Authorizer Deep Notes

- `TOKEN`: single token source (usually `Authorization` header).
- `REQUEST`: can use headers, query params, stage vars, and context.
- Caching (`authorizer_result_ttl_in_seconds`) reduces latency/cost but requires revocation strategy.
- Policy document size and principal context size constraints matter for large custom claims.

### API Keys and Usage Plans

- REST API supports API key checks per method.
- API key value itself is not auth; pair with IAM/Cognito/authorizer for secure access.
- Usage plans enforce request-rate quotas per API key.
- Terraform references:
  - `aws_api_gateway_api_key`
  - `aws_api_gateway_usage_plan`
  - `aws_api_gateway_usage_plan_key`

### Resource Policies

- Resource-based policy on REST API controls who can invoke the API (cross-account, VPC endpoint, CIDR).
- Useful for PRIVATE APIs and explicit principal whitelisting.
- Terraform: set `policy` on `aws_api_gateway_rest_api`.

---

## 6. Request Validation, Mapping, and Transformation

### Validation

- Request validators can validate:
  - body only
  - parameters only
  - both
- Request models define schema expectations by content type.
- Validation failure returns `400` before integration is called.

Terraform:
- `aws_api_gateway_request_validator`
- `aws_api_gateway_method.request_models`
- `aws_api_gateway_method.request_parameters`

### VTL Templates and Parameter Mapping

- Request templates transform method request payload into integration format.
- Response templates transform integration response into client format.
- Mapping supports `$input`, `$context`, `$util` functions.
- Keep templates deterministic and small; large templates are hard to debug.

### Binary Media Types and Content Handling

- Configure binary media types at API level.
- Use `content_handling` for conversion where required.
- Binary support must align with client `Accept` / `Content-Type` behavior and backend encoding.

### Compression

- `minimum_compression_size` controls payload compression threshold.
- Improves bandwidth usage but can increase CPU/latency for tiny responses.

---

## 7. Integration Types and Backend Patterns

### Integration Types

| Integration Type | Description | Common Use |
|---|---|---|
| `AWS_PROXY` | Lambda proxy event passthrough | Most Lambda-backed APIs |
| `AWS` | Non-proxy AWS service integration | SQS/SNS/StepFunctions direct calls |
| `HTTP_PROXY` | Pass-through to HTTP backend | Existing microservices |
| `HTTP` | Non-proxy HTTP with mapping templates | Protocol adaptation |
| `MOCK` | Static response for testing/fallback | Health and contract tests |

### Lambda Proxy (`AWS_PROXY`)

- Fastest to implement; backend owns status code/body/headers.
- Requires Lambda permission with execute-api source ARN.
- Recommended for most greenfield REST APIs.

### Non-Proxy Integrations (`AWS`, `HTTP`)

- Enable strict contract control via request/response templates.
- Better for protocol translation or legacy backend normalization.
- More operational overhead due to mapping complexity.

### VPC Link

- For private HTTP integrations through NLB.
- Requires `connection_type = "VPC_LINK"` and `connection_id`.
- Monitor integration latency and backend timeout carefully.

### Timeout and Retries

- Integration timeout max is bounded (module validates 50–29000 ms).
- API Gateway itself does not provide general backend retry semantics for all integration types.
- Design idempotent backends and explicit retry behavior in callers where needed.

---

## 8. Errors, Gateway Responses, and Client Experience

### Error Layers

1. AuthN/AuthZ errors (401/403)
2. Validation errors (400)
3. Integration invocation errors (5xx, timeout)
4. Mapping/template errors (5xx)
5. Throttling/quota (`429`)

### Gateway Responses

- Customize standard responses such as:
  - `DEFAULT_4XX`, `DEFAULT_5XX`
  - `UNAUTHORIZED`, `ACCESS_DENIED`
  - `THROTTLED`, `QUOTA_EXCEEDED`
  - `INTEGRATION_TIMEOUT`, `INTEGRATION_FAILURE`
- Used to standardize error bodies/headers (e.g., correlation IDs, JSON error envelope).

Terraform: `aws_api_gateway_gateway_response`.

### CORS

- For REST API, CORS is not one toggle; configure per-resource/per-method.
- Usually requires:
  - `OPTIONS` method
  - appropriate method/integration response headers
  - backend-provided CORS headers for proxy integrations

---

## 9. Deployments, Stages, Versioning, and Release Strategies

### Deployment Model

- `aws_api_gateway_deployment` captures a point-in-time API configuration.
- `aws_api_gateway_stage` points traffic to one deployment.
- Redeployment trigger strategy is crucial in Terraform to avoid stale deployments.

### Stage Features

- Stage variables for environment-specific behavior.
- Stage cache cluster toggles.
- Method settings across `*/*` or specific method paths.
- X-Ray enablement and access logs at stage scope.

### Recommended Release Patterns

- **Blue/Green via stages**: `v1` / `v2`, then swap custom domain base path mapping.
- **Canary** (REST stage supports canary settings): gradual traffic shift.
- **Immutable deployments** with deterministic redeployment hash in Terraform.

---

## 10. Performance, Throttling, Caching, and Limits

### Throttling Layers

- Account-level regional limits.
- Stage/method throttling via method settings (`burst` and `rate`).
- Usage plan throttling/quota for API-key consumers.

### Caching

- Stage cache cluster improves read latency and backend offload.
- Method settings can enable/disable caching and TTL.
- Cache invalidation strategy is mandatory for mutable resources.

### Latency Metrics to Track

- `Latency`: end-to-end API Gateway latency.
- `IntegrationLatency`: backend-only latency.
- Gap between them shows API Gateway overhead (mapping, auth, etc.).

### Payload and Mapping Considerations

- Large payloads and heavy VTL increase latency/cost.
- Prefer proxy integrations when transformation is minimal.

---

## 11. Custom Domains, TLS, DNS, and Edge Considerations

### Custom Domains

- Use `aws_api_gateway_domain_name` + `aws_api_gateway_base_path_mapping`.
- For DNS, alias A record to API Gateway domain target.
- Regional vs Edge endpoint behavior impacts certificate region requirements.

### TLS and Security Policy

- Enforce modern TLS policy (`TLS_1_2` preferred).
- If required by legacy clients, explicitly document downgrade risk.

### Mutual TLS (mTLS)

- Supported for custom domains in REST APIs (regional).
- Requires truststore configuration in S3.
- Terraform support is available on domain resources (provider-version dependent fields).

---

## 12. Security Hardening and Compliance Controls

### Baseline Hardening

- Disable default execute-api endpoint when using custom domains (`disable_execute_api_endpoint = true`) if architecture allows.
- Apply least-privilege IAM for invoke and management actions.
- Restrict PRIVATE API by VPC endpoint policy + API resource policy.
- Attach WAFv2 for L7 protections on public APIs.
- Avoid sensitive data in query strings or logs.

### Data Protection

- TLS in transit is mandatory.
- Encrypt access logs in CloudWatch with KMS where required.
- Use tokenization/redaction patterns in logging and templates.

### Governance

- Standard tagging across API/stage/log groups.
- Separate accounts/stages by environment (dev/stage/prod).
- Track configuration drift and enforce via CI checks.

---

## 13. Observability: Logs, Metrics, Traces, and Alarms

### Logging Types (REST)

| Log Type | Purpose | Where Configured |
|---|---|---|
| Access Logs | One structured line per request | Stage `access_log_settings` |
| Execution Logs | Internal execution details | Method/stage logging settings + API Gateway account CW role |

### Access Log Best Practices

- Use JSON format.
- Include: request ID, extended request ID, source IP, method, path, status, protocol, response length, integration latency.
- Add correlation IDs from incoming headers where possible.

### CloudWatch Metrics (Key)

- `Count`
- `4XXError`
- `5XXError`
- `Latency`
- `IntegrationLatency`
- `CacheHitCount`, `CacheMissCount` (when caching enabled)

Dimensions commonly used:
- `ApiName`
- `Stage`
- `Method`
- `Resource`

### Tracing (X-Ray)

- Enable on stage (`xray_tracing_enabled`).
- Requires account-level API Gateway CloudWatch/X-Ray role permissions.
- Provides service map and segment-level latency breakdown.

### Alarm Strategy

Minimum recommended alarms:

1. High `5XXError` sum
2. Elevated `4XXError` sum (context-aware threshold)
3. High `Latency` p95
4. High `IntegrationLatency`
5. Zero traffic anomaly (optional for critical APIs)

---

## 14. Debugging and Troubleshooting Playbook

### Fast Triage Sequence

1. Confirm stage deployment is current.
2. Check access logs for request ID and status pattern.
3. Check execution logs for mapping/auth/integration failures.
4. Compare `Latency` vs `IntegrationLatency`.
5. Check backend logs (Lambda/ALB/service).
6. Validate IAM/resource policy/authorizer decisions.

### Common Failure Signatures

| Symptom | Likely Cause | Checks |
|---|---|---|
| `403 Missing Authentication Token` | Wrong path/stage/method; custom domain mapping mismatch | Verify base path mapping and route exists |
| `401 Unauthorized` | Authorizer/token issue | Authorizer identity source, token validity, TTL cache |
| `403 Forbidden` | IAM deny/resource policy/WAF block | IAM policy simulation, API policy, WAF logs |
| `429 Too Many Requests` | Throttle/quota exceeded | Account, stage, usage plan throttles |
| `500 Internal Server Error` | Mapping template/runtime integration issue | Execution logs + integration response mapping |
| `504 Integration Timeout` | Backend exceeded timeout | Integration timeout + backend latency |

### Mapping Template Debug Tips

- Validate JSON syntax independently.
- Use explicit defaults for missing fields.
- Minimize branching in templates.
- Log request IDs and key context variables to correlate failures.

### Deployment Drift Pitfall

- Terraform updates to methods/integrations without deployment trigger updates can leave stage stale.
- Ensure deployment trigger includes all behavior-affecting objects.

---

## 15. Cost Model and Optimization

Cost drivers for REST API:

- API requests (per million requests)
- Data transfer out
- Caching (if enabled)
- Custom domain and edge/CloudFront-related transfer behavior
- CloudWatch logs ingestion/storage
- X-Ray traces

Optimization levers:

- Move simple high-volume endpoints to HTTP API (if features fit).
- Reduce payload size and compress responses.
- Use efficient authorizer caching and backend latency optimization.
- Tune log verbosity; keep INFO/data trace for non-prod or temporary incident windows.

---

## 16. Important Quotas and Service Limits

Quotas vary by region/account and can change; always verify via **Service Quotas** and API Gateway docs.

Operationally important limit classes:

- API count per region/account
- Resources and methods per API
- Authorizers and models per API
- Stage names and variables constraints
- Integration timeout bounds
- Request/response payload size bounds
- Account-level request rate/burst limits

Rule: treat defaults as starting points and request quota increases ahead of scale events.

---

## 17. Terraform Reference: API Gateway (REST v1 + Related)

### Core REST API Resources

| Terraform Resource | What It Manages |
|---|---|
| `aws_api_gateway_rest_api` | API container, endpoint config, binary media, compression, policy |
| `aws_api_gateway_resource` | Path tree segments |
| `aws_api_gateway_method` | HTTP method settings, auth, request model/params |
| `aws_api_gateway_integration` | Backend integration and request mapping |
| `aws_api_gateway_method_response` | Method response declarations |
| `aws_api_gateway_integration_response` | Integration-to-method response mapping |
| `aws_api_gateway_request_validator` | Request validation behavior |
| `aws_api_gateway_model` | JSON schema models |
| `aws_api_gateway_gateway_response` | Global default error responses |
| `aws_api_gateway_deployment` | Deployable immutable snapshot |
| `aws_api_gateway_stage` | Runtime stage config |
| `aws_api_gateway_method_settings` | Logging/metrics/throttle/cache settings |
| `aws_api_gateway_account` | Account-level CloudWatch role association |

### Security and Access Related

| Terraform Resource | Use |
|---|---|
| `aws_api_gateway_authorizer` | Lambda/Cognito authorizers |
| `aws_api_gateway_api_key` | API keys |
| `aws_api_gateway_usage_plan` | Quotas/throttle plan |
| `aws_api_gateway_usage_plan_key` | API key attachment to usage plan |
| `aws_wafv2_web_acl_association` | Stage-level WAF attachment |
| `aws_lambda_permission` | Permit API Gateway to invoke Lambda |

### Domain and DNS

| Terraform Resource | Use |
|---|---|
| `aws_api_gateway_domain_name` | Custom domain and certificate binding |
| `aws_api_gateway_base_path_mapping` | Domain path to API stage mapping |
| `aws_route53_record` | Alias DNS record |

### Observability and Operations

| Terraform Resource | Use |
|---|---|
| `aws_cloudwatch_log_group` | Access/execution log destination |
| `aws_cloudwatch_metric_alarm` | SLO/SLI alerting |
| `aws_iam_role` + attachments | API Gateway account logging/tracing role |

### v2 (HTTP/WebSocket) Namespace (for reference)

- `aws_apigatewayv2_api`
- `aws_apigatewayv2_route`
- `aws_apigatewayv2_integration`
- `aws_apigatewayv2_stage`
- `aws_apigatewayv2_domain_name`
- `aws_apigatewayv2_api_mapping`
- `aws_apigatewayv2_authorizer`

Use these only when implementing HTTP/WebSocket APIs, not REST v1.

---

## 18. This Module: Feature Mapping and Design Notes

### Implemented Features (Current Module)

This module composes REST API through submodules:

- `submodules/api`: REST API definition
- `submodules/resources`: path resources (with depth validation up to 5 levels)
- `submodules/authorizers`: Lambda/Cognito authorizers
- `submodules/methods`: method definitions and auth binding
- `submodules/integrations`: backend integration definitions
- `submodules/responses`: method + integration responses
- `submodules/stage`: deployment, stage, method settings, optional access log group
- `submodules/domain`: custom domain, base path mapping, Route53 alias

Top-level module adds:

- optional execution role creation and policy attachments
- optional API Gateway account CloudWatch role association
- request validators
- gateway responses
- optional WAFv2 association
- optional CloudWatch metric alarms (default + custom)

### Input Variables to Feature Mapping (High-Signal)

| Input | Feature |
|---|---|
| `endpoint_configuration_types` | `REGIONAL` / `EDGE` / `PRIVATE` endpoint mode |
| `binary_media_types`, `minimum_compression_size` | payload and compression behavior |
| `resources`, `methods`, `integrations` | route and backend graph |
| `method_responses`, `integration_responses` | explicit response contract mapping |
| `gateway_responses` | default error envelope customization |
| `request_validators` | request body/parameter validation |
| `xray_tracing_enabled` | stage tracing |
| `method_settings` | metrics/logging/throttle/cache flags |
| `access_log_*` | stage access logging |
| `observability`, `cloudwatch_metric_alarms` | alarm automation |
| `create_domain_name`, `domain_name`, `certificate_arn`, `base_path` | custom domain routing |
| `create_route53_record`, `hosted_zone_id`, `record_name` | DNS alias management |
| `web_acl_arn` | WAF protection |
| `execution_role_arn` / role-related flags | account log/tracing role strategy |

### Output Highlights

- API identity: `rest_api_id`, `rest_api_execution_arn`, `rest_api_root_resource_id`
- stage/runtime: `stage_name`, `stage_arn`, `stage_execution_arn`, `invoke_url`, `deployment_id`
- graph metadata: `resource_ids`, `authorizer_ids`, `methods_index`, `integration_ids`
- observability: `access_log_group_name`, `cloudwatch_metric_alarm_arns`, `cloudwatch_metric_alarm_names`
- domain metadata: `custom_domain_name`, `custom_domain_regional_domain_name`, `custom_domain_regional_zone_id`

### Current Module Boundaries / Gaps (Important)

These are API Gateway features you may add outside this module if needed:

- usage plans + API keys resources
- API documentation parts/version resources
- explicit canary settings on stage
- model resources (`aws_api_gateway_model`) management
- mutual TLS fields on custom domain (if required)
- per-method method settings overrides beyond global `*/*` object

---

## 19. Production Readiness Checklist

- Endpoint type selected intentionally (`REGIONAL` unless clear reason otherwise).
- Auth mode defined for every method; no accidental `NONE`.
- Resource policy enforced for PRIVATE APIs and restricted principals.
- WAF associated for internet-facing APIs.
- Access logs enabled with structured JSON and retention policy.
- Execution logging level set appropriately (`ERROR` or temporary `INFO`).
- Alarms configured for `5XXError`, `4XXError`, `Latency`, `IntegrationLatency`.
- Deployment trigger includes all route/integration config to prevent stale stage.
- Lambda permissions scoped to stage/method where possible.
- Custom domain + TLS policy validated; legacy TLS exceptions documented.
- Cost controls in place for logs, tracing, and cache usage.

---

## Practical Terraform Snippets

### 1) Strict IAM + Lambda Proxy Method

```hcl
resource "aws_api_gateway_method" "get_order" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "get_order" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.get_order.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orders.invoke_arn
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/GET/orders"
}
```

### 2) Request Validator + Gateway Response

```hcl
resource "aws_api_gateway_request_validator" "body_and_params" {
  rest_api_id                 = aws_api_gateway_rest_api.this.id
  name                        = "validate-body-params"
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_gateway_response" "default_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  response_type = "DEFAULT_4XX"
  status_code   = "400"

  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString,\"requestId\":\"$context.requestId\"}"
  }
}
```

### 3) Stage Logs + Alarm

```hcl
resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/orders/prod"
  retention_in_days = 30
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format          = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      method    = "$context.httpMethod"
      path      = "$context.resourcePath"
      status    = "$context.status"
      latency   = "$context.responseLatency"
    })
  }
}

resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  alarm_name          = "orders-api-prod-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.this.name
    Stage   = aws_api_gateway_stage.prod.stage_name
  }
}
```

---

Use these notes as the canonical engineering reference for REST API design in this repository. Revisit limits/pricing periodically because AWS updates both.
