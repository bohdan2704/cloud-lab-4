variable "api_name" {
  description = "The name of the HTTP API."
  type        = string
}

variable "lambda_function_name" {
  description = "The Lambda function name that API Gateway invokes."
  type        = string
}

variable "lambda_invoke_arn" {
  description = "The Lambda invoke ARN used by API Gateway."
  type        = string
}

variable "route_keys" {
  description = "A list of HTTP API route keys."
  type        = list(string)
  default = [
    "POST /notes",
    "GET /notes",
    "GET /notes/{id}",
    "PUT /notes/{id}",
    "DELETE /notes/{id}",
  ]
}

variable "tags" {
  description = "Tags applied to API Gateway resources."
  type        = map(string)
  default     = {}
}
