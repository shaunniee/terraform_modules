# AWS AppSync — Engineering Notes

## Architecture Overview

AWS AppSync is a fully managed GraphQL and Pub/Sub API service. It acts as a middle layer between clients and backend data sources, providing:

1. **GraphQL endpoint** — single endpoint for queries, mutations, subscriptions
2. **Real-time** — WebSocket-based subscriptions for live data
3. **Offline** — built-in sync with Amplify SDK conflict resolution
4. **Multiple auth** — stack up to 5 auth modes on a single API

---

## API Types

### GRAPHQL (Standard)
- Define schema, data sources, resolvers directly
- Primary use case for most applications

### MERGED
- Combines multiple source GraphQL APIs into one endpoint
- Each team owns their own source API; merged API provides a unified schema
- Requires `merged_api_execution_role_arn`
- Source APIs associated via `aws_appsync_source_api_association`
- Merge types: `AUTO_MERGE` (automatic on source changes) or `MANUAL_MERGE`

---

## Authentication Modes

| Mode | Use Case |
|------|----------|
| `API_KEY` | Public access, prototyping, server-to-server with key rotation |
| `AWS_IAM` | Service-to-service, admin actions, signed requests |
| `AMAZON_COGNITO_USER_POOLS` | User authentication, group-based authorization |
| `OPENID_CONNECT` | Third-party IdP (Auth0, Okta, Firebase) |
| `AWS_LAMBDA` | Custom authorization logic, token validation |

### Multi-Auth
- One **primary** authentication type on the API.
- Up to 4 **additional** providers via `additional_authentication_providers`.
- Use `@aws_auth`, `@aws_api_key`, `@aws_iam`, `@aws_cognito_user_pools`, `@aws_oidc`, `@aws_lambda` directives in schema to control per-field access.

### API Key Notes
- Keys expire after max 365 days.
- Rotate keys before expiry to avoid downtime.
- API keys grant full schema access unless field-level directives restrict it.

---

## Data Sources

| Type | Resource | Config Block |
|------|----------|-------------|
| `AMAZON_DYNAMODB` | DynamoDB table | `dynamodb_config` |
| `AWS_LAMBDA` | Lambda function | `lambda_config` |
| `HTTP` | Any HTTP endpoint | `http_config` |
| `AMAZON_OPENSEARCH_SERVICE` | OpenSearch domain | `opensearchservice_config` |
| `AMAZON_ELASTICSEARCH` | Legacy Elasticsearch | `elasticsearch_config` |
| `RELATIONAL_DATABASE` | Aurora Serverless (Data API) | `relational_database_config` |
| `AMAZON_EVENTBRIDGE` | EventBridge event bus | `event_bridge_config` |
| `NONE` | Local resolver (no backend) | — |

### DynamoDB Delta Sync
- For Amplify DataStore conflict resolution
- Requires base table + delta sync table + optional base table TTL

### HTTP Data Source
- Can sign requests with IAM (SigV4) via `authorization_config`
- Useful for calling API Gateway, OpenSearch, or any AWS service

---

## Resolvers

### Unit Resolvers
- Single data source per resolver
- Use VTL templates or JavaScript (APPSYNC_JS) runtime

### Pipeline Resolvers
- Chain multiple **functions** in sequence
- Each function can hit a different data source
- Pipeline resolver has a `before` step → functions → `after` step
- Set `kind = "PIPELINE"` and provide `pipeline_config.functions`

### Resolver Runtimes

| Runtime | Language | Template Fields |
|---------|----------|----------------|
| APPSYNC_JS | JavaScript (ES6 subset) | `code` with `runtime { name = "APPSYNC_JS" }` |

> **Note:** VTL (Velocity Template Language) templates are not supported in AWS provider v6+.
> All resolvers and functions must use the APPSYNC_JS runtime with `code`.

### JavaScript Resolver Notes
- Must export `request()` and `response()` functions
- Uses `@aws-appsync/utils` for helpers (`util.dynamodb.toMapValues`, etc.)
- **No** `async/await`, `Promise`, or `fetch` — all I/O is via data source mapping
- Max 32KB code size per function/resolver

---

## Functions (Pipeline)

- Reusable units of resolver logic
- Attached to a single data source
- Referenced by key in `pipeline_config.functions` array
- Support both VTL and JavaScript runtimes
- Support `sync_config` for conflict resolution
- `max_batch_size` enables batching (up to 10 items)

---

## Caching

- Powered by ElastiCache (Redis)
- Instance types: `SMALL`, `MEDIUM`, `LARGE`, `XLARGE`, `LARGE_2X`, `LARGE_4X`, `LARGE_8X`, `LARGE_12X`
- Cache behavior is `PER_RESOLVER_CACHING` — opt-in at resolver level via `caching_config`
- `caching_keys` define cache key components (e.g., `$context.arguments.id`)
- Default TTL applies API-wide; resolver-level TTL overrides

### Encryption
- `at_rest_encryption_enabled` — encrypts cached data at rest
- `transit_encryption_enabled` — encrypts data in transit between AppSync and cache

---

## Custom Domain Names

- Requires ACM certificate in **us-east-1** (CloudFront distribution)
- Creates a CloudFront distribution behind the scenes
- Returns `appsync_domain_name` (CloudFront domain) and `hosted_zone_id` for Route53 alias
- One domain per API

### DNS Setup
After creating the domain, add a Route53 alias record:
```hcl
resource "aws_route53_record" "appsync" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"

  alias {
    name                   = module.appsync.domain_appsync_domain_name
    zone_id                = module.appsync.domain_hosted_zone_id
    evaluate_target_health = false
  }
}
```

---

## WAF Integration

- Attach WAFv2 Web ACL to protect the GraphQL endpoint
- Rate limiting, IP blocking, SQL injection protection, etc.
- Uses `aws_wafv2_web_acl_association` resource
- Web ACL must be in the **same region** as the AppSync API

---

## Conflict Resolution (Sync Config)

For offline-capable apps using Amplify DataStore:

| Strategy | Behavior |
|----------|----------|
| `OPTIMISTIC_CONCURRENCY` | Reject writes if version mismatch |
| `AUTOMERGE` | Auto-merge non-conflicting fields |
| `LAMBDA` | Custom Lambda function resolves conflicts |

Set `conflict_detection = "VERSION"` to enable.

---

## Logging

### Field Log Levels
- `NONE` — no field-level logging
- `ERROR` — only errors
- `ALL` — all request/response data (verbose, higher cost)
- `INFO` — informational (available in new APIs)

### Log Group
- Auto-created at `/aws/appsync/apis/{api_id}`
- Module can manage the log group for retention policy and KMS encryption
- Set `create_cloudwatch_log_group = true` (default) to let the module manage it

### Exclude Verbose Content
- When `true`, omits full request/response data from logs
- Recommended for production to avoid logging sensitive data

---

## Tracing (X-Ray)

- Set `xray_enabled = true`
- Traces flow: Client → AppSync → Data Source → Response
- Works with downstream Lambda, DynamoDB, HTTP sources
- Segments show resolver-level timing

---

## CloudWatch Metrics

All metrics use namespace `AWS/AppSync` with dimension `GraphQLAPIId`.

### Request Metrics
| Metric | Description |
|--------|-------------|
| `4XXError` | Client errors (auth failures, validation) |
| `5XXError` | Server errors |
| `Latency` | Time from request receipt to response |
| `Requests` | Total number of requests (some API types) |
| `TokensConsumed` | Enhanced request rate tokens consumed |

### Real-time (Subscription) Metrics
| Metric | Description |
|--------|-------------|
| `ConnectSuccess` | Successful WebSocket connections |
| `ConnectClientError` | Client-side connection errors |
| `ConnectServerError` | Server-side connection errors |
| `DisconnectSuccess` | Successful disconnections |
| `DisconnectClientError` | Client disconnect errors |
| `DisconnectServerError` | Server disconnect errors |
| `SubscribeSuccess` | Successful subscriptions |
| `SubscribeClientError` | Client subscription errors |
| `SubscribeServerError` | Server subscription errors |
| `UnsubscribeSuccess` | Successful unsubscriptions |
| `PublishDataMessageSuccess` | Messages published to subscribers |
| `PublishDataMessageClientError` | Publish client errors |
| `PublishDataMessageServerError` | Publish server errors |
| `PublishDataMessageSize` | Size of published messages |
| `ActiveConnection` | Current active WebSocket connections |
| `ActiveSubscription` | Current active subscriptions |
| `ConnectionDuration` | Duration of WebSocket connections |

---

## Visibility

| Value | Behavior |
|-------|----------|
| `GLOBAL` | API is publicly discoverable (default) |
| `PRIVATE` | API is only accessible within the VPC associated with the API |

---

## Introspection

- `ENABLED` (default) — clients can query the schema
- `DISABLED` — blocks introspection queries (recommended for production)

---

## Limits & Quotas

| Limit | Value |
|-------|-------|
| Request payload | 1 MB |
| Response payload | 1 MB |
| Query depth | 1-75 (configurable) |
| Resolver count | 10-10000 per API (configurable) |
| Subscriptions per connection | 100 |
| Authentication providers | 1 primary + 4 additional |
| API keys per API | 50 |
| Data sources per API | 10000 |
| Functions per API | 10000 |
| Resolvers per API | 10000 |
| Schema size | 1 MB |
| VTL template size | 64 KB |
| JS code size | 32 KB |
| Pipeline functions per resolver | 10 |
| Batch size | 10 |
| Real-time data rate | 240 KB/s per subscription |
| WebSocket connection timeout | 24 hours |
| Custom domains per account | 25 |

---

## Cost Model

| Component | Pricing |
|-----------|---------|
| Query/Mutation requests | Per million ($4.00 us-east-1) |
| Real-time updates | Per million connection-minutes + messages |
| Caching | Hourly by instance type |
| Custom domain | Free (underlying CloudFront charges) |
| Data transfer | Standard AWS data transfer rates |

### Cost Optimization
- Use caching to reduce resolver invocations
- Batch resolvers to reduce round trips
- Use `NONE` data source for local transforms
- Monitor `TokensConsumed` metric for enhanced request mode

---

## Security Best Practices

1. **Disable introspection** in production (`introspection_config = "DISABLED"`)
2. **Use WAF** for rate limiting and IP filtering
3. **Rotate API keys** before expiry
4. **Use field-level auth directives** for fine-grained access
5. **Enable logging** (at least `ERROR` level)
6. **Set `exclude_verbose_content = true`** to avoid leaking data in logs
7. **Limit query depth** to prevent abuse (`query_depth_limit`)
8. **Use Cognito groups** for role-based access
9. **Use `PRIVATE` visibility** for internal APIs

---

## Terraform Resource Reference

| Resource | Purpose |
|----------|---------|
| `aws_appsync_graphql_api` | GraphQL API definition |
| `aws_appsync_api_cache` | API-level caching |
| `aws_appsync_api_key` | API key management |
| `aws_appsync_datasource` | Backend data source connections |
| `aws_appsync_function` | Pipeline resolver functions |
| `aws_appsync_resolver` | Field resolvers |
| `aws_appsync_domain_name` | Custom domain |
| `aws_appsync_domain_name_api_association` | Domain → API binding |
| `aws_appsync_source_api_association` | Merged API source associations |
| `aws_wafv2_web_acl_association` | WAF protection |
| `aws_cloudwatch_metric_alarm` | Metric alarms |
| `aws_cloudwatch_log_metric_filter` | Log-based metrics |
| `aws_cloudwatch_dashboard` | Observability dashboard |
| `aws_iam_role` | Logging IAM role |
| `aws_cloudwatch_log_group` | Managed log group |
