locals {
  create_role      = var.execution_role_arn == null
  lambda_role_arn  = local.create_role ? aws_iam_role.lambda_role[0].arn : var.execution_role_arn
  lambda_role_name = local.create_role ? aws_iam_role.lambda_role[0].name : null
  create_log_group = var.create_cloudwatch_log_group
  log_group_name   = "/aws/lambda/${var.function_name}"
}

resource "aws_iam_role" "lambda_role" {
  count = local.create_role ? 1 : 0

  name = "${var.function_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.function_name}-lambda-role"
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  count = local.create_role ? 1 : 0

  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda" {
  count = local.create_log_group ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.function_name}-log-group"
  })
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = local.lambda_role_arn
  description   = var.description
  handler       = var.handler
  runtime       = var.runtime
  filename      = var.filename

  timeout                        = var.timeout
  memory_size                    = var.memory_size
  publish                        = var.publish
  architectures                  = var.architectures
  layers                         = var.layers
  reserved_concurrent_executions = var.reserved_concurrent_executions
  kms_key_arn                    = var.kms_key_arn
  source_code_hash               = filebase64sha256(var.filename)

  environment {
    variables = var.environment_variables
  }

  ephemeral_storage {
    size = var.ephemeral_storage_size
  }

  tags = merge(var.tags, {
    Name = "${var.function_name}-function"
  })

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_cloudwatch_log_group.lambda
  ]
}
