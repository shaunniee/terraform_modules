output "zone_ids" {
  value = {
    for k, z in aws_route53_zone.this :
    k => z.zone_id
  }
}

output "name_servers" {
  value = {
    for k, z in aws_route53_zone.this :
    k => z.name_servers
  }
}

output "health_check_ids" {
  value = {
    for k, hc in aws_route53_health_check.this :
    k => hc.id
  }
}
