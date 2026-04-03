terraform {
  required_version = ">= 1.10.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  aws_region = "eu-central-1"
  prefix     = "gogol-bohdan-02"

  common_tags = {
    Environment = "dev"
    Group       = "OI-44"
    Project     = "serverless-lab4"
    Student     = "Gogol Bohdan"
    Variant     = "02"
  }

  api_name         = "${local.prefix}-http-api"
  audit_bucket_key = "${local.prefix}-audit-${data.aws_caller_identity.current.account_id}"
  lambda_name      = "${local.prefix}-notes-api"
  notes_table_name = "${local.prefix}-notes"
}

provider "aws" {
  region = local.aws_region
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "audit_logs" {
  bucket = local.audit_bucket_key
  tags   = merge(local.common_tags, { Name = local.audit_bucket_key })
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name = local.notes_table_name
  tags       = local.common_tags
}

module "lambda" {
  source = "../../modules/lambda"

  function_name         = local.lambda_name
  source_file           = "${path.root}/../../src/app.py"
  dynamodb_table_name   = module.dynamodb.table_name
  dynamodb_table_arn    = module.dynamodb.table_arn
  audit_bucket_name     = aws_s3_bucket.audit_logs.bucket
  audit_bucket_arn      = aws_s3_bucket.audit_logs.arn
  audit_prefix          = "notes-audit"
  log_retention_in_days = 14
  tags                  = local.common_tags
}

module "api_gateway" {
  source = "../../modules/api_gateway"

  api_name             = local.api_name
  lambda_function_name = module.lambda.function_name
  lambda_invoke_arn    = module.lambda.invoke_arn
  route_keys = [
    "POST /notes",
    "GET /notes",
    "GET /notes/{id}",
    "PUT /notes/{id}",
    "DELETE /notes/{id}",
  ]
  tags = local.common_tags
}

output "api_url" {
  description = "Base URL of the deployed HTTP API."
  value       = module.api_gateway.api_endpoint
}

output "audit_bucket_name" {
  description = "S3 bucket used to store audit logs."
  value       = aws_s3_bucket.audit_logs.bucket
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function."
  value       = module.lambda.function_name
}

output "notes_table_name" {
  description = "Name of the DynamoDB table."
  value       = module.dynamodb.table_name
}
