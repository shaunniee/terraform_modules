output "zone_ids" {
  description = "All zone IDs — both created and externally provided — merged into a single map."
  value       = local.all_zone_ids
}

output "created_zone_ids" {
  description = "Zone IDs for zones created by this module (excludes existing_zone_ids)."
  value = {
    for k, z in aws_route53_zone.this :
    k => z.zone_id
  }
}

output "name_servers" {
  description = "Name servers for zones created by this module."
  value = {
    for k, z in aws_route53_zone.this :
    k => z.name_servers
  }
}

output "health_check_ids" {
  description = "Health check IDs keyed by health check name."
  value = {
    for k, hc in aws_route53_health_check.this :
    k => hc.id
  }
}
