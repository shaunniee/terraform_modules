# Managed cache policies
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "s3_origin" {
  name = "Managed-CORS-S3Origin"
}

locals {
  default_cache_behavior_input = coalesce(var.default_cache_behavior, var.default_cache_behaviour)
  ordered_cache_behavior_input = coalesce(var.ordered_cache_behavior, var.ordered_cache_behaviour, {})

  enabled_cloudwatch_metric_alarms = {
    for alarm_key, alarm in var.cloudwatch_metric_alarms :
    alarm_key => alarm
    if try(alarm.enabled, true)
  }
}

# Origin Access Control for private buckets
resource "aws_cloudfront_origin_access_control" "this" {
  for_each = { for k, o in var.origins : k => o if o.is_private_origin && lower(try(o.origin_type, "s3")) == "s3" }

  name                              = "${var.distribution_name}-oac-${each.key}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# KMS-based CloudFront signed URLs (optional)
data "aws_kms_public_key" "signed_urls" {
  count  = var.kms_key_arn != null ? 1 : 0
  key_id = var.kms_key_arn
}

resource "aws_cloudfront_public_key" "signed_urls" {
  count       = var.kms_key_arn != null ? 1 : 0
  name        = "${var.distribution_name}-signed-url-key"
  encoded_key = data.aws_kms_public_key.signed_urls[0].public_key
  comment     = "Public key for CloudFront signed URLs"
}

resource "aws_cloudfront_key_group" "signed_urls" {
  count = var.kms_key_arn != null ? 1 : 0
  name  = "${var.distribution_name}-signed-url-group"
  items = [aws_cloudfront_public_key.signed_urls[0].id]
}

resource "aws_cloudfront_realtime_log_config" "this" {
  count = var.realtime_log_config != null ? 1 : 0

  name          = coalesce(try(var.realtime_log_config.name, null), "${var.distribution_name}-realtime-logs")
  sampling_rate = try(var.realtime_log_config.sampling_rate, 100)
  fields        = try(var.realtime_log_config.fields, [])

  dynamic "endpoint" {
    for_each = var.realtime_log_config == null ? [] : var.realtime_log_config.endpoints
    content {
      stream_type = try(endpoint.value.stream_type, "Kinesis")
      kinesis_stream_config {
        role_arn   = endpoint.value.role_arn
        stream_arn = endpoint.value.stream_arn
      }
    }
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = var.default_root_object
  price_class         = var.price_class
  comment             = coalesce(var.comment, var.distribution_name)
  aliases             = var.aliases
  web_acl_id          = var.web_acl_id
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = !(var.default_cache_behavior != null && var.default_cache_behaviour != null)
      error_message = "Set only one of default_cache_behavior or default_cache_behaviour."
    }

    precondition {
      condition     = local.default_cache_behavior_input != null
      error_message = "One of default_cache_behavior or default_cache_behaviour is required."
    }

    precondition {
      condition     = !(var.ordered_cache_behavior != null && var.ordered_cache_behaviour != null)
      error_message = "Set only one of ordered_cache_behavior or ordered_cache_behaviour."
    }

    precondition {
      condition     = length(var.aliases) == 0 || var.acm_certificate_arn != null
      error_message = "acm_certificate_arn is required when aliases are configured."
    }

    precondition {
      condition     = contains([for o in values(var.origins) : o.origin_id], local.default_cache_behavior_input.target_origin_id)
      error_message = "default cache behavior target_origin_id must match an origin_id in origins."
    }

    precondition {
      condition = alltrue([
        for b in values(local.ordered_cache_behavior_input) :
        contains([for o in values(var.origins) : o.origin_id], b.target_origin_id)
      ])
      error_message = "Each ordered cache behavior target_origin_id must match an origin_id in origins."
    }

    precondition {
      condition = var.kms_key_arn != null || alltrue([
        for b in values(local.ordered_cache_behavior_input) :
        !b.requires_signed_url
      ])
      error_message = "kms_key_arn is required when any ordered cache behavior has requires_signed_url = true."
    }

    precondition {
      condition = alltrue([
        for o in values(var.origins) :
        !o.is_private_origin || lower(try(o.origin_type, "s3")) == "s3"
      ])
      error_message = "is_private_origin can only be true for origins with origin_type = s3."
    }
  }

  # Origins
  dynamic "origin" {
    for_each = var.origins
    content {
      domain_name = origin.value.domain_name
      origin_id   = origin.value.origin_id
      origin_path = try(origin.value.origin_path, null)

      origin_access_control_id = (
        origin.value.is_private_origin && lower(try(origin.value.origin_type, "s3")) == "s3"
        ? aws_cloudfront_origin_access_control.this[origin.key].id
        : null
      )

      dynamic "s3_origin_config" {
        for_each = lower(try(origin.value.origin_type, "s3")) == "s3" ? [1] : []
        content {
          origin_access_identity = ""
        }
      }

      dynamic "custom_origin_config" {
        for_each = lower(try(origin.value.origin_type, "s3")) == "custom" ? [origin.value.custom_origin_config] : []
        content {
          http_port              = try(custom_origin_config.value.http_port, 80)
          https_port             = try(custom_origin_config.value.https_port, 443)
          origin_protocol_policy = try(custom_origin_config.value.origin_protocol_policy, "https-only")
          origin_ssl_protocols   = try(custom_origin_config.value.origin_ssl_protocols, ["TLSv1.2"])
          origin_read_timeout    = try(custom_origin_config.value.origin_read_timeout, 30)
          origin_keepalive_timeout = try(custom_origin_config.value.origin_keepalive_timeout, 5)
        }
      }
    }
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id         = local.default_cache_behavior_input.target_origin_id
    viewer_protocol_policy   = try(local.default_cache_behavior_input.viewer_protocol_policy, "redirect-to-https")
    allowed_methods          = try(local.default_cache_behavior_input.allowed_methods, ["GET", "HEAD", "OPTIONS"])
    cached_methods           = try(local.default_cache_behavior_input.cached_methods, ["GET", "HEAD"])
    cache_policy_id = coalesce(
      try(local.default_cache_behavior_input.cache_policy_id, null),
      data.aws_cloudfront_cache_policy.caching_optimized.id
    )
    origin_request_policy_id = coalesce(
      try(local.default_cache_behavior_input.origin_request_policy_id, null),
      data.aws_cloudfront_origin_request_policy.s3_origin.id
    )
    realtime_log_config_arn = var.realtime_log_config != null ? aws_cloudfront_realtime_log_config.this[0].arn : null

    dynamic "function_association" {
      for_each = try(local.default_cache_behavior_input.function_associations, {})
      content {
        event_type   = try(function_association.value.event_type, "viewer-request")
        function_arn = function_association.value.function_arn
      }
    }
  }

  # Ordered cache behaviors
  dynamic "ordered_cache_behavior" {
    for_each = local.ordered_cache_behavior_input
    content {
      path_pattern           = ordered_cache_behavior.value.path_pattern
      target_origin_id       = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy = try(ordered_cache_behavior.value.viewer_protocol_policy, "redirect-to-https")

      allowed_methods = ordered_cache_behavior.value.allowed_methods
      cached_methods  = ordered_cache_behavior.value.cached_methods

      cache_policy_id = coalesce(
        try(ordered_cache_behavior.value.cache_policy_id, null),
        ordered_cache_behavior.value.cache_disabled
        ? data.aws_cloudfront_cache_policy.caching_disabled.id
        : data.aws_cloudfront_cache_policy.caching_optimized.id
      )

      origin_request_policy_id = coalesce(
        try(ordered_cache_behavior.value.origin_request_policy_id, null),
        data.aws_cloudfront_origin_request_policy.s3_origin.id
      )
      realtime_log_config_arn = var.realtime_log_config != null ? aws_cloudfront_realtime_log_config.this[0].arn : null

      dynamic "function_association" {
        for_each = try(ordered_cache_behavior.value.function_associations, {})
        content {
          event_type   = try(function_association.value.event_type, "viewer-request")
          function_arn = function_association.value.function_arn
        }
      }

      trusted_key_groups = (
        lookup(ordered_cache_behavior.value, "requires_signed_url", false) && var.kms_key_arn != null
        ? [aws_cloudfront_key_group.signed_urls[0].id]
        : null
      )
    }
  }

  # SPA fallback
  dynamic "custom_error_response" {
    for_each = var.spa_fallback ? var.spa_fallback_status_codes : []
    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = "/${var.default_root_object}"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "logging_config" {
    for_each = var.logging == null ? [] : [var.logging]
    content {
      bucket          = logging_config.value.bucket
      include_cookies = logging_config.value.include_cookies
      prefix          = logging_config.value.prefix
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? var.ssl_support_method : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? var.minimum_protocol_version : null
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudfront" {
  for_each = local.enabled_cloudwatch_metric_alarms

  alarm_name          = coalesce(try(each.value.alarm_name, null), "${var.distribution_name}-${each.key}")
  alarm_description   = try(each.value.alarm_description, null)
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = try(each.value.namespace, "AWS/CloudFront")
  period              = each.value.period
  statistic           = try(each.value.statistic, null)
  extended_statistic  = try(each.value.extended_statistic, null)
  threshold           = each.value.threshold

  datapoints_to_alarm       = try(each.value.datapoints_to_alarm, null)
  treat_missing_data        = try(each.value.treat_missing_data, null)
  alarm_actions             = try(each.value.alarm_actions, [])
  ok_actions                = try(each.value.ok_actions, [])
  insufficient_data_actions = try(each.value.insufficient_data_actions, [])

  dimensions = merge(
    {
      DistributionId = aws_cloudfront_distribution.this.id
      Region         = "Global"
    },
    try(each.value.dimensions, {})
  )

  tags = merge(var.tags, try(each.value.tags, {}), {
    Name = coalesce(try(each.value.alarm_name, null), "${var.distribution_name}-${each.key}")
  })
}

resource "aws_cloudfront_monitoring_subscription" "this" {
  count = var.realtime_metrics_subscription_enabled ? 1 : 0

  distribution_id = aws_cloudfront_distribution.this.id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}
