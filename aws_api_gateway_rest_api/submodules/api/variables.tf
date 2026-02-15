variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "binary_media_types" {
  type    = list(string)
  default = []
}

variable "minimum_compression_size" {
  type    = number
  default = null
}

variable "api_key_source" {
  type    = string
  default = "HEADER"
}

variable "disable_execute_api_endpoint" {
  type    = bool
  default = false
}

variable "endpoint_configuration_types" {
  type    = list(string)
  default = ["REGIONAL"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
