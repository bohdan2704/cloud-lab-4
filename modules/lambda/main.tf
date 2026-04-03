terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  audit_prefix = trim(var.audit_prefix, "/")
  audit_path   = local.audit_prefix == "" ? "${var.audit_bucket_arn}/*" : "${var.audit_bucket_arn}/${local.audit_prefix}/*"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = var.source_file
  output_path = "${path.module}/${var.function_name}.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-role"

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

  tags = merge(var.tags, { Name = "${var.function_name}-role" })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "app_access" {
  name = "${var.function_name}-app-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "NotesTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan"
        ]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid      = "AuditLogWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = local.audit_path
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
  tags              = merge(var.tags, { Name = "/aws/lambda/${var.function_name}" })
}

resource "aws_lambda_function" "api_handler" {
  function_name    = var.function_name
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn
  handler          = var.handler
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size

  environment {
    variables = {
      TABLE_NAME   = var.dynamodb_table_name
      AUDIT_BUCKET = var.audit_bucket_name
      AUDIT_PREFIX = local.audit_prefix
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.app_access,
    aws_iam_role_policy_attachment.lambda_logs
  ]

  tags = merge(var.tags, { Name = var.function_name })
}
