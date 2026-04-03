variable "function_name" {
  description = "The Lambda function name."
  type        = string
}

variable "source_file" {
  description = "Absolute or relative path to the Lambda source file."
  type        = string
}

variable "handler" {
  description = "The Lambda handler entrypoint."
  type        = string
  default     = "app.handler"
}

variable "runtime" {
  description = "Lambda runtime version."
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "memory_size" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 256
}

variable "dynamodb_table_name" {
  description = "The DynamoDB table used by the Lambda."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table used by the Lambda."
  type        = string
}

variable "audit_bucket_name" {
  description = "The S3 bucket where audit records are stored."
  type        = string
}

variable "audit_bucket_arn" {
  description = "The ARN of the S3 audit bucket."
  type        = string
}

variable "audit_prefix" {
  description = "The prefix used for objects written to the audit bucket."
  type        = string
  default     = "audit"
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention period."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to Lambda resources."
  type        = map(string)
  default     = {}
}
