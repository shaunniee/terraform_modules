resource "aws_route53_zone" "this" {
  for_each = var.zones

  name    = each.value.domain_name
  comment = lookup(each.value, "comment", null)

  dynamic "vpc" {
    for_each = each.value.private ? each.value.vpc_ids : []
    content {
      vpc_id = vpc.value
    }
  }
}

locals {
  # Merge created zone IDs with externally-provided zone IDs.
  # Created zones take precedence if the same key appears in both.
  all_zone_ids = merge(
    var.existing_zone_ids,
    { for k, z in aws_route53_zone.this : k => z.zone_id }
  )
}

resource "aws_route53_health_check" "this" {
  for_each = var.health_checks

  type              = each.value.type
  fqdn              = each.value.fqdn
  port              = lookup(each.value, "port", null)
  resource_path     = lookup(each.value, "resource_path", null)
  request_interval  = each.value.request_interval
  failure_threshold = each.value.failure_threshold
  measure_latency   = each.value.measure_latency

  regions = lookup(each.value, "regions", null)
  tags = {
    Name = each.key
  }
}

locals {
  flat_records = flatten([
    for zone_key, zone_records in var.records : [
      for record_name, record in zone_records : {
        zone_key = zone_key
        name     = record_name
        config   = record
      }
    ]
  ])
}

resource "aws_route53_record" "this" {
  for_each = {
    for r in local.flat_records :
    "${r.zone_key}-${r.name}-${coalesce(try(r.config.routing_policy.set_identifier, null), "default")}" => r
  }

  zone_id = local.all_zone_ids[each.value.zone_key]
  name    = each.value.name
  type    = each.value.config.type

  ttl     = each.value.config.alias != null ? null : each.value.config.ttl
  records = each.value.config.alias != null ? null : each.value.config.values

  dynamic "alias" {
    for_each = each.value.config.alias != null ? [each.value.config.alias] : []
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = alias.value.evaluate_target_health
    }
  }

  set_identifier = try(each.value.config.routing_policy.set_identifier, null)

  dynamic "weighted_routing_policy" {
    for_each = try(each.value.config.routing_policy.type, "simple") == "weighted" ? [1] : []
    content {
      weight = each.value.config.routing_policy.weight
    }
  }

  dynamic "latency_routing_policy" {
    for_each = try(each.value.config.routing_policy.type, "simple") == "latency" ? [1] : []
    content {
      region = each.value.config.routing_policy.region
    }
  }

  dynamic "failover_routing_policy" {
    for_each = try(each.value.config.routing_policy.type, "simple") == "failover" ? [1] : []
    content {
      type = each.value.config.routing_policy.failover
    }
  }

  dynamic "geolocation_routing_policy" {
    for_each = try(each.value.config.routing_policy.type, "simple") == "geolocation" ? [1] : []
    content {
      continent   = try(each.value.config.routing_policy.continent, null)
      country     = try(each.value.config.routing_policy.country, null)
      subdivision = try(each.value.config.routing_policy.subdivision, null)
    }
  }

  health_check_id = try(each.value.config.routing_policy.health_check_id, null)
}
