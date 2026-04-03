output "function_name" {
  description = "The deployed Lambda function name."
  value       = aws_lambda_function.api_handler.function_name
}

output "invoke_arn" {
  description = "The invoke ARN for API Gateway integration."
  value       = aws_lambda_function.api_handler.invoke_arn
}

output "function_arn" {
  description = "The Lambda function ARN."
  value       = aws_lambda_function.api_handler.arn
}
