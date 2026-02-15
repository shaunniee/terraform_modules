variable "rest_api_id" {
  type = string
}

variable "stage_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "base_path" {
  type    = string
  default = null
}

variable "security_policy" {
  type    = string
  default = "TLS_1_2"
}

variable "create_route53_record" {
  type    = bool
  default = false
}

variable "hosted_zone_id" {
  type    = string
  default = null
}

variable "record_name" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
