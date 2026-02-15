variable "rest_api_id" {
  type = string
}

variable "root_resource_id" {
  type = string
}

variable "resources" {
  type = map(object({
    path_part  = string
    parent_key = optional(string)
  }))
  default = {}
}
