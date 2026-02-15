resource "aws_api_gateway_rest_api" "this" {
  name                         = var.name
  description                  = var.description
  binary_media_types           = var.binary_media_types
  minimum_compression_size     = var.minimum_compression_size
  api_key_source               = var.api_key_source
  disable_execute_api_endpoint = var.disable_execute_api_endpoint

  endpoint_configuration {
    types = var.endpoint_configuration_types
  }

  tags = var.tags
}
