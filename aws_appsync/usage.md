# AWS AppSync Module — Usage Guide

## Overview

This module creates a fully-featured AWS AppSync GraphQL API with support for:

- **Multiple authentication modes** (API Key, Cognito, OIDC, IAM, Lambda)
- **Multiple data sources** (DynamoDB, Lambda, HTTP, OpenSearch, RDS, EventBridge, None)
- **Unit and pipeline resolvers** with VTL or JavaScript runtime
- **API caching** with per-resolver configuration
- **Custom domain names** with certificate association
- **WAF integration** for API protection
- **Merged API** architecture (source API associations)
- **Full observability** — CloudWatch alarms, anomaly detection, log metric filters, dashboards

---

## Scenario A — Basic GraphQL API with API Key Auth

```hcl
module "appsync" {
  source = "../../aws_appsync"

  name                = "my-graphql-api"
  authentication_type = "API_KEY"

  schema = file("${path.module}/schema.graphql")

  api_keys = {
    default = {
      description = "Default API key"
      expires     = "2025-12-31T00:00:00Z"
    }
  }

  datasources = {
    orders_table = {
      type             = "AMAZON_DYNAMODB"
      service_role_arn = aws_iam_role.appsync_datasource.arn
      dynamodb_config = {
        table_name = module.dynamodb.table_name
      }
    }
  }

  resolvers = {
    get_order = {
      type       = "Query"
      field      = "getOrder"
      data_source = "orders_table"
      code = file("${path.module}/resolvers/getOrder.js")
      
    }
  }

  tags = {
    Environment = "dev"
  }
}
```

---

## Scenario B — Cognito Auth with Multiple Auth Providers

```hcl
module "appsync" {
  source = "../../aws_appsync"

  name                = "multi-auth-api"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  user_pool_config = {
    user_pool_id   = module.cognito.user_pool_id
    default_action = "ALLOW"
  }

  additional_authentication_providers = [
    {
      authentication_type = "API_KEY"
    },
    {
      authentication_type = "AWS_IAM"
    }
  ]

  schema = file("${path.module}/schema.graphql")

  api_keys = {
    public = {
      description = "Public API key for unauthenticated access"
    }
  }

  datasources = {
    users_table = {
      type             = "AMAZON_DYNAMODB"
      service_role_arn = aws_iam_role.appsync_ds.arn
      dynamodb_config = {
        table_name = "users"
      }
    }
  }

  resolvers = {
    get_user = {
      type                      = "Query"
      field                     = "getUser"
      data_source               = "users_table"
      code = file("${path.module}/resolvers/getUser.js")
      
    }
  }

  tags = { Environment = "staging" }
}
```

---

## Scenario C — Pipeline Resolver with JavaScript Runtime

```hcl
module "appsync" {
  source = "../../aws_appsync"

  name                = "pipeline-api"
  authentication_type = "API_KEY"
  schema              = file("${path.module}/schema.graphql")

  api_keys = {
    default = {}
  }

  datasources = {
    orders_table = {
      type             = "AMAZON_DYNAMODB"
      service_role_arn = aws_iam_role.appsync_ds.arn
      dynamodb_config = {
        table_name = "orders"
      }
    }
    inventory_table = {
      type             = "AMAZON_DYNAMODB"
      service_role_arn = aws_iam_role.appsync_ds.arn
      dynamodb_config = {
        table_name = "inventory"
      }
    }
  }

  functions = {
    validate_order = {
      data_source = "orders_table"
      code        = file("${path.module}/functions/validateOrder.js")
    }
    check_inventory = {
      data_source     = "inventory_table"
      code            = file("${path.module}/functions/checkInventory.js")
      runtime_name    = "APPSYNC_JS"
      runtime_version = "1.0.0"
    }
  }

  resolvers = {
    create_order = {
      type  = "Mutation"
      field = "createOrder"
      kind  = "PIPELINE"
      code  = file("${path.module}/resolvers/createOrder.js")
      pipeline_config = {
        functions = ["validate_order", "check_inventory"]
      }
    }
  }

  tags = { Environment = "dev" }
}
```

---

## Scenario D — HTTP & Lambda Data Sources

```hcl
module "appsync" {
  source = "../../aws_appsync"

  name                = "multi-datasource-api"
  authentication_type = "AWS_IAM"
  schema              = file("${path.module}/schema.graphql")

  datasources = {
    payment_service = {
      type             = "HTTP"
      service_role_arn = aws_iam_role.appsync_ds.arn
      http_config = {
        endpoint = "https://payments.example.com"
        authorization_config = {
          authorization_type = "AWS_IAM"
          aws_iam_config = {
            signing_region       = "us-east-1"
            signing_service_name = "execute-api"
          }
        }
      }
    }
    notification_lambda = {
      type             = "AWS_LAMBDA"
      service_role_arn = aws_iam_role.appsync_ds.arn
      lambda_config = {
        function_arn = module.lambda.function_arn
      }
    }
    local_resolver = {
      type = "NONE"
    }
  }

  resolvers = {
    process_payment = {
      type                      = "Mutation"
      field                     = "processPayment"
      data_source               = "payment_service"
      code = file("${path.module}/resolvers/processPayment.js")
      
    }
    send_notification = {
      type                      = "Mutation"
      field                     = "sendNotification"
      data_source               = "notification_lambda"
      code = file("${path.module}/resolvers/sendNotification.js")
      
    }
    echo = {
      type                      = "Query"
      field                     = "echo"
      data_source               = "local_resolver"
      code = file("${path.module}/resolvers/echo.js")
      
    }
  }

  tags = { Environment = "prod" }
}
```

---

## Scenario E — Full Observability

```hcl
module "appsync" {
  source = "../../aws_appsync"

  name                = "observed-api"
  authentication_type = "API_KEY"
  schema              = file("${path.module}/schema.graphql")

  logging_enabled           = true
  log_field_log_level       = "ALL"
  log_exclude_verbose_content = false
  log_retention_in_days     = 30
  xray_enabled              = true

  api_keys = {
    default = {}
  }

  datasources = {
    main_table = {
      type             = "AMAZON_DYNAMODB"
      service_role_arn = aws_iam_role.appsync_ds.arn
      dynamodb_config  = { table_name = "main" }
    }
  }

  resolvers = {
    get_item = {
      type                      = "Query"
      field                     = "getItem"
      data_source               = "main_table"
      code = file("${path.module}/resolvers/getItem.js")
      
    }
  }

  observability = {
    enabled                     = true
    enable_default_alarms       = true
    enable_anomaly_detection_alarms = true
    enable_dashboard            = true
    default_alarm_actions       = [aws_sns_topic.alerts.arn]
    default_ok_actions          = [aws_sns_topic.alerts.arn]
  }

  metric_alarms = {
    high_latency = {
      enabled             = true
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "Latency"
      namespace           = "AWS/AppSync"
      period              = 300
      extended_statistic  = "p99"
      threshold           = 10000
      alarm_actions       = [aws_sns_topic.critical.arn]
    }
  }

  log_metric_filters = {
    unauthorized_access = {
      enabled          = true
      pattern          = "\"Unauthorized\""
      metric_namespace = "Custom/AppSync"
      metric_name      = "UnauthorizedAccess"
      metric_value     = "1"
    }
  }

  tags = { Environment = "prod" }
}
```

---

## Scenario F — Custom Domain & WAF

```hcl
module "appsync" {
  source = "../../aws_appsync"

  name                = "secure-api"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  user_pool_config = {
    user_pool_id   = module.cognito.user_pool_id
    default_action = "ALLOW"
  }

  schema = file("${path.module}/schema.graphql")

  domain_name = {
    domain_name     = "api.example.com"
    certificate_arn = module.acm.certificate_arn
    description     = "Production GraphQL API domain"
  }

  waf_web_acl_arn = aws_wafv2_web_acl.appsync.arn

  caching_enabled = true
  caching_config = {
    type                       = "SMALL"
    ttl                        = 3600
    at_rest_encryption_enabled = true
    transit_encryption_enabled = true
  }

  datasources = {
    main_table = {
      type             = "AMAZON_DYNAMODB"
      service_role_arn = aws_iam_role.appsync_ds.arn
      dynamodb_config  = { table_name = "main" }
    }
  }

  resolvers = {
    list_items = {
      type                      = "Query"
      field                     = "listItems"
      data_source               = "main_table"
      code = file("${path.module}/resolvers/listItems.js")
      
      caching_config = {
        ttl          = 300
        caching_keys = ["$context.arguments.category"]
      }
    }
  }

  logging_enabled       = true
  log_field_log_level   = "ERROR"
  log_retention_in_days = 14

  tags = { Environment = "prod" }
}
```

---

## Scenario G — Merged API

```hcl
module "merged_api" {
  source = "../../aws_appsync"

  name                = "merged-api"
  api_type            = "MERGED"
  authentication_type = "AWS_IAM"

  merged_api_execution_role_arn = aws_iam_role.merged_api.arn

  source_api_associations = {
    orders_api = {
      source_api_id                        = module.orders_appsync.api_id
      source_api_association_config_merge_type = "AUTO_MERGE"
    }
    users_api = {
      source_api_id                        = module.users_appsync.api_id
      source_api_association_config_merge_type = "MANUAL_MERGE"
      description                          = "Users service API"
    }
  }

  tags = { Environment = "prod" }
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `name` | Name of the GraphQL API | `string` | — | yes |
| `api_type` | API type: `GRAPHQL` or `MERGED` | `string` | `"GRAPHQL"` | no |
| `schema` | GraphQL schema definition | `string` | `null` | conditional |
| `authentication_type` | Primary auth type | `string` | `"API_KEY"` | no |
| `user_pool_config` | Cognito User Pool configuration | `object` | `null` | conditional |
| `openid_connect_config` | OIDC configuration | `object` | `null` | conditional |
| `lambda_authorizer_config` | Lambda authorizer configuration | `object` | `null` | conditional |
| `additional_authentication_providers` | Additional auth providers | `list` | `[]` | no |
| `api_keys` | Map of API keys to create | `map(any)` | `{}` | no |
| `datasources` | Map of data sources | `map(any)` | `{}` | no |
| `functions` | Map of AppSync functions (pipeline) | `map(any)` | `{}` | no |
| `resolvers` | Map of resolvers | `map(any)` | `{}` | no |
| `logging_enabled` | Enable CloudWatch logging | `bool` | `false` | no |
| `logging_role_arn` | External IAM role ARN for logging | `string` | `null` | no |
| `log_field_log_level` | Field log level | `string` | `"ERROR"` | no |
| `xray_enabled` | Enable X-Ray tracing | `bool` | `false` | no |
| `caching_enabled` | Enable API caching | `bool` | `false` | no |
| `caching_config` | Cache configuration | `object` | see default | no |
| `domain_name` | Custom domain configuration | `object` | `null` | no |
| `waf_web_acl_arn` | WAF Web ACL ARN to associate | `string` | `null` | no |
| `observability` | Observability feature toggles | `object` | see default | no |
| `metric_alarms` | Custom CloudWatch metric alarms | `map(any)` | `{}` | no |
| `metric_anomaly_alarms` | Custom anomaly detection alarms | `map(any)` | `{}` | no |
| `log_metric_filters` | Custom log metric filters | `map(any)` | `{}` | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `api_id` | The unique identifier of the GraphQL API |
| `api_arn` | The ARN of the GraphQL API |
| `api_uris` | Map of URIs (GRAPHQL, REALTIME) |
| `api_name` | Name of the GraphQL API |
| `logging_role_arn` | ARN of the logging IAM role |
| `api_key_ids` | Map of API key name → ID |
| `api_key_values` | Map of API key name → key value (sensitive) |
| `datasource_arns` | Map of data source name → ARN |
| `function_ids` | Map of function name → function ID |
| `function_arns` | Map of function name → ARN |
| `resolver_arns` | Map of resolver name → ARN |
| `domain_name` | Custom domain name |
| `domain_hosted_zone_id` | Hosted zone ID for Route53 alias |
| `domain_appsync_domain_name` | CloudFront distribution domain |
| `log_group_name` | CloudWatch log group name |
| `alarm_arns` | Map of alarm logical key → ARN |
| `alarm_names` | Map of alarm logical key → name |
| `anomaly_alarm_arns` | Map of anomaly alarm key → ARN |
| `dashboard_name` | CloudWatch dashboard name |
| `dashboard_arn` | CloudWatch dashboard ARN |
